#include "Converter.h"

#include <cuda_profiler_api.h>
#include <tinyformat.h>

#include "AssignPlacementColor.h"
#include "BrickColors.h"
#include "bricks.h"
#include "log.h"
#include "model/GltfLoader.h"
#include "types.h"
#include "util/StopWatch.h"

#define ARP_LOG_CONTEXT "Converter"

using namespace bf;

namespace
{
__global__ void
init_proximity_map_from_color_map_kernel(const ColorMapT* color_map, uint8_t init_val, ProximityMapT* out_proximity_map)
{
    assert(color_map->m_width == out_proximity_map->m_width && color_map->m_height == out_proximity_map->m_height);

    uint32_t px = blockIdx.x * blockDim.x + threadIdx.x;
    uint32_t py = blockIdx.y * blockDim.y + threadIdx.y;

    if (px < color_map->m_width && py < color_map->m_height) {
        bool is_colored = color_map->read_pixel(px, py).a > 0;
        if (is_colored) out_proximity_map->write_pixel(px, py, glm::vec<1, uint8_t>{init_val});
    }
}
} // namespace

Converter::Converter(const ConverterParams& params) : m_params(params)
{
    int resolution = params.resolution;
    tfm::printf("[INFO ] [Converter] Resolution: %d\n", resolution);

    if (m_proximity_threshold == UINT8_MAX) {
        m_proximity_threshold = calc_proximity_threshold(resolution);
        tfm::printf("[INFO ] [Converter] Proximity threshold (derived): %d\n", m_proximity_threshold);
    } else {
        m_proximity_threshold = params.proximity_threshold;
        tfm::printf("[INFO ] [Converter] Proximity threshold: %d\n", m_proximity_threshold);
    }

    if (params.proximity_max_value == UINT8_MAX) {
        m_proximity_max_value = calc_proximity_max_value(resolution);
        tfm::printf("[INFO ] [Converter] Proximity max value (derived): %d\n", m_proximity_max_value);
    } else {
        m_proximity_max_value = params.proximity_max_value;
        tfm::printf("[INFO ] [Converter] Proximity max value: %d\n", m_proximity_max_value);
    }

    m_num_placements = resolution * resolution * k_num_bricks;
    // init_placements();

    // Create a dedicate CUDA stream on which execute all operations
    CHECK_CU(cudaStreamCreate(&m_stream));

    CHECK_CU(cudaMallocAsync(&m_valid_placements_d, m_num_placements * sizeof(bool), m_stream));
    CHECK_CU(cudaStreamSynchronize(m_stream));

    m_color_map = ColorMapT::create(resolution, resolution, nullptr, m_stream);
    m_color_map_d = to_device(m_color_map, m_stream);

    m_prev_proximity_map = ProximityMapT::create(resolution, resolution, nullptr, m_stream);
    m_prev_proximity_map_d = to_device(m_prev_proximity_map, m_stream);

    m_prev_placements = PlacementMapT::create(resolution, resolution, nullptr, m_stream);
    m_prev_placements_d = to_device(m_prev_placements, m_stream);

    m_cur_placements = PlacementMapT::create(resolution, resolution, nullptr, m_stream);
    m_cur_placements_d = to_device(m_cur_placements, m_stream);

    m_placement_solver = std::make_unique<PlacementSolver>(m_num_placements, resolution, m_stream);
    CHECK_CU(cudaStreamSynchronize(m_stream));

    tfm::printf("[INFO ] [Converter] Allocations:\n");
    tfm::printf("[INFO ] [Converter]   Num placements: %zu\n", m_num_placements);
    tfm::printf("[INFO ] [Converter]   Color map: %dx%d, %p (%zu bytes)\n",
                resolution,
                resolution,
                m_color_map_d,
                m_color_map.data_size());
    tfm::printf("[INFO ] [Converter]   Proximity map: %dx%d, %p (%zu bytes)\n",
                resolution,
                resolution,
                m_prev_proximity_map_d,
                m_prev_proximity_map.data_size());
    tfm::printf("[INFO ] [Converter]   Previous placement map: %dx%d, %p (%zu bytes)\n",
                resolution,
                resolution,
                m_prev_placements_d,
                m_prev_placements.data_size());
    tfm::printf("[INFO ] [Converter]   Current placement map: %dx%d, %p (%zu bytes)\n",
                resolution,
                resolution,
                m_cur_placements_d,
                m_cur_placements.data_size());
}

uint8_t Converter::calc_proximity_threshold(int resolution) { return 1; }

uint8_t Converter::calc_proximity_max_value(int resolution)
{
    // If the resolution is 16, we opt to use a proximity max value of 2.
    // We use this ratio to calculate the proximity max value for any resolution

    float r = 2.f / 16.f;
    int v = (int) (r * float(resolution));
    return (uint8_t) std::min(v, 254);
}

glm::mat4 Converter::model2brick_matrix(const Model& model, const glm::mat4& model_orientation, int resolution)
{
    glm::vec3 a = model_orientation * glm::vec4(model.m_min, 1.0f);
    glm::vec3 b = model_orientation * glm::vec4(model.m_max, 1.0f);
    glm::vec3 min_ = glm::min(a, b);
    glm::vec3 max_ = glm::max(a, b);
    glm::vec3 model_size = max_ - min_;
    float max_xz_side = glm::max(model_size.x, model_size.z);
    // Transform from Model space to Brick space
    glm::mat4 transform = glm::identity<glm::mat4>();
    glm::vec3 scale{float(resolution) / max_xz_side};
    scale.y /= 1.2f; // Brick height adjustment
    transform = glm::scale(transform, scale);
    transform = glm::translate(transform, -min_); // Bring to origin
    transform = transform * model_orientation;
    return transform;
}

void Converter::transform_model()
{
    glm::mat4 model2brick = model2brick_matrix(*m_model, m_params.model_orientation, m_params.resolution);
    m_model->apply_transform(model2brick);
    m_model->update_min_max(true /* update_mesh_min_max */);
}

void Converter::init_proximity_map_from_color_map()
{
    m_prev_proximity_map.fill(0, m_stream);

    dim3 num_blocks{};
    num_blocks.x = div_ceil<size_t>(m_params.resolution, 32);
    num_blocks.y = div_ceil<size_t>(m_params.resolution, 32);
    num_blocks.z = 1;
    dim3 block_dim(32, 32, 1);
    init_proximity_map_from_color_map_kernel<<<num_blocks, block_dim, 0, m_stream>>>(
        m_color_map_d, m_proximity_max_value /* init_val */, m_prev_proximity_map_d);
}

size_t Converter::place_on_subslice(uint32_t slice_y, int subslice)
{
    size_t num_placed_bricks = 0;

    StopWatch log_stopwatch{};

    CHECK_CU(cudaMemsetAsync(m_valid_placements_d, true, m_num_placements * sizeof(bool), m_stream));

    CUDAStopwatch stopwatch;

    while (true) {
        /* Find best placement */
        stopwatch.start(m_stream);

        PlacementSolver::Input params{};
        params.is_subslice0 = subslice == -1 || subslice == 0;
        params.color_map_d = m_color_map_d;
        params.current_placement_map_d = m_cur_placements_d;
        params.previous_placement_map_d = m_prev_placements_d;
        params.proximity_map_d = m_prev_proximity_map_d;
        auto [placement, reward] = m_placement_solver->solve(params, m_stream); // Already synchronizes the stream

        stopwatch.stop(m_stream);
        m_stats.subslice_solve_placement_dt[subslice == -1 ? 0 : subslice].add(stopwatch.pull_sync());

        if (reward < m_min_reward) break;

        /* Set the placement in the current placements map */
        uint16_t pid = m_next_pid;
        ++m_next_pid;
        // TODO 64 iterations... not very efficient...
        //  every write is a host-to-device copy...
        const auto& brick = k_bricks[placement.bid];
        for (int bz = 0; bz < BRICK_MAX_EXTENT_Z; bz++) {
            for (int bx = 0; bx < BRICK_MAX_EXTENT_X; bx++) {
                if (brick[bz][bx]) {
                    m_cur_placements.write_pixel(
                        placement.x + bx, placement.z + bz, glm::vec<1, uint16_t>{pid}, m_stream);
                }
            }
        }

        /* Stack placement (if needed) */
        uint8_t subslice_mask = subslice == -1 ? 0x7 : 1 << subslice;
        placement.subslice_mask = subslice_mask;
        placement.cid = 0;
        auto [iterator, inserted] = m_stacked_placements.emplace(placement);
        // If we're placing complete bricks, stacked placements shouldn't already contain this placement
        CHECK_STATE(subslice == -1 && inserted);
        // If the placement is stacked 3 times (3 equal placements for the slice), then can be compacted
        if (!inserted) iterator->subslice_mask |= subslice_mask;

        for (const auto& listener : m_listeners) listener->on_place(m_slice_y, placement, reward);

        if (log_stopwatch.elapsed_seconds() >= 5.0) {
            printf("[Converter] PLACE %d; Placed bricks: %zu, Last placement: (%d, %d) -> BID %d, Last reward: %.3f, "
                   "Reward threshold: %.3f\n",
                   subslice,
                   num_placed_bricks,
                   placement.x,
                   placement.z,
                   placement.bid,
                   reward,
                   m_min_reward);
            log_stopwatch.reset();
        }

        ++num_placed_bricks;
    }

    return num_placed_bricks;
}

void Converter::linearize_placements()
{
    ARP_DEBUG("Linearizing placements...");

    m_linear_stacked_placements.clear();

    size_t num_placements = m_stacked_placements.size();
    if (num_placements == 0) return;

    // Copy placements unordered_set to linear memory (vector) for GPU uploading
    m_linear_stacked_placements.resize(num_placements);
    std::copy(m_stacked_placements.begin(), m_stacked_placements.end(), m_linear_stacked_placements.begin());

    ARP_DEBUG("%zu placements linearized", m_linear_stacked_placements.size());

    ARP_DEBUG("Placements:");
    for (int pi = 0; pi < m_linear_stacked_placements.size(); ++pi) {
        const Placement& placement = m_linear_stacked_placements[pi];
        ARP_DEBUG("  %3d Placement BID: %2d, X: %3d, Y: %3d, Subslice mask: %d, CID: %2d",
                  pi,
                  placement.bid,
                  placement.x,
                  placement.z,
                  placement.subslice_mask,
                  placement.cid);
    }
}

void Converter::color_placements()
{
    if (m_linear_stacked_placements.empty()) return;
    size_t N = m_linear_stacked_placements.size();
    Placement* placements_d;
    /* Upload placements to GPU */
    CHECK_CU(cudaMallocAsync(&placements_d, N * sizeof(Placement), m_stream));
    CHECK_CU(cudaMemcpyAsync(
        placements_d, m_linear_stacked_placements.data(), N * sizeof(Placement), cudaMemcpyHostToDevice, m_stream));
    /* Assign colors to placements */
    BrickColors& colors = BrickColors::get();
    AssignPlacementColor::assign(m_color_map, placements_d, N, colors.color_masks_d());
    /* Bring colors to host */
    CHECK_CU(cudaMemcpyAsync(
        m_linear_stacked_placements.data(), placements_d, N * sizeof(Placement), cudaMemcpyDeviceToHost, m_stream));
    CHECK_CU(cudaFreeAsync(placements_d, m_stream));
    CHECK_CU(cudaStreamSynchronize(m_stream));
}

void Converter::start()
{
    CHECK_STATE(!m_done, "The converter was already started and is done");

    m_self_d = to_device(*this, m_stream); // Make a screenshot of "this" and transfer it on device

    StopWatch stopwatch{};
    std::string dur_str;

    // LOAD MODEL
    printf("[Converter] Loading model: %s\n", m_params.model_path.c_str());

    stopwatch.reset();

    GltfLoader gltf_loader{};
    m_model = std::make_unique<Model>(gltf_loader.load_file(m_params.model_path));

    m_num_slices = calc_num_slices(*m_model, m_params.resolution);

    transform_model();

    for (const auto& listener : m_listeners) listener->on_model_load(*m_model);

    dur_str = stopwatch.elapsed_time_str();
    printf("[Converter] Model loaded in %s\n", dur_str.c_str());

    //
    int num_slices = glm::ceil(m_model->size().y);

    m_slicer = std::make_unique<Slicer>(*m_model, m_params.resolution, m_params.alpha_test_threshold, m_stream);
    m_model.reset(); // We don't need host-side model anymore

    // INIT
    m_prev_placements.fill(ARP_NO_PLACEMENT_VALUE, m_stream);
    m_cur_placements.fill(ARP_NO_PLACEMENT_VALUE, m_stream);
    m_prev_proximity_map.fill(0, m_stream);

    CHECK_CU(cudaStreamSynchronize(m_stream));

    CUDAStopwatch slice_stopwatch{};
    CUDAStopwatch voxelization_stopwatch{};
    CUDAStopwatch subslice0_stopwatch{};
    CUDAStopwatch subslice1_stopwatch{};
    CUDAStopwatch subslice2_stopwatch{};
    CUDAStopwatch spread_proximity_stopwatch{};
    CUDAStopwatch color_placements_stopwatch{};
    size_t subslice0_num_placements = 0;
    size_t subslice1_num_placements = 0;
    size_t subslice2_num_placements = 0;

    for (m_slice_y = 0; m_slice_y < num_slices; m_slice_y++) {
        if (m_stop) return;

        slice_stopwatch.start(m_stream);

        ARP_INFO(
            "---------------------------------------------------------------- Slice %d/%d", m_slice_y + 1, num_slices);

        m_stacked_placements.clear();
        m_next_pid = 0;

        // COMPUTE SLICE (i.e. voxelization)
        voxelization_stopwatch.start(m_stream);

        m_slicer->slice(m_slice_y, m_color_map, m_stream);

        voxelization_stopwatch.stop(m_stream);

        ARP_INFO("Voxelization performed in %s", stopwatch.elapsed_time_str().c_str());

        // PLACEMENT BEGIN
        for (const auto& listener : m_listeners) listener->on_placement_begin(m_slice_y);

        if (m_params.use_subslices) {
            // PLACE0
            subslice0_stopwatch.start(m_stream);
            subslice0_num_placements = place_on_subslice(m_slice_y, 0 /* subslice */);
            subslice0_stopwatch.stop(m_stream);

            m_prev_placements.copy_from(m_cur_placements, m_stream);
            m_cur_placements.fill(ARP_NO_PLACEMENT_VALUE, m_stream);

            // PLACE1
            subslice1_stopwatch.start(m_stream);
            subslice1_num_placements = place_on_subslice(m_slice_y, 1 /* subslice */);
            subslice1_stopwatch.stop(m_stream);

            m_prev_placements.copy_from(m_cur_placements, m_stream);
            m_cur_placements.fill(ARP_NO_PLACEMENT_VALUE, m_stream);

            // PLACE2
            subslice2_stopwatch.start(m_stream);
            subslice2_num_placements = place_on_subslice(m_slice_y, 2 /* subslice */);
            subslice2_stopwatch.stop(m_stream);
        } else {
            // PLACE0
            subslice0_stopwatch.start(m_stream);
            subslice0_num_placements = place_on_subslice(m_slice_y, -1 /* subslice */);
            subslice0_stopwatch.stop(m_stream);
        }

        m_prev_placements.copy_from(m_cur_placements, m_stream);
        m_cur_placements.fill(ARP_NO_PLACEMENT_VALUE, m_stream);

        /* Linearize (stacked) placements */
        linearize_placements();

        /* Color placements */
        color_placements_stopwatch.start(m_stream);
        color_placements();
        color_placements_stopwatch.stop(m_stream);

        // SLICE END
        for (const auto& listener : m_listeners) {
            listener->on_placement_end(m_slice_y, m_linear_stacked_placements);
        }

        // COMPUTE PROXIMITY MAP
        spread_proximity_stopwatch.start(m_stream);

        // Seed the proximity map with initial values and spread them
        init_proximity_map_from_color_map();
        m_spread_value.spread(m_prev_proximity_map, m_proximity_max_value /* num_iterations */, m_stream);

        spread_proximity_stopwatch.stop(m_stream);

        CHECK_CU(cudaStreamSynchronize(m_stream));

        /* Pull performance stats */
        float voxelization_dt = voxelization_stopwatch.pull_sync();
        float subslice0_dt = subslice0_stopwatch.pull_sync();
        float subslice1_dt = subslice1_stopwatch.pull_sync();
        float subslice2_dt = subslice2_stopwatch.pull_sync();
        float spread_proximity_map_dt = spread_proximity_stopwatch.pull_sync();
        float color_placements_dt = color_placements_stopwatch.pull_sync();

        ARP_INFO("Slice %d voxelization performed in %.1fms", m_slice_y, voxelization_dt);
        ARP_INFO("Subslice 0 covered in %.1fms; Placed bricks: %zu", subslice0_dt, subslice0_num_placements);
        ARP_INFO("Subslice 1 covered in %.1fms; Placed bricks: %zu", subslice1_dt, subslice1_num_placements);
        ARP_INFO("Subslice 2 covered in %.1fms; Placed bricks: %zu", subslice2_dt, subslice2_num_placements);
        ARP_INFO("Proximity map computed in %.1fms", spread_proximity_map_dt);
        ARP_INFO("Placements colored in %.1fms", color_placements_dt);

        m_stats.voxelization_dt.add(voxelization_dt);
        m_stats.subslice_dt[0].add(subslice0_dt);
        m_stats.subslice_dt[1].add(subslice1_dt);
        m_stats.subslice_dt[2].add(subslice2_dt);
        m_stats.spread_proximity_map_dt.add(spread_proximity_map_dt);
        m_stats.color_placements_dt.add(color_placements_dt);
    }

    m_done = true;
}
