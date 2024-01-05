#include "App.cuh"

#include <GLFW/glfw3.h>
#include <glad/gl.h>
#include <imgui.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>

#include "bricks.cuh"
#include "util/StopWatch.hpp"
#include "video/gl_helpers.hpp"

using namespace lego_builder;


App::App(Window& window) :
    m_window(window)
{
    m_model_path = "/home/loryruta/CLionProjects/lego-builder/resources/models/shinto_shrine.glb";
    m_slice_side = 64;

    // Initialize imgui
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    (void) io;

    ImGui_ImplGlfw_InitForOpenGL(m_window.handle(), true);
    ImGui_ImplOpenGL3_Init("#version 330");

    //
    m_arpenteur = std::make_unique<Arpenteur>(m_model_path, m_slice_side, *this);

    m_color_map_cuda_mapping.emplace(create_gl_texture(m_slice_side, m_slice_side));
    m_proximity_map_cuda_mapping.emplace(create_gl_texture(m_slice_side, m_slice_side));
    m_subslice0_cuda_mapping.emplace(create_gl_texture(m_slice_side, m_slice_side));
    m_subslice1_cuda_mapping.emplace(create_gl_texture(m_slice_side, m_slice_side));
    m_subslice2_cuda_mapping.emplace(create_gl_texture(m_slice_side, m_slice_side));
}

App::~App()
{
    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();

    ImGui::DestroyContext();
}

void App::on_model_load(const Model& model)
{
    m_job_queue.push([this, model]()
    {
        m_baked_model = std::make_unique<BakedModel>(m_model_renderer.bake_model(model));

        glm::vec3 model_hsize = model.size() / 2.0f;
        m_look_at_position = model.m_min + model_hsize;

        float camera_distance = glm::sqrt(model_hsize.x * model_hsize.x + model_hsize.z * model_hsize.z);
        camera_distance *= 1.3f;
        m_camera.m_position = m_look_at_position + glm::vec3(camera_distance, model_hsize.y / 2.0f, camera_distance);
        m_camera.look_at(m_look_at_position);
    });
}

void App::enqueue_and_wait_copy_maps_job()
{
    m_job_queue.push([this]()
    {
         copy_color_map();
         copy_proximity_map();
         write_placement_maps();
    });

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

void App::copy_color_map()
{
    m_color_map_cuda_mapping->copy_from(m_arpenteur->m_color_map);
}

// TODO put in DeviceImage or utility file
template<
    uint32_t SRC_IMAGE_FORMAT, typename SRC_IMAGE_TYPE,
    uint32_t DST_IMAGE_FORMAT, typename DST_IMAGE_TYPE
    >
__global__
void transform_image_kernel(
    const DeviceImage<SRC_IMAGE_FORMAT, SRC_IMAGE_TYPE>* src_image,
    DeviceImage<DST_IMAGE_FORMAT, DST_IMAGE_TYPE>* dst_image
    )
{
    size_t x = blockIdx.x * blockDim.x + threadIdx.x;
    size_t y = blockIdx.y * blockDim.y + threadIdx.y;

    //printf("x: %d, y: %d, width: %d, height: %d\n", x, y, src_image->m_width, src_image->m_height);

    if (x < src_image->m_width && y < src_image->m_height)
    {
        auto v = src_image->read_pixel(x, y);
        //auto new_val = transform_func(v);
        dst_image->write_pixel(x, y, glm::vec<4, uint8_t>{(float(v.x & 0x7F) / float(PROXIMITY_MAP_HIGH_VALUE)) * 255.0f, 0, 0, 255});
    }
}

/// Transform the input image into the output image invoking a transform function on each source pixel.
template<
    uint32_t SRC_IMAGE_FORMAT, typename SRC_IMAGE_TYPE,
    uint32_t DST_IMAGE_FORMAT, typename DST_IMAGE_TYPE,
    typename TRANSFORM_FUNC
    >
void transform_image(
    const DeviceImage<SRC_IMAGE_FORMAT, SRC_IMAGE_TYPE>& src_image,
    DeviceImage<DST_IMAGE_FORMAT, DST_IMAGE_TYPE>& dst_image,
    TRANSFORM_FUNC transform_func
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

__device__
glm::vec<4, uint8_t> transform_proximity_map(const glm::vec<1, uint8_t>& v)
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
    DeviceImage<4, uint8_t> tmp_image = DeviceImage<4, uint8_t>::create(m_slice_side, m_slice_side, nullptr);

    tmp_image.fill(255);
    transform_image(m_arpenteur->m_prev_proximity_map, tmp_image, transform_proximity_map);  // Fake CLion error :')

    m_proximity_map_cuda_mapping->copy_from(tmp_image);
}

void App::write_placement_maps()
{
    StopWatch stop_watch{};

    printf("[App] Writing placements to textures for visualization...\n");

    DeviceImage<4, uint8_t> tmp_subslice0_image = DeviceImage<4, uint8_t>::create(m_slice_side, m_slice_side, nullptr);
    DeviceImage<4, uint8_t> tmp_subslice1_image = DeviceImage<4, uint8_t>::create(m_slice_side, m_slice_side, nullptr);
    DeviceImage<4, uint8_t> tmp_subslice2_image = DeviceImage<4, uint8_t>::create(m_slice_side, m_slice_side, nullptr);

    tmp_subslice0_image.fill(0);
    tmp_subslice1_image.fill(0);
    tmp_subslice2_image.fill(0);

    PlacementHash hash_func{};
    for (std::pair<Placement, uint8_t> entry : m_arpenteur->m_stacked_placements)
    {
        Placement& placement = entry.first;
        uint8_t subslice_mask = entry.second;
        assert(subslice_mask);  // Shouldn't be zero

        uint64_t hash = hash_func(placement);

        glm::vec<4, uint8_t> v{};
        v.x = glm::abs(glm::sin(hash * 0.147f)) * 255.0f;
        v.y = glm::abs(glm::cos(hash * 0.843f)) * 255.0f;
        v.z = glm::abs(glm::sin(hash * 0.239f)) * 255.0f;
        v.w = 255;

        auto& brick = k_bricks[placement.m_bid];
        for (int by = 0; by < BRICK_MAX_HEIGHT; by++)
        {
            for (int bx = 0; bx < BRICK_MAX_WIDTH; bx++)
            {
                if (brick[by][bx])
                {
                    if (subslice_mask & 0x1) tmp_subslice0_image.write_pixel(placement.m_x + bx, placement.m_y + by, v);
                    if (subslice_mask & 0x2) tmp_subslice1_image.write_pixel(placement.m_x + bx, placement.m_y + by, v);
                    if (subslice_mask & 0x4) tmp_subslice2_image.write_pixel(placement.m_x + bx, placement.m_y + by, v);
                }
            }
        }
    }

    m_subslice0_cuda_mapping->copy_from(tmp_subslice0_image);
    m_subslice1_cuda_mapping->copy_from(tmp_subslice1_image);
    m_subslice2_cuda_mapping->copy_from(tmp_subslice2_image);

    std::string duration_str = stop_watch.elapsed_time_str();
    printf("[App] Placements written in %s\n", duration_str.c_str());
}

void App::show_model_window()
{
    if (ImGui::Begin("Model"))
    {
        ImGui::Text("Model path: %s", m_arpenteur->m_model_path.c_str());

        if (m_baked_model)
        {
            m_model_view_framebuffer.render([&]()
            {
                glClearColor(0.6f, 0.6f, 0.6f, 1.0f);
                glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

                m_model_renderer.render(*m_baked_model, m_camera, glm::identity<glm::mat4>());
            });

            ImVec2 image_size{256, 256};
            ImGui::Image(reinterpret_cast<void*>(m_model_view_framebuffer.m_texture), image_size, ImVec2(0, 1), ImVec2(1, 0));

            // Update the camera to orbit around the model
            m_camera.m_position += m_camera.right() * m_dt * m_camera_speed;
            m_camera.look_at(m_look_at_position);
        }
    }
    ImGui::End();
}

void App::show_placement_map_window()
{
    if (ImGui::Begin("Placement maps"))
    {
        ImVec2 window_size = ImGui::GetWindowSize();
        ImVec2 image_size(window_size.y, window_size.y);

        ImGui::RadioButton("Color map", (int*) &m_visualized_map, VisualizeMapType_ColorMap);
        ImGui::SameLine();
        ImGui::RadioButton("Placement map", (int*) &m_visualized_map, VisualizeMapType_PlacementMap);
        ImGui::SameLine();
        ImGui::RadioButton("Proximity map (previous slice)", (int*) &m_visualized_map, VisualizeMapType_ProximityMap);

        // Color map
        if (m_visualized_map == VisualizeMapType_ColorMap)
        {
            ImGui::NewLine();
            ImGui::Image(reinterpret_cast<void*>(m_color_map_cuda_mapping->texture()), image_size, ImVec2(0, 1), ImVec2(1, 0));
        }
        // Proximity map
        else if (m_visualized_map == VisualizeMapType_ProximityMap)
        {
            ImGui::NewLine();
            ImGui::Image(reinterpret_cast<void*>(m_proximity_map_cuda_mapping->texture()), image_size, ImVec2(0, 1), ImVec2(1, 0));
        }
        // Placement map
        else if (m_visualized_map == VisualizeMapType_PlacementMap)
        {
            if (ImGui::ArrowButton("subslice_left", ImGuiDir_Left) && m_visualized_subslice_idx > 0)
            {
                if (m_visualized_subslice_idx > 0) --m_visualized_subslice_idx;
            }
            ImGui::SameLine();
            if (ImGui::ArrowButton("subslice_right", ImGuiDir_Right) && m_visualized_subslice_idx < 2)
            {
                if (m_visualized_subslice_idx < 2) ++m_visualized_subslice_idx;
            }
            ImGui::SameLine();
            ImGui::Text("Slice %d/2", m_visualized_subslice_idx);

            if (m_visualized_subslice_idx == 0)
            {
                ImGui::Image(reinterpret_cast<void*>(m_subslice0_cuda_mapping->texture()), image_size, ImVec2(0, 1), ImVec2(1, 0));
            }
            else if (m_visualized_subslice_idx == 1)
            {
                ImGui::Image(reinterpret_cast<void*>(m_subslice1_cuda_mapping->texture()), image_size, ImVec2(0, 1), ImVec2(1, 0));
            }
            else
            {
                ImGui::Image(reinterpret_cast<void*>(m_subslice2_cuda_mapping->texture()), image_size, ImVec2(0, 1), ImVec2(1, 0));
            }
        }
    }
    ImGui::End();
}

void App::render()
{
    ImGui::ShowDemoWindow();

    show_model_window();
    show_placement_map_window();
}

void App::run()
{
    // Start l'Arpenteur on a separate thread
    std::thread arpenteur_thread([this]() { m_arpenteur->run(); });

    m_window.set_key_callback([&](int key, int scancode, int action, int mods)
    {
        bool is_space = key == GLFW_KEY_SPACE && action == GLFW_PRESS;

        if ((key == GLFW_KEY_ENTER && action == GLFW_PRESS) || is_space)
        {
            // Resume the Arpenteur thread (by default it stops after a slice is completed)
            m_arpenteur_should_run = true;
            m_arpenteur_should_run.notify_all();
        }

        if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS) m_window.set_should_close(true);  // Bye bye! :)

        if (is_space) m_autorun = !m_autorun;
    });

    // Loop
    while (!m_window.should_close())
    {
        glBindFramebuffer(GL_FRAMEBUFFER, 0);

        glm::ivec2 framebuffer_size = m_window.get_framebuffer_size();
        glViewport(0, 0, framebuffer_size.x, framebuffer_size.y);

        double now = glfwGetTime();
        if (m_last_frame_t > 0.0f) m_dt = now - m_last_frame_t;
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

        m_job_queue_cond_var.notify_all();  // Notify arpenteur thread that the job queue is now empty
    }

    // TODO STOP THE ARPENTEUR!
    arpenteur_thread.join();
}
