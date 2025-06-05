#include "Arpenteur.cuh"

#include <cuda_profiler_api.h>
#include <thrust/extrema.h>
#include <tinyformat.h>

#include "assign_placements_color.cuh"
#include "bricks.hpp"
#include "log.hpp"
#include "model/GltfLoader.hpp"
#include "reward_func.cuh"
#include "types.cuh"
#include "util/StopWatch.hpp"

#define ARP_LOG_CONTEXT "Arpenteur"

using namespace lego_builder;

Arpenteur::Arpenteur(const ArpenteurInput& input) :
    m_input(input)
{
    int resolution = input.resolution;
    tfm::printf("[INFO ] [Arpenteur] Resolution: %d\n", resolution);

    if (m_proximity_threshold == UINT8_MAX)
    {
        m_proximity_threshold = calc_proximity_threshold(resolution);
        tfm::printf("[INFO ] [Arpenteur] Proximity threshold (derived): %d\n", m_proximity_threshold);
    }
    else
    {
        m_proximity_threshold = input.proximity_threshold;
        tfm::printf("[INFO ] [Arpenteur] Proximity threshold: %d\n", m_proximity_threshold);
    }

    if (input.proximity_max_value == UINT8_MAX)
    {
        m_proximity_max_value = calc_proximity_max_value(resolution);
        tfm::printf("[INFO ] [Arpenteur] Proximity max value (derived): %d\n", m_proximity_max_value);
    }
    else
    {
        m_proximity_max_value = input.proximity_max_value;
        tfm::printf("[INFO ] [Arpenteur] Proximity max value: %d\n", m_proximity_max_value);
    }

    m_num_placements = resolution * resolution * k_num_bricks;
    // init_placements();

    CHECK_CU(cudaMalloc(&m_valid_placements_d, m_num_placements * sizeof(bool)));

    m_color_map = ColorMapT::create(resolution, resolution, nullptr);
    m_color_map_d = to_device(m_color_map);

    m_prev_proximity_map = ProximityMapT::create(resolution, resolution, nullptr);
    m_prev_proximity_map_d = to_device(m_prev_proximity_map);

    m_prev_placements = PlacementMapT::create(resolution, resolution, nullptr);
    m_prev_placements_d = to_device(m_prev_placements);

    m_cur_placements = PlacementMapT::create(resolution, resolution, nullptr);
    m_cur_placements_d = to_device(m_cur_placements);

    m_placement_solver = std::make_unique<PlacementSolver>(m_num_placements, resolution);

    tfm::printf("[INFO ] [Arpenteur] Allocations:\n");
    tfm::printf("[INFO ] [Arpenteur]   Num placements: %zu\n", m_num_placements);
    tfm::printf("[INFO ] [Arpenteur]   Color map: %dx%d, %p (%zu bytes)\n", resolution, resolution, m_color_map_d, m_color_map.data_size());
    tfm::printf(
        "[INFO ] [Arpenteur]   Proximity map: %dx%d, %p (%zu bytes)\n", resolution, resolution, m_prev_proximity_map_d, m_prev_proximity_map.data_size()
    );
    tfm::printf(
        "[INFO ] [Arpenteur]   Previous placement map: %dx%d, %p (%zu bytes)\n", resolution, resolution, m_prev_placements_d, m_prev_placements.data_size()
    );
    tfm::printf(
        "[INFO ] [Arpenteur]   Current placement map: %dx%d, %p (%zu bytes)\n", resolution, resolution, m_cur_placements_d, m_cur_placements.data_size()
    );

    cudaDeviceSetLimit(cudaLimitPrintfFifoSize, size_t(1) << 30 /* 1GB */);

    tfm::printf("[DEBUG] [Arpenteur] Device capabilities:\n");
    size_t printf_buffer_size;
    cudaDeviceGetLimit(&printf_buffer_size, cudaLimitPrintfFifoSize);
    tfm::printf("[DEBUG] [Arpenteur]   cudaLimitPrintfFifoSize: %zu KB\n", printf_buffer_size >> 10);
}

uint8_t Arpenteur::calc_proximity_threshold(int resolution)
{
    return 1;
}

uint8_t Arpenteur::calc_proximity_max_value(int resolution)
{
    // If the resolution is 16, we opt to use a proximity max value of 2.
    // We use this ratio to calculate the proximity max value for any resolution

    float r = 2.f / 16.f;
    int v = (int) (r * float(resolution));
    return (uint8_t) std::min(v, 254);
}

void Arpenteur::transform_model()
{
    glm::vec3 model_size = m_model->size();
    float max_xz_side = glm::max(model_size.x, model_size.z);

    // Transform from Model space to Conversion space
    glm::vec3 scale_matrix{m_input.resolution / max_xz_side};
    scale_matrix.y /= 1.2f; // Brick height adjustment

    glm::mat4 transform = glm::identity<glm::mat4>();
    transform = glm::scale(transform, scale_matrix);
    transform = glm::translate(transform, -m_model->m_min); // Bring to origin

    m_model->apply_flip(m_input.flip_x, m_input.flip_y, m_input.flip_z, transform);

    m_model->apply_transform(transform);
    m_model->update_min_max(true /* update_mesh_min_max */);
}

__global__ void init_proximity_map_from_color_map_kernel(const ColorMapT* color_map, uint8_t init_val, ProximityMapT* out_proximity_map)
{
    assert(color_map->m_width == out_proximity_map->m_width && color_map->m_height == out_proximity_map->m_height);

    uint32_t px = blockIdx.x * blockDim.x + threadIdx.x;
    uint32_t py = blockIdx.y * blockDim.y + threadIdx.y;

    if (px < color_map->m_width && py < color_map->m_height)
    {
        bool is_colored = color_map->read_pixel(px, py).a > 0;
        if (is_colored) out_proximity_map->write_pixel(px, py, glm::vec<1, uint8_t>{init_val});
    }
}

void Arpenteur::init_proximity_map_from_color_map()
{
    m_prev_proximity_map.fill(0);

    dim3 num_blocks{};
    num_blocks.x = div_ceil<size_t>(m_input.resolution, 32);
    num_blocks.y = div_ceil<size_t>(m_input.resolution, 32);
    num_blocks.z = 1;

    dim3 block_dim(32, 32, 1);
    init_proximity_map_from_color_map_kernel<<<num_blocks, block_dim>>>(m_color_map_d, m_proximity_max_value /* init_val */, m_prev_proximity_map_d);
    CHECK_CU(cudaDeviceSynchronize());
}

void Arpenteur::place(const Placement& placement)
{
    uint16_t pid = m_next_pid;
    ++m_next_pid;

    // TODO 64 iterations... not very efficient...
    //  every write is a host-to-device copy...
    const auto& brick = k_bricks[placement.m_bid];
    for (uint8_t bx = 0; bx < BRICK_MAX_WIDTH; bx++)
    {
        for (uint8_t by = 0; by < BRICK_MAX_HEIGHT; by++)
        {
            if (brick[by][bx])
            {
                m_cur_placements.write_pixel(placement.m_x + bx, placement.m_y + by, glm::vec<1, uint16_t>{pid});
            }
        }
    }

    // ARP_INFO("Placed BID=%d at (%d, %d) with PID=%d", placement.m_bid, placement.m_x, placement.m_y, pid);
}

size_t Arpenteur::place_on_subslice(uint32_t slice_y, int subslice)
{
    size_t num_placed_bricks = 0;

    StopWatch log_stopwatch{};

    CHECK_CU(cudaMemset(m_valid_placements_d, true, m_num_placements * sizeof(bool)));
    CHECK_CU(cudaDeviceSynchronize());

    while (true)
    {
        PlacementSolver::Input params{};
        params.is_subslice0 = subslice == 0;
        params.color_map_d = m_color_map_d;
        params.current_placement_map_d = m_cur_placements_d;
        params.previous_placement_map_d = m_prev_placements_d;
        params.proximity_map_d = m_prev_proximity_map_d;
        auto [placement, reward] = m_placement_solver->solve(params);
        if (reward < m_min_reward) break;

        place(placement);

        placement.m_subslice_mask = 1 << subslice;
        placement.m_cid = 0;
        auto [iterator, inserted] = m_stacked_placements.emplace(placement);
        if (!inserted) iterator->m_subslice_mask |= 1 << subslice;
        // If the placement is stacked 3 times (3 equal placements for the slice), then can be compacted

        for (const auto& listener : m_listeners) listener->on_place(m_slice_y, placement, reward);

        if (log_stopwatch.elapsed_millis() >= 5000)
        {
            printf(
                "[Arpenteur] PLACE %d; Placed bricks: %zu, Last placement: (%d, %d) -> BID %d, Last reward: %.3f, Reward threshold: %.3f\n", subslice,
                num_placed_bricks, placement.m_x, placement.m_y, placement.m_bid, reward, m_min_reward
            );
            log_stopwatch.reset();
        }

        ++num_placed_bricks;
    }

    return num_placed_bricks;
}

void Arpenteur::linearize_placements_to_output()
{
    ARP_DEBUG("Linearizing placements to output...");

    m_linear_stacked_placements.clear();
    CHECK_STATE(!m_linear_stacked_placements_d);

    size_t num_placements = m_stacked_placements.size();
    if (num_placements == 0)
    {
        ARP_WARN("No placement to color");
        return;
    }

    // Copy placements unordered_set to linear memory (vector) for GPU uploading
    m_linear_stacked_placements.resize(num_placements);
    std::copy(m_stacked_placements.begin(), m_stacked_placements.end(), m_linear_stacked_placements.begin());

    ARP_DEBUG("%zu placements linearized", m_linear_stacked_placements.size());

    // Upload placements on GPU
    CHECK_CU(cudaMalloc(&m_linear_stacked_placements_d, num_placements * sizeof(Placement)));
    CHECK_CU(cudaMemcpy(m_linear_stacked_placements_d, m_linear_stacked_placements.data(), num_placements * sizeof(Placement), cudaMemcpyHostToDevice));

    // Colorize!
    const size_t num_blocks = div_ceil<size_t>(num_placements, 32);
    const size_t block_dim = 1024;
    assign_placements_color_kernel<<<num_blocks, block_dim>>>(m_self_d, m_linear_stacked_placements_d, num_placements);
    CHECK_CU(cudaDeviceSynchronize());

    // Copy placements from GPU back to host to get the color assignments
    CHECK_CU(cudaMemcpy(m_linear_stacked_placements.data(), m_linear_stacked_placements_d, num_placements * sizeof(Placement), cudaMemcpyDeviceToHost));

    CHECK_CU(cudaFree(m_linear_stacked_placements_d));
    m_linear_stacked_placements_d = nullptr;

    ARP_DEBUG("Placements:");
    for (int pi = 0; pi < m_linear_stacked_placements.size(); ++pi)
    {
        const Placement& placement = m_linear_stacked_placements[pi];
        ARP_DEBUG(
            "  %3d Placement BID: %2d, X: %3d, Y: %3d, Subslice mask: %d, CID: %2d", pi, placement.m_bid, placement.m_x, placement.m_y,
            placement.m_subslice_mask, placement.m_cid
        );
    }

    tfm::printf("[Arpenteur] Colored!\n");
}

void Arpenteur::run()
{
    m_self_d = to_device(*this); // Make a screenshot of "this" and transfer it on device

    StopWatch stop_watch{};
    std::string dur_str;

    // LOAD MODEL
    printf("[Arpenteur] Loading model: %s\n", m_input.model_path.c_str());

    stop_watch.reset();

    GltfLoader gltf_loader{};
    m_model = std::make_unique<Model>(gltf_loader.load_file(m_input.model_path));

    transform_model();

    for (const auto& listener : m_listeners) listener->on_model_load(*m_model);

    dur_str = stop_watch.elapsed_time_str();
    printf("[Arpenteur] Model loaded in %s\n", dur_str.c_str());

    //
    int num_slices = glm::ceil(m_model->size().y);

    m_slicer = std::make_unique<Slicer>(*m_model, m_input.resolution, m_input.alpha_test_threshold);
    m_model.reset(); // We don't need host-side model anymore

    // INIT
    m_prev_placements.fill(ARP_NO_PLACEMENT_VALUE);
    m_cur_placements.fill(ARP_NO_PLACEMENT_VALUE);
    m_prev_proximity_map.fill(0);

    for (m_slice_y = 0; m_slice_y < num_slices; m_slice_y++)
    {
        if (m_stop) return;

        ARP_INFO("---------------------------------------------------------------- Slice %d/%d", m_slice_y + 1, num_slices);

        m_stacked_placements.clear();
        m_next_pid = 0;

        // COMPUTE SLICE (i.e. voxelization)
        stop_watch.reset();

        m_slicer->slice(m_slice_y, m_color_map);

        ARP_INFO("Voxelization performed in %s", stop_watch.elapsed_time_str().c_str());

        // PLACEMENT BEGIN
        for (const auto& listener : m_listeners) listener->on_placement_begin(m_slice_y);

        size_t num_placed_bricks;

        // PLACE0
        stop_watch.reset();

        num_placed_bricks = place_on_subslice(m_slice_y, 0 /* subslice */);

        m_prev_placements.copy_from(m_cur_placements);
        m_cur_placements.fill(ARP_NO_PLACEMENT_VALUE);

        ARP_INFO("Subslice 0 covered in %s; Placed bricks: %zu", stop_watch.elapsed_time_str().c_str(), num_placed_bricks);

        // PLACE1
        stop_watch.reset();

        num_placed_bricks = place_on_subslice(m_slice_y, 1 /* subslice */);

        m_prev_placements.copy_from(m_cur_placements);
        m_cur_placements.fill(ARP_NO_PLACEMENT_VALUE);

        ARP_INFO("Subslice 1 covered in %s; Placed bricks: %zu", stop_watch.elapsed_time_str().c_str(), num_placed_bricks);

        // PLACE2
        stop_watch.reset();

        num_placed_bricks = place_on_subslice(m_slice_y, 2 /* subslice */);

        m_prev_placements.copy_from(m_cur_placements);
        m_cur_placements.fill(ARP_NO_PLACEMENT_VALUE);

        ARP_INFO("Subslice 2 covered in %s; Placed bricks: %zu", stop_watch.elapsed_time_str().c_str(), num_placed_bricks);

        // LINEARIZE & COLORIZE
        linearize_placements_to_output();

        // SLICE END
        for (const auto& listener : m_listeners) listener->on_placement_end(m_slice_y, m_linear_stacked_placements);

        // COMPUTE PROXIMITY MAP
        stop_watch.reset();

        init_proximity_map_from_color_map();
        m_spread_value.spread(m_prev_proximity_map, m_proximity_max_value /* num_iterations */); // Spread the init values on the proximity map

        printf("[Arpenteur]   COMPUTE PROXIMITY MAP; %s\n", stop_watch.elapsed_time_str().c_str());
    }
}
