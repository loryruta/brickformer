#include <filesystem>
#include <thread>

#include "Slicer.cuh"
#include "StopWatch.hpp"
#include "model/GltfLoader.hpp"
#include "model/Model.hpp"
#include "video/TextureRenderer.hpp"
#include "video/ViewModelApp.hpp"
#include "video/cuda_interop_helpers.cuh"
#include "video/gl_helpers.hpp"

using namespace lego_builder;
using namespace std::chrono_literals;

/// Transforms the model vertices such that the maximum of XZ axes, fits the given side.
/// Use case: used before performing slicing to fit the Model within the Slicer space.
void fit_xz_plane(Model& model, float new_xz_side)
{
    glm::vec3 model_size = model.size();
    float max_xz_side = glm::max(model_size.x, model_size.z);

    glm::mat4 transform = glm::identity<glm::mat4>();
    transform = glm::scale(transform, glm::vec3(new_xz_side / max_xz_side));
    transform = glm::translate(transform, -model.m_min);

    model.apply_transform(transform);
    model.update_min_max(true /* update_mesh_min_max */);
}

int main(int argc, char* argv[])
{
    constexpr uint32_t k_slice_side = 256; // TODO put in a global config.hpp

    Window window(500, 500, "lego_builder");

    int version = gladLoadGL(glfwGetProcAddress);
    assert(version > 0);  // TODO no assert

    printf("OpenGL %d.%d loaded\n", GLAD_VERSION_MAJOR(version), GLAD_VERSION_MINOR(version));

    enable_gl_debug_output();

    std::filesystem::path model_path =
            "/home/loryruta/CLionProjects/lego-builder/resources/models/shinto_shrine.glb";

    GltfLoader gltf_loader;

    Model model = gltf_loader.load_file(model_path);

    fit_xz_plane(model, k_slice_side);

    glm::vec3 model_size = model.size();

    printf("Transformed model in slice-space; Min: (%.3f, %.3f, %.3f), Max: (%.3f, %.3f, %.3f); Size: (%.3f, %.3f, %.3f)\n",
           model.m_min.x, model.m_min.y, model.m_min.z,
           model.m_max.x, model.m_max.y, model.m_max.z,
           model_size.x, model_size.y, model_size.z
           );

    // Visualize that the model is correctly transformed into the Slicer space
    glm::vec3 model_hsize = model_size / 2.0f;

    glm::vec3 orbit_center = model.m_min + model_hsize;

    float cam_rad = glm::sqrt(model_hsize.x * model_hsize.x + model_hsize.z * model_hsize.z);
    cam_rad *= 1.3f;
    glm::vec3 cam_position = orbit_center + glm::vec3(cam_rad, model_hsize.y / 2.0f, cam_rad);

    ViewModelApp view_model_app(window, model, orbit_center, cam_position, 100.0f);
    if (view_model_app.run()) exit(0);

    //const DeviceModel* d_model = upload_model(model);

    Slicer slicer(model, k_slice_side);

    SliceT slice = SliceT::create(k_slice_side, k_slice_side);

    TextureRenderer texture_renderer;

    // Create a GL texture mapped to a CUDA resource. It's used to visually display the result of the slicing
    CudaMappedGlTexture frame_texture = CudaMappedGlTexture::create(k_slice_side, k_slice_side);

    uint32_t num_slices = glm::ceil(model_size.y);

    for (uint32_t slice_y = 0; slice_y < num_slices; slice_y++)
    {
        printf("Slice %d/%d...\n", slice_y + 1, num_slices);

        StopWatch stop_watch;

        slicer.slice(slice_y, slice);

        std::string slice_dt_str = stop_watch.elapsed_time_str();
        printf("Slice %d/%d generated in %s\n", slice_y + 1, num_slices, slice_dt_str.c_str());

        // Render
        window.begin_frame();

        glDisable(GL_DEPTH_TEST);

        glClearColor(0, 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT);

        frame_texture.copy_from(slice);
        texture_renderer.render(frame_texture.gl_texture());

        window.end_frame();
    }

    return 0;
}


