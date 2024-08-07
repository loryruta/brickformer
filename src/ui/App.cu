#include "App.cuh"

#include <GLFW/glfw3.h>
#include <glad/gl.h>
#include <imgui.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>
#include <nfd.h>

#include "bricks.hpp"
#include "model/GltfLoader.hpp"
#include "util/StopWatch.hpp"
#include "video/gl_helpers.hpp"

using namespace lego_builder;

App::App(Window& window) :
    m_window(window)
{
    // Initialize imgui
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;
    (void) io;

    ImGui_ImplGlfw_InitForOpenGL(m_window.handle(), true);
    ImGui_ImplOpenGL3_Init("#version 330");

    m_undo_brick_height_adjustment_matrix = glm::identity<glm::mat4>();
    m_undo_brick_height_adjustment_matrix[1][1] *= 1.2f;

    m_model_renderer = std::make_unique<ModelRenderer>();
    m_grid_renderer = std::make_unique<GridRenderer>();

    /* UI */
    m_ui_input.on_input_change = [this]() { on_input_change(); };
    m_ui_input.on_submit = [this]() { start_conversion(); };

    m_ui_view_3d_window = std::make_unique<ui::View3dWindow>(
        m_window, [&]() { render_3d_scene(); },
        [&](const glm::vec3& dposition, float dyaw, float dpitch)
        {
            if (dposition.x != 0.f)
                m_camera.m_position += m_camera.right() * dposition.x;
            if (dposition.y != 0.f)
                m_camera.m_position += m_camera.up() * dposition.y;
            if (dposition.z != 0.f)
                m_camera.m_position += m_camera.forward() * dposition.z;
            if (dyaw != 0.f)
                m_camera.m_yaw += dyaw * 0.004f;
            if (dpitch != 0.f)
                m_camera.m_pitch += dpitch * 0.004f;
        }
    );
}

App::~App()
{
    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();

    ImGui::DestroyContext();
}

void App::on_input_change()
{
    clear_conversion();

    ui::InputWindow& input_ui = m_ui_input;

    if (input_ui.model_path.empty())
        return;

    bool model_changed = m_view_model_path != input_ui.model_path;

    // Reload model if changed
    if (model_changed)
    {
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
    m_model_bbox.min = glm::min(transformed_bbox_min, transformed_bbox_max); // We can recalc min-max like this because we're not rotating
    m_model_bbox.max = glm::max(transformed_bbox_min, transformed_bbox_max);

    // Update num slices (UI)
    input_ui.display_num_slices = calc_num_slices(*m_model, input_ui.resolution);

    m_model_renderer->m_alpha_test_threshold = input_ui.alpha_test_threshold;

    // Reset camera
    if (model_changed)
    {
        glm::vec3 p = m_model_bbox.get_center();
        float camera_distance = glm::sqrt(p.x * p.x + p.z * p.z);
        camera_distance *= 1.3f;
        m_camera.m_position = p + glm::vec3(camera_distance, p.y / 2.0f, camera_distance);
        m_camera.look_at(p);
    }
}

void App::on_model_load(const Model& model) {}

void App::enqueue_and_wait_copy_maps_job()
{
    m_job_queue.push(
        [this]()
        {
            copy_color_map();
            copy_proximity_map();
            write_placement_maps(m_hashed_placement_map_cuda_mappings, true);
            write_placement_maps(m_colored_placement_map_cuda_mappings, false);
            add_placements_to_construction_model();
            add_color_map_voxels(); // TODO slow down too much
        }
    );

    // Wait for the pushed jobs to be executed before continuing (avoid concurrency)
    {
        std::unique_lock<std::mutex> lock(m_job_queue_mutex);
        m_job_queue_cond_var.wait(lock, [this]() { return m_job_queue.empty(); });
    }
}

void App::on_placement_begin(uint32_t slice_y)
{
    enqueue_and_wait_copy_maps_job();
    m_placement_stopwatch.reset();
}

void App::on_place(uint32_t slice_y, const Placement& placement, float reward)
{
    if (m_placement_stopwatch.elapsed_millis() >= 1000 * k_placement_visualization_period)
    {
        enqueue_and_wait_copy_maps_job();
        m_placement_stopwatch.reset();
    }
}

void App::on_placement_end(uint32_t slice_y)
{
    enqueue_and_wait_copy_maps_job();

    if (!m_autorun)
    {
        // Block until manually resumed (ENTER pressed)
        m_arpenteur_should_run = false;
        m_arpenteur_should_run.wait(false);
    }
}

glm::vec<4, uint8_t> eval_placement_hashed_color(const Placement& placement)
{
    static const PlacementHash k_hash_func{};
    uint64_t hash = k_hash_func(placement);

    glm::vec4 v{};
    v.x = glm::abs(glm::sin(hash * 0.147f)) * 255.0f;
    v.y = glm::abs(glm::cos(hash * 0.843f)) * 255.0f;
    v.z = glm::abs(glm::sin(hash * 0.239f)) * 255.0f;
    v.w = 255.0f;
    return v;
}

void App::copy_color_map()
{
    m_color_map_cuda_mapping->copy_from(m_arpenteur->m_color_map);
}

// TODO put in DeviceImage or utility file
template<uint32_t SRC_IMAGE_FORMAT, typename SRC_IMAGE_TYPE, uint32_t DST_IMAGE_FORMAT, typename DST_IMAGE_TYPE>
__global__ void transform_image_kernel(const DeviceImage<SRC_IMAGE_FORMAT, SRC_IMAGE_TYPE>* src_image, DeviceImage<DST_IMAGE_FORMAT, DST_IMAGE_TYPE>* dst_image)
{
    size_t x = blockIdx.x * blockDim.x + threadIdx.x;
    size_t y = blockIdx.y * blockDim.y + threadIdx.y;

    // printf("x: %d, y: %d, width: %d, height: %d\n", x, y, src_image->m_width, src_image->m_height);

    if (x < src_image->m_width && y < src_image->m_height)
    {
        auto v = src_image->read_pixel(x, y);
        // auto new_val = transform_func(v);
        dst_image->write_pixel(x, y, glm::vec<4, uint8_t>{(float(v.x & 0x7F) / float(PROXIMITY_MAP_HIGH_VALUE)) * 255.0f, 0, 0, 255});
    }
}

/// Transform the input image into the output image invoking a transform function on each source pixel.
template<uint32_t SRC_IMAGE_FORMAT, typename SRC_IMAGE_TYPE, uint32_t DST_IMAGE_FORMAT, typename DST_IMAGE_TYPE, typename TRANSFORM_FUNC>
void transform_image(
    const DeviceImage<SRC_IMAGE_FORMAT, SRC_IMAGE_TYPE>& src_image, DeviceImage<DST_IMAGE_FORMAT, DST_IMAGE_TYPE>& dst_image, TRANSFORM_FUNC transform_func
)
{
    assert(src_image.m_width == dst_image.m_width && src_image.m_height == dst_image.m_height);

    DeviceImage<SRC_IMAGE_FORMAT, SRC_IMAGE_TYPE>* src_image_d = to_device(src_image);
    DeviceImage<DST_IMAGE_FORMAT, DST_IMAGE_TYPE>* dst_image_d = to_device(dst_image);

    dim3 num_blocks{};
    num_blocks.x = div_ceil<uint32_t>(src_image.m_width, 32);
    num_blocks.y = div_ceil<uint32_t>(src_image.m_height, 32);
    num_blocks.z = 1;

    dim3 block_dim(32, 32, 1);
    transform_image_kernel<<<num_blocks, block_dim>>>(src_image_d, dst_image_d);
    CHECK_CU(cudaDeviceSynchronize());
}

__device__ glm::vec<4, uint8_t> transform_proximity_map(const glm::vec<1, uint8_t>& v)
{
    uint8_t new_val = float(v.x) / float(PROXIMITY_MAP_HIGH_VALUE) * 255.0f;

    printf("FROM %d TO %d\n", v.x, new_val);

    return glm::vec<4, uint8_t>{new_val, 0, 0, 255};
}

void App::copy_proximity_map()
{
    // Allocate a temporary image that hosts the conversion of the proximity map to RGBA (remember: proximity map is
    // a grayscale image). This is necessary as I've not found a way to directly write to a cudaArray (i.e. CUDA mapped
    // texture)
    DeviceImage<4, uint8_t> tmp_image = DeviceImage<4, uint8_t>::create(m_input.resolution, m_input.resolution, nullptr);

    tmp_image.fill(255);
    transform_image(m_arpenteur->m_prev_proximity_map, tmp_image, transform_proximity_map); // Fake CLion error :')

    m_proximity_map_cuda_mapping->copy_from(tmp_image);
}

void App::write_placement_maps(std::vector<CudaMappedGlTexture>& out_images, bool use_hashed_color)
{
    StopWatch stop_watch{};

    printf("[App] Writing placements to textures for visualization...\n");

    int resolution = m_input.resolution;

    DeviceImage<4, uint8_t> tmp_images[3];
    tmp_images[0] = DeviceImage<4, uint8_t>::create(resolution, resolution, nullptr);
    tmp_images[1] = DeviceImage<4, uint8_t>::create(resolution, resolution, nullptr);
    tmp_images[2] = DeviceImage<4, uint8_t>::create(resolution, resolution, nullptr);

    tmp_images[0].fill(0);
    tmp_images[1].fill(0);
    tmp_images[2].fill(0);

    for (ColoredPlacement& entry : m_arpenteur->m_colored_placements)
    {
        Placement& placement = entry.m_placement;
        uint8_t subslice_mask = entry.m_subslice_mask;
        assert(subslice_mask); // Shouldn't be zero

        glm::vec<4, uint8_t> color{};
        if (use_hashed_color)
        {
            color = eval_placement_hashed_color(placement);
        }
        else
        {
            color = entry.m_color;
            color.a = 255.0f;
        }

        auto& brick = k_bricks[placement.m_bid];
        for (int bz = 0; bz < BRICK_MAX_HEIGHT; bz++)
        {
            for (int bx = 0; bx < BRICK_MAX_WIDTH; bx++)
            {
                if (brick[bz][bx])
                {
                    if (subslice_mask & 0x1)
                        tmp_images[0].write_pixel(placement.m_x + bx, placement.m_y + bz, color);
                    if (subslice_mask & 0x2)
                        tmp_images[1].write_pixel(placement.m_x + bx, placement.m_y + bz, color);
                    if (subslice_mask & 0x4)
                        tmp_images[2].write_pixel(placement.m_x + bx, placement.m_y + bz, color);
                }
            }
        }
    }

    out_images[0].copy_from(tmp_images[0]);
    out_images[1].copy_from(tmp_images[1]);
    out_images[2].copy_from(tmp_images[2]);

    std::string duration_str = stop_watch.elapsed_time_str();
    printf("[App] Placements written in %s\n", duration_str.c_str());
}

void App::add_placements_to_construction_model()
{
    printf("[App] UPDATE CONSTRUCTION MODEL; Updating vertices...\n");

    for (ColoredPlacement& colored_placement : m_arpenteur->m_colored_placements)
    {
        m_brick_model_builder->place(
            m_arpenteur->m_slice_y, colored_placement.m_placement.m_x, colored_placement.m_placement.m_y, colored_placement.m_placement.m_bid,
            colored_placement.m_subslice_mask, glm::vec4{colored_placement.m_color} / 255.0f
        );
    }

    printf("[App] UPDATE CONSTRUCTION MODEL; Baking...\n");

    m_baked_construction_model = std::make_unique<BakedModel>(ModelRenderer::bake_model(m_brick_model_builder->model()));

    printf("[App] UPDATE CONSTRUCTION MODEL; Done\n");
}

void App::add_color_map_voxels()
{
    const ColorMapT& color_map = m_arpenteur->m_color_map;
    int slice_y = m_arpenteur->m_slice_y;

    std::vector<ColorMapT::PixelT> data(color_map.m_width * color_map.m_height);
    CHECK_CU(cudaMemcpy(data.data(), color_map.m_data, data.size() * sizeof(ColorMapT::PixelT), cudaMemcpyDeviceToHost));

    for (size_t i = 0; i < data.size(); i++)
    {
        if (data[i].a > 0)
        {
            int x = i % color_map.m_width;
            int z = i / color_map.m_width;
            glm::vec4 color = glm::vec4{data[i]} / 255.0f;
            m_voxel_model_builder->set_voxel(x, slice_y, z, color);
        }
    }

    m_baked_voxel_model = std::make_unique<BakedModel>(ModelRenderer::bake_model(m_voxel_model_builder->model()));
}

void App::render_3d_scene()
{
    glClearColor(0.6f, 0.6f, 0.6f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    GLint viewport[4];
    glGetIntegerv(GL_VIEWPORT, viewport);
    m_camera.m_aspect_ratio = float(viewport[2]) / float(viewport[3]); // width / height

    m_model_renderer->m_ssao = m_ui_view_settings.ssao;

    // Render model
    if (m_ui_view_settings.show_model)
    {
        if (m_baked_model)
        {
            glm::mat4 transform{1.f};
            if (!m_ui_view_settings.perform_brick_height_adjustment)
                transform *= m_undo_brick_height_adjustment_matrix;
            transform *= m_model_to_view_transform;

            m_model_renderer->render(*m_baked_model, m_camera, transform);
        }
    }

    // Render grid
    if (m_ui_view_settings.show_grid)
    {
        if (m_baked_model)
        {
            int resolution = m_ui_input.resolution;

            GridRenderer::RenderParams params{};
            params.camera = m_camera;
            params.min = glm::vec3(0, 0, 0);
            params.divisions.x = resolution;
            params.divisions.y = calc_num_slices(*m_model, resolution);
            params.divisions.z = resolution;
            params.max = glm::vec3(params.divisions) / float(resolution) * k_max_view_side;
            params.half_border_size = 0.1f;

            m_grid_renderer->render(params);
        }
    }

    // Render construction
    if (m_ui_view_settings.show_construction)
    {
        if (m_baked_construction_model)
        {
            m_model_renderer->render(*m_baked_construction_model, m_camera, m_conversion_to_view_transform);
        }
    }

    // Render voxels
    if (m_ui_view_settings.show_voxels)
    {
        if (m_baked_voxel_model)
        {
            m_model_renderer->render(*m_baked_voxel_model, m_camera, m_conversion_to_view_transform);
        }
    }

    // Update the camera to orbit around the model
    if (!m_freecam)
    {
        m_camera.m_position += m_camera.right() * m_dt * m_camera_speed;
        m_camera.look_at(m_model_bbox.get_center());
    }
}

void App::show_main_window()
{
    ImGui::DockSpaceOverViewport();

    if (ImGui::Begin("###LeftSidebarWindow", nullptr, ImGuiWindowFlags_NoTitleBar))
    {
        ImGuiID dockspace_id = ImGui::GetID("LeftSidebarDockspace");
        ImGui::DockSpace(dockspace_id);
    }
    ImGui::End();

    if (ImGui::Begin("###RightSidebarWindow", nullptr, ImGuiWindowFlags_NoTitleBar))
    {
        ImGuiID dockspace_id = ImGui::GetID("RightSidebarDockspace");
        ImGui::DockSpace(dockspace_id);
    }
    ImGui::End();
}

void App::render()
{
    show_main_window();
    m_ui_input.show();
    m_ui_view_settings.show();
    m_ui_maps_window.show();
    m_ui_view_3d_window->show();
}

void App::clear_conversion()
{
    if (!m_arpenteur)
        return;

    printf("[WARN ] [App] Conversion stopped\n");

    CHECK_STATE(m_arpenteur);
    CHECK_STATE(m_arpenteur_thread);

    while (!m_job_queue.empty())
        m_job_queue.pop();
    m_arpenteur->m_stop = true;
    m_arpenteur_should_run = true; // Let another iteration so to stop
    m_arpenteur_should_run.notify_all();
    m_arpenteur_thread->join();

    m_arpenteur_thread.reset();
    m_arpenteur.reset();
    m_color_map_cuda_mapping.reset();
    m_hashed_placement_map_cuda_mappings.clear();
    m_colored_placement_map_cuda_mappings.clear();
    m_proximity_map_cuda_mapping.reset();
    m_brick_model_builder.reset();
    m_baked_construction_model.reset();
    m_voxel_model_builder.reset();
    m_baked_voxel_model.reset();
}

void App::start_conversion()
{
    clear_conversion();

    CHECK_STATE(!m_arpenteur);
    CHECK_STATE(!m_arpenteur_thread);

    m_ui_view_settings.show_grid = false;

    int resolution = m_ui_input.resolution;

    m_input.model_path = m_ui_input.model_path;
    m_input.resolution = resolution;
    m_input.flip_x = m_ui_input.flip_x;
    m_input.flip_y = m_ui_input.flip_y;
    m_input.flip_z = m_ui_input.flip_z;
    m_arpenteur = std::make_unique<Arpenteur>(m_input);
    m_arpenteur->set_listener(this);

    // Calculate view transforms
    m_conversion_to_view_transform = glm::identity<glm::mat4>();
    m_conversion_to_view_transform = glm::scale(m_conversion_to_view_transform, glm::vec3(k_max_view_side / resolution));

    // Create maps (debug)
    m_color_map_cuda_mapping.emplace(create_gl_texture(resolution, resolution));

    m_hashed_placement_map_cuda_mappings.emplace_back(create_gl_texture(resolution, resolution)); // Subslice 0
    m_hashed_placement_map_cuda_mappings.emplace_back(create_gl_texture(resolution, resolution)); // Subslice 1
    m_hashed_placement_map_cuda_mappings.emplace_back(create_gl_texture(resolution, resolution)); // Subslice 2

    m_colored_placement_map_cuda_mappings.emplace_back(create_gl_texture(resolution, resolution)); // Subslice 0
    m_colored_placement_map_cuda_mappings.emplace_back(create_gl_texture(resolution, resolution)); // Subslice 1
    m_colored_placement_map_cuda_mappings.emplace_back(create_gl_texture(resolution, resolution)); // Subslice 2

    m_proximity_map_cuda_mapping.emplace(create_gl_texture(resolution, resolution));

    m_brick_model_builder = std::make_unique<BrickModelBuilder>(); // Construction model
    m_voxel_model_builder = std::make_unique<VoxelModelBuilder>(); // Voxel model

    // Link maps texture to UI
    m_ui_maps_window.color_map = m_color_map_cuda_mapping->texture();
    for (int subslice = 0; subslice < 3; ++subslice)
    {
        m_ui_maps_window.hashed_placement_maps[subslice] = m_hashed_placement_map_cuda_mappings[subslice].texture();
        m_ui_maps_window.colored_placement_maps[subslice] = m_colored_placement_map_cuda_mappings[subslice].texture();
    }
    m_ui_maps_window.proximity_map = m_proximity_map_cuda_mapping->texture();

    // Start l'Arpenteur
    m_arpenteur_thread = std::make_unique<std::thread>([this]() { m_arpenteur->run(); });
}

void App::run()
{
    m_window.set_key_callback(
        [&](int key, int scancode, int action, int mods)
        {
            bool is_autorun_pressed = key == GLFW_KEY_F1 && action == GLFW_PRESS;

            if ((key == GLFW_KEY_ENTER && action == GLFW_PRESS) || is_autorun_pressed)
            {
                // Resume the Arpenteur thread (by default it stops after a slice is completed)
                m_arpenteur_should_run = true;
                m_arpenteur_should_run.notify_all();
            }

            if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS)
                m_window.set_should_close(true); // Bye bye! :)

            if (is_autorun_pressed)
                m_autorun = !m_autorun;
        }
    );

    // Loop
    while (!m_window.should_close())
    {
        glBindFramebuffer(GL_FRAMEBUFFER, 0);

        glm::ivec2 framebuffer_size = m_window.get_framebuffer_size();
        glViewport(0, 0, framebuffer_size.x, framebuffer_size.y);

        double now = glfwGetTime();
        if (m_last_frame_t > 0.0f)
            m_dt = now - m_last_frame_t;
        m_last_frame_t = now;

        // Render
        m_window.begin_frame();

        glClearColor(0.0f, 0.4f, 0.0f, 0.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplGlfw_NewFrame();

        ImGui::NewFrame();

        render();

        ImGui::Render();
        ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());

        m_window.end_frame();

        // Execute all queued jobs
        while (!m_job_queue.empty())
        {
            std::function<void()> job = m_job_queue.pop();
            job();
        }

        m_job_queue_cond_var.notify_all(); // Notify arpenteur thread that the job queue is now empty
    }
}
