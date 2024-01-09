#include "App.cuh"

#include <GLFW/glfw3.h>
#include <glad/gl.h>
#include <imgui.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>

#include "bricks.hpp"
#include "util/StopWatch.hpp"
#include "video/gl_helpers.hpp"

using namespace lego_builder;


App::App(Window& window) :
    m_window(window)
{
    m_model_path = "/home/loryruta/CLionProjects/lego-builder/resources/models/polka-dot_man.glb";
    m_slice_side = 60;

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

    m_hashed_placement_map_cuda_mappings.emplace_back(create_gl_texture(m_slice_side, m_slice_side));
    m_hashed_placement_map_cuda_mappings.emplace_back(create_gl_texture(m_slice_side, m_slice_side));
    m_hashed_placement_map_cuda_mappings.emplace_back(create_gl_texture(m_slice_side, m_slice_side));

    m_colored_placement_map_cuda_mappings.emplace_back(create_gl_texture(m_slice_side, m_slice_side));
    m_colored_placement_map_cuda_mappings.emplace_back(create_gl_texture(m_slice_side, m_slice_side));
    m_colored_placement_map_cuda_mappings.emplace_back(create_gl_texture(m_slice_side, m_slice_side));

    m_model_renderer = std::make_unique<ModelRenderer>();
    m_model_renderer->add_directional_light({.m_direction = glm::normalize(glm::vec3{-1.0f, -1.0f, 0.0f}), .m_color = glm::vec3{1.0f}});
    m_model_renderer->add_directional_light({.m_direction = glm::normalize(glm::vec3{0.0f, -1.0f, -1.0f}), .m_color = glm::vec3{1.0f}});
    m_model_renderer->add_directional_light({.m_direction = glm::normalize(glm::vec3{-1.0f, 0.0f, -1.0f}), .m_color = glm::vec3{1.0f}});
    m_model_renderer->add_directional_light({.m_direction = glm::normalize(glm::vec3{0.0f, -1.0f, -1.0f}), .m_color = glm::vec3{1.0f}});
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
        m_baked_model = std::make_unique<BakedModel>(m_model_renderer->bake_model(model));

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
         write_placement_maps(m_hashed_placement_map_cuda_mappings, true);
         write_placement_maps(m_colored_placement_map_cuda_mappings, false);
         add_placements_to_construction_model();
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

void App::write_placement_maps(std::vector<CudaMappedGlTexture>& out_images, bool use_hashed_color)
{
    StopWatch stop_watch{};

    printf("[App] Writing placements to textures for visualization...\n");

    DeviceImage<4, uint8_t> tmp_images[3]{
        DeviceImage<4, uint8_t>::create(m_slice_side, m_slice_side, nullptr),
        DeviceImage<4, uint8_t>::create(m_slice_side, m_slice_side, nullptr),
        DeviceImage<4, uint8_t>::create(m_slice_side, m_slice_side, nullptr)
    };

    tmp_images[0].fill(0);
    tmp_images[1].fill(0);
    tmp_images[2].fill(0);

    for (ColoredPlacement& entry : m_arpenteur->m_colored_placements)
    {
        Placement& placement = entry.m_placement;
        uint8_t subslice_mask = entry.m_subslice_mask;
        assert(subslice_mask);  // Shouldn't be zero

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
                    if (subslice_mask & 0x1) tmp_images[0].write_pixel(placement.m_x + bx, placement.m_y + bz, color);
                    if (subslice_mask & 0x2) tmp_images[1].write_pixel(placement.m_x + bx, placement.m_y + bz, color);
                    if (subslice_mask & 0x4) tmp_images[2].write_pixel(placement.m_x + bx, placement.m_y + bz, color);
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
//        uint64_t hash = hash_func(colored_placement);

//        glm::vec<4, float> color{};
//        color.x = glm::abs(glm::sin(hash * 0.147f));
//        color.y = glm::abs(glm::cos(hash * 0.843f));
//        color.z = glm::abs(glm::sin(hash * 0.239f));
//        color.w = 1.0f;

        m_brick_model_builder.place(
            m_arpenteur->m_slice_y,
            colored_placement.m_placement.m_x, colored_placement.m_placement.m_y,
            colored_placement.m_placement.m_bid,
            colored_placement.m_subslice_mask,
            glm::vec4{colored_placement.m_color} / 255.0f
            );
    }

    printf("[App] UPDATE CONSTRUCTION MODEL; Baking...\n");

    m_baked_construction_model = std::make_unique<BakedModel>(m_model_renderer->bake_model(m_brick_model_builder.model()));

    printf("[App] UPDATE CONSTRUCTION MODEL; Done\n");
}

void App::render_3d_scene()
{
    glClearColor(0.6f, 0.6f, 0.6f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    if (m_visualize_model)
    {
        if (m_baked_model) m_model_renderer->render(*m_baked_model, m_camera, glm::mat4{1.0f});
    }

    if (m_visualize_construction)
    {
        if (m_baked_construction_model) m_model_renderer->render(*m_baked_construction_model, m_camera, glm::mat4{1.0f});
    }

    // Update the camera to orbit around the model
    m_camera.m_position += m_camera.right() * m_dt * m_camera_speed;
    m_camera.look_at(m_look_at_position);
}

void App::show_model_window()
{
    if (ImGui::Begin("Model"))
    {
        ImGui::Text("Model path: %s", m_arpenteur->m_model_path.c_str());

        ImGui::Checkbox("Model", &m_visualize_model);
        ImGui::SameLine();
        ImGui::Checkbox("Construction", &m_visualize_construction);
        ImGui::SameLine();
        ImGui::Checkbox("Shading", &m_model_renderer->m_shading);

        ImGui::NewLine();

        ImVec2 image_size;
        image_size.y = ImGui::GetContentRegionAvail().y;
        image_size.x = image_size.y;
        ImGui::Image(reinterpret_cast<void*>(m_model_view_framebuffer.m_texture), image_size, ImVec2(0, 1), ImVec2(1, 0));
    }
    ImGui::End();
}

void App::show_placement_map_window()
{
    if (ImGui::Begin("Placement maps"))
    {
        ImGui::RadioButton("Color map", (int*) &m_visualized_map, VisualizeMapType_ColorMap);
        ImGui::SameLine();
        ImGui::RadioButton("Placement map", (int*) &m_visualized_map, VisualizeMapType_PlacementMap);
        ImGui::SameLine();
        ImGui::RadioButton("Proximity map (previous slice)", (int*) &m_visualized_map, VisualizeMapType_ProximityMap);

        GLuint placement_map_texture;

        // Color map
        if (m_visualized_map == VisualizeMapType_ColorMap)
        {
            ImGui::NewLine();
            placement_map_texture = m_color_map_cuda_mapping->texture();
        }
        // Proximity map
        else if (m_visualized_map == VisualizeMapType_ProximityMap)
        {
            ImGui::NewLine();
            placement_map_texture = m_proximity_map_cuda_mapping->texture();
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
            ImGui::SameLine();
            ImGui::Checkbox("Color", &m_visualize_colored_placement_map);

            std::vector<CudaMappedGlTexture>& placement_maps = m_visualize_colored_placement_map ? m_colored_placement_map_cuda_mappings : m_hashed_placement_map_cuda_mappings;
            placement_map_texture = placement_maps.at(m_visualized_subslice_idx).texture();
        }

        ImVec2 image_size;
        image_size.y = ImGui::GetContentRegionAvail().y;
        image_size.x = image_size.y;

        ImGui::Image(reinterpret_cast<void*>(placement_map_texture), image_size, ImVec2(0, 1), ImVec2(1, 0));
    }
    ImGui::End();
}

void App::render()
{
    m_model_view_framebuffer.render([&]() { render_3d_scene(); });

    //ImGui::ShowDemoWindow();
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
