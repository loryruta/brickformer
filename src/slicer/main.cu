#include <filesystem>

#include "Model.hpp"
#include "GltfLoader.hpp"
#include "video/ViewModelApp.hpp"
#include "video/gl_helpers.hpp"
#include "BuildBvh.cuh"
#include "DeviceModel.cuh"
#include "Slicer.cuh"
#include "../StopWatch.hpp"
#include "video/TextureRenderer.hpp"

using namespace lego_builder;

int main(int argc, char* argv[])
{
    Window window(500, 500, "lego_builder");

    int version = gladLoadGL(glfwGetProcAddress);
    assert(version > 0);  // TODO no assert

    printf("OpenGL %d.%d loaded\n", GLAD_VERSION_MAJOR(version), GLAD_VERSION_MINOR(version));

    enable_gl_debug_output();

    std::filesystem::path model_path =
            "/home/loryruta/CLionProjects/lego-builder/resources/models/prehistoric_planet_tyrannosaurus_rex_model.glb";

    GltfLoader gltf_loader;
    Model model = gltf_loader.load_file(model_path);

    //ViewModelApp view_model_app(window, model);
    //if (view_model_app.run()) exit(0);

    BuildBvh build_bvh;
    const Bvh* d_bvh = build_bvh.build(model);

    const DeviceModel* d_model = upload_model(model);

    constexpr uint32_t k_slice_side = 256; // TODO put in a global config.hpp

    Slicer slicer(d_bvh, d_model, model.m_transformed_min, model.m_transformed_max, k_slice_side);

    using SliceImageT = DeviceImage<4, uint8_t>;

    SliceImageT slice_img = SliceImageT::create(k_slice_side, k_slice_side, nullptr);
    slice_img.fill(0);
    SliceImageT* d_slice_img = to_device(slice_img);

    TextureRenderer tex_renderer;
    GLuint frame_tex = create_gl_texture_from_cuda_image(slice_img, false /* copy_content */);

    for (uint32_t slice_y = 0; slice_y < slicer.num_slices(); slice_y++)
    {
        printf("Slice %d/%d...\n", slice_y + 1, slicer.num_slices());

        StopWatch stop_watch;

        slicer.slice(slice_y, d_slice_img);

        std::string slice_dt_str = stop_watch.elapsed_time_str();
        printf("Slice %d/%d generated in %s\n", slice_y + 1, slicer.num_slices(), slice_dt_str.c_str());

        // Render
        window.begin_frame();

        glDisable(GL_DEPTH_TEST);

        glClearColor(0, 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT);

        copy_cuda_image_to_gl_texture(slice_img, frame_tex);
        tex_renderer.render(frame_tex);

        window.end_frame();
    }

    return 0;
}


