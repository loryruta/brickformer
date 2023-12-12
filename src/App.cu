#include "App.cuh"

#include <external/glad.h> // From raylib.h
#include <texture_types.h>
#include <cuda_gl_interop.h>
#include <curand.h>

#define MAP_WIDTH  256
#define MAP_HEIGHT 256

using namespace lego_builder;

namespace
{
    /// Creates a raylib texture without requiring initialization data.
    Texture create_texture(int width, int height)
    {
        Texture texture;
        glGenTextures(1, &texture.id);
        texture.width = width;
        texture.height = height;
        texture.format = PixelFormat::PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;
        texture.mipmaps = 1;

        glBindTexture(GL_TEXTURE_2D, texture.id);

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, MAP_WIDTH, MAP_HEIGHT, GL_NONE, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);

        glBindTexture(GL_TEXTURE_2D, 0);

        return texture;
    }

    template<typename CALLBACK>
    void map_gl_texture(const Texture& texture, CALLBACK callback)
    {
        cudaGraphicsResource* resource;
        CHECK_CU(cudaGraphicsGLRegisterImage(&resource, texture.id, GL_TEXTURE_2D, cudaGraphicsRegisterFlagsWriteDiscard));

        cudaArray* texture_ptr;
        CHECK_CU(cudaGraphicsMapResources(1, &resource));
        CHECK_CU(cudaGraphicsSubResourceGetMappedArray(&texture_ptr, resource, 0, 0));

        callback(texture_ptr);

        CHECK_CU(cudaGraphicsUnmapResources(1, &resource));
        CHECK_CU(cudaGraphicsUnregisterResource(resource));
    }

    void copy_to_gl_texture(const DeviceImage<4, uint8_t>& image, Texture& texture)
    {
        map_gl_texture(texture, [&](cudaArray* texture_ptr)
        {
            CHECK_CU(cudaMemcpy2DToArray(
                    texture_ptr, 0, 0,
                    image.m_data,
                    image.m_width * image.pixel_size(),  // spitch
                    image.m_width * image.pixel_size(),  // width
                    image.m_height,
                    cudaMemcpyDeviceToDevice));
        });
    }

} // namespace


App::App()
{
    InitWindow(500, 500, "lego_builder   ¯\\_(ツ)_/¯");

    m_color_map_texture = create_texture(MAP_WIDTH, MAP_HEIGHT);

    m_tmp_image = DeviceImage<4, uint8_t>::create_device_ptr(MAP_WIDTH, MAP_HEIGHT, nullptr);

    m_cur_placement_map_texture = create_texture(MAP_WIDTH, MAP_HEIGHT);
    m_prv_placement_map_texture = create_texture(MAP_WIDTH, MAP_HEIGHT);
}

App::~App()
{
    UnloadTexture(m_color_map_texture);

    CloseWindow();
}

bool App::should_close() const
{
    return WindowShouldClose();
}

void App::set_color_map(const ColorMapT* d_color_map)
{
    copy_to_gl_texture(to_host(d_color_map), m_color_map_texture);
}

__global__ void convert_placement_map(const PlacementMapT* d_placement_map, DeviceImage<4, uint8_t>* d_out)
{
    size_t i = blockIdx.x * blockDim.x + threadIdx.x;

    uint32_t x = i % MAP_WIDTH;
    uint32_t y = i / MAP_WIDTH;

    if (y < d_placement_map->m_height)
    {
        uint16_t pid = d_placement_map->read_pixel(x, y).x;

        // Map the placement ID to a "random" "unique" color

        glm::vec<4, uint8_t> val{};
        if (pid != 0)
        {
            // Inspiration:
            // https://gist.github.com/patriciogonzalezvivo/670c22f3966e662d2f83

            float v = sin(float(pid)) * 1e4f;
            v = v - floorf(v);  // Restrict to [0, 1]

            val.r = (uint8_t) (abs(sin(v * 1408.0f)) * 255.0f);
            val.g = (uint8_t) (abs(cos(v * 8578.0f)) * 255.0f);
            val.b = (uint8_t) (abs(sin(v * 9674.0f)) * 255.0f);
            val.a = 255;
        }

        d_out->write_pixel(x, y, val);
    }
}

void App::set_placement_map(const PlacementMapT* d_placement_map)
{
    auto image_info = to_host(d_placement_map);
    size_t num_blocks = (image_info.m_width * image_info.m_height) << 10;

    convert_placement_map<<<num_blocks, 1024>>>(d_placement_map, m_tmp_image);
    CHECK_CU(cudaDeviceSynchronize());

    copy_to_gl_texture(to_host(m_tmp_image), m_cur_placement_map_texture);
}

void App::draw()
{
    int screen_w = GetScreenWidth();
    int screen_h = GetScreenHeight();

    BeginDrawing();
    {
        ClearBackground(BLACK);

        DrawTexturePro(m_cur_placement_map_texture,
                       {0, 0, (float) m_cur_placement_map_texture.width, (float) m_cur_placement_map_texture.height},
                       {0, 0, (float) screen_w, (float) screen_h},
                       {0, 0},
                       0.0f, WHITE);
    }
    EndDrawing();
}



