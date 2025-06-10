#include "MainScreen.h"

#include <glad/gl.h>
#include <imgui.h>
#include <nfd.h>

#include "App.h"
#include "Converter.h"
#include "log.hpp"
#include "model/GltfLoader.hpp"

#define ARP_LOG_CONTEXT "MainScreen"

using namespace lego_builder;

void ui::InputWindow::show()
{
    if (ImGui::Begin("##Input")) {
        ImGui::Text("Model: %s", model_path.filename().c_str());

        if (ImGui::Button("Select a model")) {
            nfdu8char_t* out_path;
            nfdu8filteritem_t filters[]{{"glTF", "gltf,glb"}};
            nfdopendialogu8args_t args{};
            args.filterList = filters;
            args.filterCount = 1;

            nfdresult_t nfd_result = NFD_OpenDialogU8_With(&out_path, &args);
            if (nfd_result == NFD_OKAY) {
                std::filesystem::path tmp_model_path = out_path;
                if (!std::filesystem::exists(tmp_model_path)) {
                    printf("[ERROR] [InputForm] Invalid path: %s!\n", tmp_model_path.c_str());
                } else if (std::filesystem::is_directory(tmp_model_path)) {
                    printf("[ERROR] [InputForm] Not a file: %s\n", tmp_model_path.c_str());
                } else if (tmp_model_path.extension() != ".glb" && tmp_model_path.extension() != ".gltf") {
                    printf("[ERROR] [InputForm] Invalid extension (supported .glb/.gltf): %s\n",
                           tmp_model_path.extension().c_str());
                } else {
                    printf("[INFO ] [InputForm] Selected model: %s\n", out_path);
                    model_path = tmp_model_path;
                    if (on_input_change) on_input_change();
                }
                NFD_FreePathU8(out_path);
            }
        }

        if (ImGui::SliderInt("Resolution", &resolution, 1, 256) && on_input_change) on_input_change();
        ImGui::Text("Num slices: %d", display_num_slices);

        if (ImGui::Checkbox("Flip X", &flip_x) && on_input_change) on_input_change();
        if (ImGui::Checkbox("Flip Y", &flip_y) && on_input_change) on_input_change();
        if (ImGui::Checkbox("Flip Z", &flip_z) && on_input_change) on_input_change();

        ImGui::Text("Alpha test threshold");
        if (ImGui::SliderFloat("###alpha_test_threshold", &alpha_test_threshold, 0.f, 0.999f) && on_input_change)
            on_input_change();

        ImGui::Text("Proximity");
        ImGui::Checkbox("Auto", &auto_proximity_settings);
        if (auto_proximity_settings) ImGui::BeginDisabled();
        ImGui::SliderInt("Max value", &proximity_max_value, 1, 254);
        ImGui::SliderInt("Threshold", &proximity_threshold, 1, 32);
        if (auto_proximity_settings) ImGui::EndDisabled();

        if (model_path.empty()) ImGui::BeginDisabled();
        if (ImGui::Button("Convert")) {
            if (on_submit) on_submit();
        }
        if (model_path.empty()) ImGui::EndDisabled();
    }
    ImGui::End();
}

void ui::ViewSettingsWindow::show()
{
    if (ImGui::Begin("View settings")) {
        ImGui::Checkbox("Show model", &show_model);
        ImGui::Checkbox("Show Brick height adjustment", &perform_brick_height_adjustment);
        ImGui::Checkbox("Show grid", &show_grid);
        ImGui::Checkbox("Show construction", &show_construction);
        ImGui::Checkbox("Show voxels", &show_voxels);
        ImGui::Checkbox("Ambient Occlusion", &ssao);
    }
    ImGui::End();
}

void ui::MapsWindow::show()
{
    if (ImGui::Begin("Maps")) {
        ImGui::RadioButton("Color map", (int*) &map_type, MapType_ColorMap);
        ImGui::RadioButton("Placement map", (int*) &map_type, MapType_PlacementMap);
        ImGui::RadioButton("Proximity map (previous slice)", (int*) &map_type, MapType_ProximityMap);

        GLuint texture = 0;

        // Color map
        if (map_type == MapType_ColorMap) {
            ImGui::NewLine();
            texture = color_map;
        }
        // Proximity map
        else if (map_type == MapType_ProximityMap) {
            ImGui::NewLine();
            texture = proximity_map;
        }
        // Placement map
        else if (map_type == MapType_PlacementMap) {
            if (ImGui::ArrowButton("subslice_left", ImGuiDir_Left) && subslice_idx > 0) {
                if (subslice_idx > 0) --subslice_idx;
            }
            ImGui::SameLine();
            if (ImGui::ArrowButton("subslice_right", ImGuiDir_Right) && subslice_idx < 2) {
                if (subslice_idx < 2) ++subslice_idx;
            }
            ImGui::SameLine();
            ImGui::Text("Slice %d/2", subslice_idx);
            ImGui::SameLine();
            ImGui::Checkbox("Color", &show_colored_placement_map);

            texture =
                show_colored_placement_map ? colored_placement_maps[subslice_idx] : hashed_placement_maps[subslice_idx];
        }

        ImVec2 image_size;
        image_size.x = ImGui::GetContentRegionAvail().x;
        image_size.y = ImGui::GetContentRegionAvail().x;

        ImGui::Image((ImTextureID) texture, image_size, ImVec2(0, 1), ImVec2(1, 0));
    }
    ImGui::End();
}

MainScreen::MainScreen()
{
    m_undo_brick_height_adjustment_matrix = glm::identity<glm::mat4>();
    m_undo_brick_height_adjustment_matrix[1][1] *= 1.2f;

    /* UI */
    m_ui.input.on_input_change = [this]() { on_input_change(); };
    m_ui.input.on_submit = [this]() { start_conversion(); };

    m_ui.view_3d_window = std::make_unique<ui::View3dWindow>(
        g_app->window(),
        [&]() { render_3d_scene(); },
        [&](const glm::vec3& dposition, float dyaw, float dpitch) {
            if (dposition.x != 0.f) m_camera.m_position += m_camera.right() * dposition.x;
            if (dposition.y != 0.f) m_camera.m_position += m_camera.up() * dposition.y;
            if (dposition.z != 0.f) m_camera.m_position += m_camera.forward() * dposition.z;
            if (dyaw != 0.f) m_camera.m_yaw += dyaw * 0.004f;
            if (dpitch != 0.f) m_camera.m_pitch += dpitch * 0.004f;
        });
}

void MainScreen::update(float dt)
{
    if (!m_freecam) {
        m_camera.m_position += m_camera.right() * dt * m_camera_speed;
        m_camera.look_at(m_model_bbox.get_center());
    }
}

void MainScreen::render() {}

void MainScreen::ui_conversion_window()
{
    if (ImGui::Begin("Conversion")) {
        if (!m_converter_should_run) {
            if (ImGui::Button("Resume")) {
                m_converter_should_run = true;
                m_converter_should_run.notify_all();
            }
        } else {
            if (ImGui::Button("Pause")) {
                m_converter_should_run = false;
            }
        }
        ImGui::SameLine();
        if (ImGui::Button("Stop")) {
            stop_conversion();
        }
        bool autorun = m_converter_autorun.load();
        if (ImGui::Checkbox("Autorun", &autorun)) {
            m_converter_autorun.store(autorun);
        }
    }
    ImGui::End();
}

void MainScreen::ui()
{
    ImGui::DockSpaceOverViewport();

    if (ImGui::Begin("LeftSidebar", nullptr, ImGuiWindowFlags_NoTitleBar)) {
        ImGuiID dockspace_id = ImGui::GetID("LeftSidebarDockspace");
        ImGui::DockSpace(dockspace_id);
    }
    ImGui::End();

    if (ImGui::Begin("RightSidebar", nullptr, ImGuiWindowFlags_NoTitleBar)) {
        ImGuiID dockspace_id = ImGui::GetID("RightSidebarDockspace");
        ImGui::DockSpace(dockspace_id);
    }
    ImGui::End();

    m_ui.input.show();
    if (m_converter) {
        ui_conversion_window();
    }
    m_ui.view_settings.show();
    m_ui.maps.show();
    m_ui.view_3d_window->show();
}

void MainScreen::on_placement_end(uint32_t slice_y, const std::vector<Placement>& placements)
{
    if (!m_converter_autorun) {
        m_converter_should_run = false;
        m_converter_should_run.wait(false); // Block until the flag should_run is false
    }
}

void MainScreen::render_3d_scene()
{
    glClearColor(0.6f, 0.6f, 0.6f, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    GLint viewport[4];
    glGetIntegerv(GL_VIEWPORT, viewport);
    m_camera.m_aspect_ratio = float(viewport[2]) / float(viewport[3]); // width / height

    g_app->model_renderer().m_ssao = m_ui.view_settings.ssao;

    // Render model
    if (m_ui.view_settings.show_model) {
        if (m_baked_model) {
            glm::mat4 transform{1.f};
            if (!m_ui.view_settings.perform_brick_height_adjustment) {
                transform *= m_undo_brick_height_adjustment_matrix;
            }
            transform *= m_model_to_view_transform;
            g_app->model_renderer().render(*m_baked_model, m_camera, transform);
        }
    }

    // Render grid
    if (m_ui.view_settings.show_grid) {
        if (m_baked_model) {
            int resolution = m_ui.input.resolution;

            GridRenderer::RenderParams params{};
            params.camera = m_camera;
            params.min = glm::vec3(0, 0, 0);
            params.divisions.x = resolution;
            params.divisions.y = calc_num_slices(*m_model, resolution);
            params.divisions.z = resolution;
            params.max = glm::vec3(params.divisions) / float(resolution) * k_max_view_side;
            params.half_border_size = 0.1f;

            g_app->grid_renderer().render(params);
        }
    }

    // Render brick model
    if (m_ui.view_settings.show_construction) {
        if (m_converter_visualization_bridge) {

            const std::unique_ptr<BrickRenderer_BakedModel>& brick_model = m_converter_visualization_bridge->brick_model();
            if (brick_model) {
                BrickRenderer_RenderParams params{};
                params.baked_model = brick_model.get();
                params.camera = &m_camera;
                params.kernel_r = 3;
                params.border_color = glm::vec4(0, 0, 0, 1); // Black
                g_app->brick_renderer().render(params);
            }
        }
    }

    // Render voxel model
    if (m_ui.view_settings.show_voxels) {
        if (m_converter_visualization_bridge) {
            const std::unique_ptr<BakedModel>& voxel_model = m_converter_visualization_bridge->voxel_model();
            if (voxel_model) {
                // g_app->model_renderer().render(*voxel_model, m_camera, m_conversion_to_view_transform);
            }
        }
    }
}

void MainScreen::on_input_change()
{
    stop_conversion();

    ui::InputWindow& input_ui = m_ui.input;

    // Proximity settings
    if (input_ui.auto_proximity_settings) {
        input_ui.proximity_threshold = Converter::calc_proximity_threshold(input_ui.resolution);
        input_ui.proximity_max_value = Converter::calc_proximity_max_value(input_ui.resolution);
    }

    if (input_ui.model_path.empty()) return;

    bool model_changed = m_view_model_path != input_ui.model_path;

    // Reload model if changed
    if (model_changed) {
        std::string model_path = input_ui.model_path;

        m_view_model_path = model_path;
        GltfLoader gltf_loader{};
        m_model = std::make_unique<Model>(gltf_loader.load_file(model_path));
        m_baked_model = std::make_unique<BakedModel>(ModelRenderer::bake_model(*m_model));
    }

    // Calculate transform from Model space to UI space (flip flags could have changed)
    m_model_to_view_transform = glm::identity<glm::mat4>();
    glm::vec3 model_size = m_model->size();
    glm::vec3 scale_matrix = glm::vec3(k_max_view_side / glm::max(model_size.x, model_size.z));
    m_model_to_view_transform = glm::scale(m_model_to_view_transform, glm::vec3(scale_matrix));
    m_model_to_view_transform = glm::translate(m_model_to_view_transform, -m_model->m_min);
    m_model->apply_flip(input_ui.flip_x, input_ui.flip_y, input_ui.flip_z, m_model_to_view_transform);

    // Update UI space bounding box
    glm::vec3 transformed_bbox_min = m_model_to_view_transform * glm::vec4(m_model->m_min, 1);
    glm::vec3 transformed_bbox_max = m_model_to_view_transform * glm::vec4(m_model->m_max, 1);
    m_model_bbox.min = glm::min(transformed_bbox_min,
                                transformed_bbox_max); // We can recalc min-max like this because we're not rotating
    m_model_bbox.max = glm::max(transformed_bbox_min, transformed_bbox_max);

    // Update num slices (UI)
    input_ui.display_num_slices = calc_num_slices(*m_model, input_ui.resolution);

    g_app->model_renderer().m_alpha_test_threshold = input_ui.alpha_test_threshold;

    // Reset camera
    if (model_changed) {
        glm::vec3 p = m_model_bbox.get_center();
        float camera_distance = glm::sqrt(p.x * p.x + p.z * p.z);
        camera_distance *= 1.3f;
        m_camera.m_position = p + glm::vec3(camera_distance, p.y / 2.0f, camera_distance);
        m_camera.look_at(p);
    }
}

void MainScreen::start_conversion()
{
    CHECK_STATE(!m_converter, "Conversion already started");

    m_ui.view_settings.show_grid = false;

    int resolution = m_ui.input.resolution;

    // Init the converter
    ConverterParams params{};
    params.model_path = m_ui.input.model_path;
    params.resolution = resolution;
    params.flip_x = m_ui.input.flip_x;
    params.flip_y = m_ui.input.flip_y;
    params.flip_z = m_ui.input.flip_z;
    m_converter = std::make_unique<Converter>(params);

    // Converter -> Visualization bridge (internally set itself as a listener)
    m_converter_visualization_bridge = std::make_unique<ConverterVisualizationBridge>(*m_converter);
    // Add MainScreen as a listener (must be the last one)
    m_converter->add_listener(this);

    // Maps UI textures -> Visualization bridge textures
    m_ui.maps.color_map = m_converter_visualization_bridge->color_map_texture();
    for (int subslice = 0; subslice < 3; ++subslice) {
        m_ui.maps.hashed_placement_maps[subslice] =
            m_converter_visualization_bridge->placement_map_hashed_color_texture(subslice);
        m_ui.maps.colored_placement_maps[subslice] =
            m_converter_visualization_bridge->placement_map_color_texture(subslice);
    }
    m_ui.maps.proximity_map = m_converter_visualization_bridge->proximity_map_texture();

    // Calculate view transforms
    m_conversion_to_view_transform = glm::identity<glm::mat4>();
    m_conversion_to_view_transform =
        glm::scale(m_conversion_to_view_transform, glm::vec3(k_max_view_side / resolution));

    // Start the Converter thread
    m_converter_thread = std::make_unique<std::thread>([this]() { m_converter->start(); });
}

void MainScreen::stop_conversion()
{
    if (!m_converter) {
        ARP_DEBUG("Clear conversion called, but nothing to clear");
        return;
    }

    ARP_INFO("Conversion stopped");

    CHECK_STATE(m_converter);
    CHECK_STATE(m_converter_thread);

    // TODO Empty the queue of jobs in the application
    m_converter->m_stop = true;
    m_converter_should_run = true; // Let another iteration so to stop
    m_converter_should_run.notify_all();
    m_converter_thread->join();

    m_converter.reset();
    m_converter_thread.reset();
    m_converter_visualization_bridge.reset();

    m_ui.view_settings.show_model = true;
}
