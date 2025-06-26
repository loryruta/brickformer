#include "MainScreen.h"

#include <glad/gl.h>
#include <imgui.h>

#include "App.h"
#include "AuthScreen.h"
#include "BrickColors.h"
#include "Converter.h"
#include "UIStyle.h"
#include "imgui_internal.h"
#include "io/BrickModelIO.h"
#include "log.h"
#include "model/GltfLoader.h"

#define ARP_LOG_CONTEXT "MainScreen"

using namespace bf;

void ui::ViewSettingsWindow::show()
{
    if (ui_window("View Settings")) {
        ImGui::Checkbox("Show model", &show_model);
        // ImGui::Checkbox("Show Brick height adjustment", &perform_brick_height_adjustment);
        ImGui::Checkbox("Show grid", &show_grid);
        ImGui::Checkbox("Show brick model", &show_brick_model);
        ImGui::Checkbox("Show brick plane", &show_brick_plane);
        ImGui::Checkbox("SSAO", &ssao);
        ImGui::Checkbox("Orbit camera", &orbit_camera);
        ui_slider_float("Orbit speed", &orbit_speed, 0.1f, 8.0f);
    }
    ImGui::End();
}

void ui::MapsWindow::show()
{
    if (ui_window("Maps")) {
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
    m_camera.m_position = glm::vec3(0, 1, 0);

    BrickColors& colors = BrickColors::get();
    colors.upload_colors();

    /* UI */
    m_ui.input_window = std::make_unique<InputWindow>(*this);
    m_ui.user_window = std::make_unique<UserWindow>();
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

    m_ui.brick_model_window = std::make_unique<BrickModelWindow>(*this);
    m_ui.brick_colors_window = std::make_unique<BrickColorsWindow>();

    // Start user sync daemon
    User& user = User::get();
    if (!user.is_anonymous()) {
        m_user_sync_daemon = std::make_unique<UserSyncDaemon>(user);

        auto redirect_to_auth_screen = [](std::string error) {
            g_app->enqueue_job([error]() { g_app->set_screen(std::make_shared<AuthScreen>(error)); });
        };
        m_user_sync_daemon->user_auth_error = redirect_to_auth_screen;
        m_user_sync_daemon->user_document_retrieve_error = redirect_to_auth_screen;

        m_user_sync_daemon->start();
    }
}

MainScreen::~MainScreen()
{
    // When destroyed, make sure to show up the cursor again
    Window& window = g_app->window();
    glfwSetInputMode(window.handle(), GLFW_CURSOR, GLFW_CURSOR_NORMAL);
}

void MainScreen::update(float dt)
{
    if (m_ui.view_settings.orbit_camera) {
        if (m_model) {
            int resolution = m_ui.input_window->resolution;
            glm::mat4 model_orientation = m_ui.input_window->model_orientation();
            glm::mat4 transform = Converter::model2brick_matrix(*m_model, model_orientation, resolution);
            glm::vec3 a = transform * glm::vec4(m_model->m_min, 1.0f);
            glm::vec3 max_ = transform * glm::vec4(m_model->m_max, 1.0f);
            glm::vec3 min_ = glm::min(a, max_); // Should be zero
            max_ = glm::max(a, max_);
            glm::vec3 middle = (max_ + min_) * 0.5f;
            glm::vec3 size = max_ - min_;
            float h = size.y;
            float diag = glm::sqrt(size.x * size.x + size.z * size.z) * 0.5f;
            float r = diag * 3.1f;
            m_camera.m_position = middle + diag;
            double t = glfwGetTime();
            float speed = m_ui.view_settings.orbit_speed;
            m_camera.m_position.x = middle.x + r * glm::sin(t * speed);
            m_camera.m_position.z = middle.z + r * glm::cos(t * speed);
            m_camera.m_position.y = middle.y + h * 1.4f;
            m_camera.look_at(middle);
        }
    }
}

void MainScreen::render() {}

void MainScreen::ui()
{
    ImGui::DockSpaceOverViewport();

    ImGuiWindowClass notabbar_class;
    notabbar_class.DockNodeFlagsOverrideSet = ImGuiDockNodeFlags_NoTabBar;

    ImGui::SetNextWindowClass(&notabbar_class);
    if (ImGui::Begin("LeftSidebar", nullptr)) {
        ImGuiID dockspace_id = ImGui::GetID("LeftSidebarDockspace");
        ImGui::DockSpace(dockspace_id);
    }
    ImGui::End();

    ImGui::SetNextWindowClass(&notabbar_class);
    if (ImGui::Begin("RightSidebar", nullptr)) {
        ImGuiID dockspace_id = ImGui::GetID("RightSidebarDockspace");
        ImGui::DockSpace(dockspace_id);
    }
    ImGui::End();

    m_ui.user_window->ui();
    m_ui.view_settings.show();
    ImGui::SetNextWindowClass(&notabbar_class);
    m_ui.view_3d_window->ui();

    bool is_converting = bool(m_converter);

    if (is_converting) {
        m_ui.conversion_window->ui();
        m_ui.maps.show();
    } else {
        m_ui.input_window->ui();
        m_ui.brick_colors_window->ui();
    }

    if (m_brick_model) {
        m_ui.brick_model_window->ui();
    }
}

void MainScreen::on_placement_end(uint32_t slice_y, const std::vector<Placement>& placements)
{
    g_app->enqueue_job([this, slice_y]() {
        BrickModelWindow& view_conversion_window = *m_ui.brick_model_window;
        if (view_conversion_window.current_subslice_catch_conversion) {
            view_conversion_window.current_subslice = (int) slice_y;
        }
    });

    if (!m_converter->m_stop) {
        if (!m_converter_autorun) {
            m_converter_should_run = false;
            m_converter_should_run.wait(false); // Block as long as the flag remains false
        }
    }
}

void MainScreen::set_brick_model(std::shared_ptr<BrickModel> brick_model, bool visualize)
{
    m_brick_model = std::move(brick_model);
    const Model& model = m_brick_model->model();
    m_baked_brick_model = std::make_unique<BrickRenderer_BakedModel>(BrickRenderer::bake_model(model));

    if (visualize) {
        m_ui.view_settings.show_model = false;
        m_ui.view_settings.show_grid = false;
        m_ui.view_settings.show_brick_model = true;
        m_ui.view_settings.show_brick_plane = true;
    }
}

void MainScreen::clear_brick_model()
{
    m_brick_model.reset();
    m_baked_brick_model.reset();
    m_ui.view_settings.show_model = true;
    m_ui.view_settings.show_grid = true;

    // If the brick model is discarded while the conversion is running, stop the conversion as well
    if (m_converter) stop_conversion(true);
}

void MainScreen::render_3d_scene()
{
    glClearColor(0.6f, 0.6f, 0.6f, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    GLint viewport[4];
    glGetIntegerv(GL_VIEWPORT, viewport);
    m_camera.m_aspect_ratio = float(viewport[2]) / float(viewport[3]); // width / height

    // Render model
    if (m_ui.view_settings.show_model) {
        if (m_baked_model) {
            glm::mat4 model_orientation = m_ui.input_window->model_orientation();
            int resolution = m_ui.input_window->resolution;
            glm::mat4 transform = glm::identity<glm::mat4>();
            transform[1][1] *= 1.2f; // Undo brick height adjustment
            transform *= Converter::model2brick_matrix(*m_model, model_orientation, resolution);
            g_app->model_renderer().m_ssao = m_ui.view_settings.ssao;
            g_app->model_renderer().m_alpha_test_threshold = m_ui.input_window->alpha_test_threshold;
            g_app->model_renderer().render(*m_baked_model, m_camera, transform);
        }
    }

    // Render grid
    if (m_ui.view_settings.show_grid) {
        if (m_baked_model) {
            int resolution = m_ui.input_window->resolution;

            GridRenderer::RenderParams params{};
            params.camera = m_camera;
            params.min = glm::vec3(0, 0, 0);
            params.divisions.x = resolution;
            int num_slices = calc_num_slices(*m_model, resolution);
            params.divisions.y = num_slices;
            params.divisions.z = resolution;
            params.max = glm::vec3(resolution, num_slices, resolution);
            params.half_border_size = 0.06f;
            g_app->grid_renderer().render(params);
        }
    }

    // Render brick model
    if (m_ui.view_settings.show_brick_model) {
        if (m_brick_model && m_baked_brick_model) {
            BrickRenderer_RenderParams params{};
            params.baked_model = m_baked_brick_model.get();
            params.camera = &m_camera;
            params.transform = glm::identity<glm::mat4>();
            params.kernel_r = 1;
            params.border_color = glm::vec4(0, 0, 0, 1); // Black
            params.start_vertex = 0;                     // Always start from the bottom slice
            const auto& subslice_ranges = m_brick_model->subslice_ranges();
            if (!subslice_ranges.empty()) {
                int& current_subslice = m_ui.brick_model_window->current_subslice;
                if (current_subslice >= subslice_ranges.size()) current_subslice = subslice_ranges.size() - 1;
                params.end_vertex = subslice_ranges.at(current_subslice).second;
                g_app->brick_renderer().render(params);
            }
        }
    }

    // Render the brick plane
    if (m_ui.view_settings.show_brick_plane) {
        g_app->brick_plane_renderer().render(0, m_camera, 0);
    }
}

void MainScreen::load_and_display_model(const std::filesystem::path& model_filepath)
{
    GltfLoader gltf_loader{};
    m_model = std::make_unique<Model>(gltf_loader.load_file(model_filepath));
    m_baked_model = std::make_unique<BakedModel>(ModelRenderer::bake_model(*m_model));
    m_ui.view_settings.show_model = true;
}

void MainScreen::start_conversion()
{
    CHECK_STATE(!m_converter, "Conversion already started");

    m_ui.view_settings.show_grid = false;

    int resolution = m_ui.input_window->resolution;

    // Init the converter
    ConverterParams params{};
    params.model_path = m_ui.input_window->model_path.string();
    params.resolution = resolution;
    params.model_orientation = m_ui.input_window->model_orientation();
    params.use_subslices = false;
    params.alpha_test_threshold = m_ui.input_window->alpha_test_threshold;
    params.proximity_max_value = m_ui.input_window->proximity_max_value;
    params.proximity_threshold = m_ui.input_window->proximity_threshold;
    m_converter = std::make_unique<Converter>(params);
    // Setup the conversion visualization bridge (internally set itself as a listener)
    m_converter_visualization_bridge = std::make_unique<ConverterVisualizationBridge>(*this);
    // Add MainScreen as a listener (must be the last one)
    m_converter->add_listener(this);

    /* Brick Model */
    // Discard any previously created brick model:
    // if the user has loaded a pre-saved conversion this will be unloaded to give precedence to the new conversion
    m_brick_model = m_converter_visualization_bridge->brick_model();
    m_ui.brick_model_window->current_subslice = 0;
    m_ui.brick_model_window->current_subslice_catch_conversion = true;

    /* UI */
    m_ui.view_settings.show_model = false;
    // Maps UI textures -> Visualization bridge textures
    m_ui.maps.color_map = m_converter_visualization_bridge->color_map_texture();
    for (int subslice = 0; subslice < 3; ++subslice) {
        m_ui.maps.hashed_placement_maps[subslice] =
            m_converter_visualization_bridge->placement_map_hashed_color_texture(subslice);
        m_ui.maps.colored_placement_maps[subslice] =
            m_converter_visualization_bridge->placement_map_color_texture(subslice);
    }
    m_ui.maps.proximity_map = m_converter_visualization_bridge->proximity_map_texture();
    m_ui.conversion_window = std::make_unique<ConversionWindow>(*this);

    // Start the Converter thread
    m_converter_thread = std::make_unique<std::thread>([this]() { m_converter->start(); });
}

void MainScreen::stop_conversion(bool discard)
{
    if (!m_converter) return;

    ARP_INFO("Conversion stopped");

    CHECK_STATE(m_converter);
    CHECK_STATE(m_converter_thread);

    // TODO Empty the queue of jobs in the application ?

    m_converter->m_stop = true;
    m_converter_autorun = false;   // Reset autorun to its default state
    m_converter_should_run = true; // Unblock the thread if it's waiting
    m_converter_should_run.notify_all();
    m_converter_thread->join();

    m_converter.reset();
    m_converter_thread.reset();
    m_converter_visualization_bridge.reset();

    if (discard) {
        if (m_brick_model) clear_brick_model();
        m_ui.view_settings.show_model = true;
        m_ui.view_settings.show_grid = true;
    } else {
        // Keep the brick model for visualization
    }

    /* Clean Conversion UI */
    m_ui.conversion_window.reset();
    // m_ui.maps
}
