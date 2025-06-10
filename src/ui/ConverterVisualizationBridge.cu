#include "ConverterVisualizationBridge.h"

#include "App.h"
#include "brick_colors.hpp"
#include "bricks.hpp"
#include "log.hpp"
#include "util/StopWatch.hpp"

#define ARP_LOG_CONTEXT "ConverterVisualizationBridge"

using namespace lego_builder;

namespace
{
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
} // namespace

ConverterVisualizationBridge::ConverterVisualizationBridge(Converter& converter) : m_converter(converter)
{
    int resolution = m_converter.m_params.resolution;

    m_color_map_texture = std::make_unique<CUDAMappedGLTexture>(create_gl_texture(resolution, resolution));

    m_placement_map_hashed_color_textures.emplace_back(create_gl_texture(resolution, resolution)); // Subslice 0
    m_placement_map_hashed_color_textures.emplace_back(create_gl_texture(resolution, resolution)); // Subslice 1
    m_placement_map_hashed_color_textures.emplace_back(create_gl_texture(resolution, resolution)); // Subslice 2

    m_placement_map_color_textures.emplace_back(create_gl_texture(resolution, resolution)); // Subslice 0
    m_placement_map_color_textures.emplace_back(create_gl_texture(resolution, resolution)); // Subslice 1
    m_placement_map_color_textures.emplace_back(create_gl_texture(resolution, resolution)); // Subslice 2

    m_proximity_map_texture = std::make_unique<CUDAMappedGLTexture>(create_gl_texture(resolution, resolution));

    m_brick_model_builder = std::make_unique<BrickModelBuilder>();
    m_voxel_model_builder = std::make_unique<VoxelModelBuilder>();

    m_converter.add_listener(this);
}

void ConverterVisualizationBridge::copy_color_map(cudaStream_t stream)
{
    m_color_map_texture->copy_from(m_converter.m_color_map, g_stream);
}

void ConverterVisualizationBridge::copy_placement_maps(cudaStream_t stream)
{
    StopWatch stopwatch{};

    printf("[App] Writing placements to textures for visualization...\n");

    int resolution = m_converter.m_params.resolution;

    std::vector<DeviceImage<4, uint8_t>> hashed_color_images;
    std::vector<DeviceImage<4, uint8_t>> color_images;
    for (int i = 0; i < 3; ++i) {
        hashed_color_images.emplace_back(DeviceImage<4, uint8_t>::create(resolution, resolution, nullptr, g_stream));
        color_images.emplace_back(DeviceImage<4, uint8_t>::create(resolution, resolution, nullptr, g_stream));
    }

    for (int i = 0; i < 3; ++i) {
        hashed_color_images.at(i).fill(0, g_stream);
        color_images.at(i).fill(0, g_stream);
    }

    for (const Placement& placement : m_converter.m_linear_stacked_placements) {
        uint8_t subslice_mask = placement.subslice_mask;
        assert(subslice_mask); // Shouldn't be zero

        glm::vec<4, uint8_t> hashed_color = eval_placement_hashed_color(placement);
        glm::vec<4, uint8_t> color = k_brick_colors[placement.cid].color_u8();
        auto& brick = k_bricks[placement.bid];
        for (int bz = 0; bz < BRICK_MAX_EXTENT_Z; bz++) {
            for (int bx = 0; bx < BRICK_MAX_EXTENT_X; bx++) {
                if (brick[bz][bx]) {
                    int px = placement.x + bx;
                    int pz = placement.z + bz;
                    if (subslice_mask & 0x1) {
                        hashed_color_images.at(0).write_pixel(px, pz, hashed_color, g_stream);
                        color_images.at(0).write_pixel(px, pz, color, g_stream);
                    }
                    if (subslice_mask & 0x2) {
                        hashed_color_images.at(1).write_pixel(px, pz, hashed_color, g_stream);
                        color_images.at(1).write_pixel(px, pz, color, g_stream);
                    }
                    if (subslice_mask & 0x4) {
                        hashed_color_images.at(2).write_pixel(px, pz, hashed_color, g_stream);
                        color_images.at(2).write_pixel(px, pz, color, g_stream);
                    }
                }
            }
        }
    }

    for (int i = 0; i < 3; ++i) {
        m_placement_map_hashed_color_textures.at(i).copy_from(hashed_color_images.at(i), g_stream);
        m_placement_map_color_textures.at(i).copy_from(color_images.at(i), g_stream);
    }

    std::string duration_str = stopwatch.elapsed_time_str();
    ARP_INFO("Placement maps filled in %s", duration_str.c_str());
}

void ConverterVisualizationBridge::copy_proximity_map(cudaStream_t stream)
{
    int resolution = m_converter.m_params.resolution;

    // Allocate a temporary image that hosts the conversion of the proximity map to RGBA (remember: proximity map is
    // a grayscale image). This is necessary as I've not found a way to directly write to a cudaArray (i.e. CUDA mapped
    // texture)
    DeviceImage<4, uint8_t> tmp_image = DeviceImage<4, uint8_t>::create(resolution, resolution, nullptr, g_stream);

    int proximity_max_val = m_converter.m_proximity_max_value;

    auto transform_proximity_val =
        [proximity_max_val] __device__(const glm::vec<1, uint8_t>& val) -> glm::vec<4, uint8_t> {
        uint8_t new_val = (uint8_t) float(val.x) / float(proximity_max_val) * 255.0f;
        return glm::vec<4, uint8_t>{new_val, 0, 0, 255};
    };

    tmp_image.fill(0, g_stream);
    m_converter.m_prev_proximity_map.transform_to(tmp_image, transform_proximity_val, g_stream);

    m_proximity_map_texture->copy_from(tmp_image, g_stream);
}

void ConverterVisualizationBridge::add_placements_to_construction_model(cudaStream_t)
{
    /* Add geometry */
    StopWatch stopwatch{};
    ARP_DEBUG("Update Brick Model; Adding vertices...");

    uint32_t pid = 0; // TODO make global for any slice
    for (const Placement& placement : m_converter.m_linear_stacked_placements) {
        const BrickColor& brick_color = k_brick_colors[placement.cid];
        ARP_DEBUG("  %03d Slice: %d, BID: %2d, X: %3d, Z: %3d, Subslice mask: %d, Color: %s",
                  pid,
                  m_converter.m_slice_y,
                  placement.bid,
                  placement.x,
                  placement.z,
                  placement.subslice_mask,
                  brick_color.name);
        ++pid;
        m_brick_model_builder->add_placement(m_converter.m_slice_y, pid, placement);
    }

    std::string dt_str;
    dt_str = stopwatch.elapsed_time_str();
    ARP_DEBUG("Update Brick Model; Vertices added in %s", dt_str);

    /* Baking */
    stopwatch.reset();
    ARP_DEBUG("Update Brick Model; Baking...");

    const Model& brick_model = m_brick_model_builder->model();
    m_baked_brick_model = std::make_unique<BrickRenderer_BakedModel>(BrickRenderer::bake_model(brick_model));

    dt_str = stopwatch.elapsed_time_str();
    ARP_DEBUG("Update Brick Model; Model baked in %s", dt_str);
}

void ConverterVisualizationBridge::add_color_map_voxels(cudaStream_t)
{
    const ColorMapT& color_map = m_converter.m_color_map;
    int slice_y = m_converter.m_slice_y;
    std::vector<ColorMapT::PixelT> data(color_map.m_width * color_map.m_height);
    CHECK_CU(
        cudaMemcpy(data.data(), color_map.m_data, data.size() * sizeof(ColorMapT::PixelT), cudaMemcpyDeviceToHost));
    for (size_t i = 0; i < data.size(); i++) {
        if (data[i].a > 0) {
            int x = i % color_map.m_width;
            int z = i / color_map.m_width;
            glm::vec4 color = glm::vec4{data[i]} / 255.0f;
            m_voxel_model_builder->set_voxel(x, slice_y, z, color);
        }
    }
    m_baked_voxel_model = std::make_unique<BakedModel>(ModelRenderer::bake_model(m_voxel_model_builder->model()));
}

void ConverterVisualizationBridge::on_placement_end(uint32_t slice_y, const std::vector<Placement>& placements)
{
    // Reminder: this function is called asynchronously
    g_app->enqueue_job([this]() {
        cudaStream_t stream = g_stream;

        copy_color_map(stream);
        copy_proximity_map(stream);
        copy_placement_maps(stream);
        add_placements_to_construction_model(stream);
        // add_color_map_voxels(stream);

        CHECK_CU(cudaStreamSynchronize(stream));
    });
    // Make the Converter wait for the completion of the jobs above
    g_app->wait_job_completion();
}
