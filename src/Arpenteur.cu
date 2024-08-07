#include "Arpenteur.cuh"

#include <thrust/extrema.h>
#include <cuda_profiler_api.h>

#include "bricks.hpp"
#include "colorize_placements.cuh"
#include "model/GltfLoader.hpp"
#include "reward_func.cuh"
#include "types.cuh"
#include "util/StopWatch.hpp"

using namespace lego_builder;

Arpenteur::Arpenteur(const ArpenteurInput& input) :
    m_input(input)
{
    int resolution = input.resolution;
    m_num_placements = resolution * resolution * k_num_bricks;

    CHECK_CU(cudaMalloc(&m_placements_d, m_num_placements * sizeof(Placement)));
    init_placements();

    CHECK_CU(cudaMalloc(&m_rewards_d, m_num_placements * sizeof(float)));

    CHECK_CU(cudaMalloc(&m_valid_placements_d, m_num_placements * sizeof(bool)));

    m_color_map = ColorMapT::create(resolution, resolution, nullptr);
    m_color_map_d = to_device(m_color_map);

    m_prev_proximity_map = ProximityMapT::create(resolution, resolution, nullptr);
    m_prev_proximity_map_d = to_device(m_prev_proximity_map);

    m_prev_placements = PlacementMapT::create(resolution, resolution, nullptr);
    m_prev_placements_d = to_device(m_prev_placements);

    m_cur_placements = PlacementMapT::create(resolution, resolution, nullptr);
    m_cur_placements_d = to_device(m_cur_placements);

    m_colored_placements.reserve(k_max_colored_placements);
    CHECK_CU(cudaMalloc(&m_colored_placements_d, k_max_colored_placements * sizeof(ColoredPlacement)));
}

__global__
void init_placements_kernel(Arpenteur* self)
{
    size_t i = blockIdx.x * blockDim.x + threadIdx.x;

    uint32_t resolution = self->m_input.resolution;

    if (i < self->m_num_placements)
    {
        Placement& placement = self->m_placements_d[i];

        placement.m_bid = i % k_num_bricks;
        placement.m_x = (i / k_num_bricks) % resolution;
        placement.m_y = i / (resolution * k_num_bricks);
    }
}

void Arpenteur::init_placements()
{
    size_t num_blocks = div_ceil<size_t>(m_num_placements, 1024);
    init_placements_kernel<<<num_blocks, 1024>>>(to_device(*this));  // this to device, even if some fields aren't initialized yet
}

void Arpenteur::transform_model()
{
    glm::vec3 model_size = m_model->size();
    float max_xz_side = glm::max(model_size.x, model_size.z);

    // Transform from Model space to Conversion space
    glm::vec3 scale_matrix{m_input.resolution / max_xz_side};
    scale_matrix.y /= 1.2f;  // Brick height adjustment

    glm::mat4 transform = glm::identity<glm::mat4>();
    transform = glm::scale(transform, scale_matrix);
    transform = glm::translate(transform, -m_model->m_min); // Bring to origin

    m_model->apply_flip(m_input.flip_x, m_input.flip_y, m_input.flip_z, transform);

    m_model->apply_transform(transform);
    m_model->update_min_max(true /* update_mesh_min_max */);
}

__global__
void init_proximity_map_from_color_map_kernel(const ColorMapT* color_map, ProximityMapT* out_proximity_map)
{
    assert(color_map->m_width == out_proximity_map->m_width && color_map->m_height == out_proximity_map->m_height);

    uint32_t px = blockIdx.x * blockDim.x + threadIdx.x;
    uint32_t py = blockIdx.y * blockDim.y + threadIdx.y;

    if (px < color_map->m_width && py < color_map->m_height)
    {
        bool colored = color_map->read_pixel(px, py).a > 0;
        if (colored)
        {
            uint8_t v = PROXIMITY_MAP_HIGH_VALUE;
            v |= 0x80;
            out_proximity_map->write_pixel(px, py, glm::vec<1, uint8_t>{v});
        }
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
    init_proximity_map_from_color_map_kernel<<<num_blocks, block_dim>>>(m_color_map_d, m_prev_proximity_map_d);
    CHECK_CU(cudaDeviceSynchronize());
}

template<bool IS_SUBSLICE0>
__global__
void eval_placements_kernel(Arpenteur* self)
{
    uint32_t warp_i = blockIdx.x * 32 + (threadIdx.x >> 5); // One placement per warp

    if (warp_i < self->m_num_placements)
    {
        if (!self->m_valid_placements_d[warp_i]) return;

        Placement& placement = self->m_placements_d[warp_i];

        float reward;
        bool is_valid = eval_placement<IS_SUBSLICE0>(*self, placement, reward);

        if ((threadIdx.x & 0x1F) == 0)
        {
            if (!is_valid) self->m_valid_placements_d[warp_i] = false;
            self->m_rewards_d[warp_i] = is_valid ? reward : 0.0f;
        }
    }
}

template<uint32_t SUBSLICE>
std::pair<Placement, float> Arpenteur::compute_next_placement()
{
    // Not necessary because every placement will write its reward
    //CHECK_CU(cudaMemset(m_rewards_d, 0, m_num_placements * sizeof(float)));
    //CHECK_CU(cudaDeviceSynchronize());

    CHECK_CU(cudaProfilerStart());

    size_t num_blocks = div_ceil<size_t>(m_num_placements, 32);
    size_t dim_block = 1024;
    eval_placements_kernel<SUBSLICE == 0><<<num_blocks, dim_block>>>(m_self_d);
    CHECK_CU(cudaDeviceSynchronize());

    CHECK_CU(cudaProfilerStop());

    float* max_reward_d = thrust::max_element(
        thrust::device, m_rewards_d, m_rewards_d + m_num_placements);  // Fake IDE error on CLion :')
    size_t max_i = max_reward_d - m_rewards_d;

    std::pair<Placement, float> result = {to_host(&m_placements_d[max_i]), to_host(max_reward_d)};
    return result;
}

void Arpenteur::place(const Placement& placement)
{
    uint16_t pid = m_next_pid;
    ++m_next_pid;

    // TODO 64 iterations... not very efficient...
    //  every write is a host-to-device copy...
    auto& brick = k_bricks[placement.m_bid];
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
}

template<uint32_t SUBSLICE>
size_t Arpenteur::place_on_subslice(uint32_t slice_y)
{
    size_t num_placed_bricks = 0;

    StopWatch log_stopwatch{};

    CHECK_CU(cudaMemset(m_valid_placements_d, true, m_num_placements * sizeof(bool)));
    CHECK_CU(cudaDeviceSynchronize());

    while (true)
    {
        auto [placement, reward] = compute_next_placement<SUBSLICE>();

        if (reward < m_min_reward) break;

        if (false) {
            printf("[DEBUG] [Arpenteur] Placing brick %d at (%d, %d), reward: %f\n", placement.m_bid, placement.m_x, placement.m_y, reward);
            printf("[DEBUG] [Arpenteur] Placement; BID: %d, Pos: (%d, %d)\n", placement.m_bid, placement.m_x, placement.m_y);
            printf("[DEBUG] [Arpenteur]   is_outside: %s, "
                   "is_overlapping: %s, "
                   "num_covered_map_cells: %d, "
                   "brick_size: %d, "
                   "num_neighbors: %d, "
                   "num_connectible_sides: %d, "
                   "num_connected_bricks: %d\n",
                   placement.computed.is_outside ? "y" : "n",
                   placement.computed.is_overlapping ? "y" : "n",
                   placement.computed.num_covered_map_cells,
                   placement.computed.brick_size,
                   placement.computed.num_neighbors,
                   placement.computed.num_connectible_sides,
                   placement.computed.num_connected_bricks
            );
        }

        place(placement);

        uint8_t subslice_bit = 1 << SUBSLICE;
        auto [iterator, inserted] = m_stacked_placements.emplace(placement, subslice_bit);
        if (!inserted) iterator->second |= subslice_bit;
        // If the placement is stacked 3 times (3 equal placements for the slice), then can be compacted

        if (m_listener) m_listener->on_place(m_slice_y, placement, reward);

        if (log_stopwatch.elapsed_millis() >= 5000)
        {
            printf("[Arpenteur] PLACE %d; Placed bricks: %zu, Last placement: (%d, %d) -> BID %d, Last reward: %.3f, Reward threshold: %.3f\n",
                   SUBSLICE, num_placed_bricks,
                   placement.m_x, placement.m_y, placement.m_bid,
                   reward,
                   m_min_reward
                   );
            log_stopwatch.reset();
        }

        ++num_placed_bricks;
    }

    return num_placed_bricks;
}

void Arpenteur::linearize_and_colorize()
{
    m_colored_placements.clear();

    CHECK_STATE_MSG(m_stacked_placements.size() < k_max_colored_placements,
                    "Too many placements! You must increase the buffer size");

    // Empty the stacked placements hashmap into a vector
    for (auto& [placement, subslice_mask] : m_stacked_placements)
    {
        ColoredPlacement colored_placement{};
        colored_placement.m_placement = placement;
        colored_placement.m_subslice_mask = subslice_mask;
        m_colored_placements.emplace_back(colored_placement);
    }

    // Copy the vector to device
    CHECK_CU(cudaMemcpy(m_colored_placements_d, m_colored_placements.data(), m_colored_placements.size() * sizeof(ColoredPlacement), cudaMemcpyHostToDevice));

    // Colorize!
    const size_t num_blocks = div_ceil<size_t>(m_colored_placements.size(), 32);
    const size_t dim_block = 1024;
    compute_placements_color_kernel<<<num_blocks, dim_block>>>(m_self_d, m_colored_placements_d, m_colored_placements.size());
    CHECK_CU(cudaDeviceSynchronize());

    // Copy the vector back to host
    CHECK_CU(cudaMemcpy(m_colored_placements.data(), m_colored_placements_d, m_colored_placements.size() * sizeof(ColoredPlacement), cudaMemcpyDeviceToHost));

    // TODO There could be placements without a color!
    //   Because not all placements cover at least one colored cell of the Color map.
}

void Arpenteur::run()
{
    m_self_d = to_device(*this);  // Make a screenshot of "this" and transfer it on device

    StopWatch stop_watch{};
    std::string dur_str;

    // LOAD MODEL
    printf("[Arpenteur] Loading model: %s\n", m_input.model_path.c_str());

    stop_watch.reset();

    GltfLoader gltf_loader{};
    m_model = std::make_unique<Model>(gltf_loader.load_file(m_input.model_path));

    transform_model();

    if (m_listener) m_listener->on_model_load(*m_model);

    dur_str = stop_watch.elapsed_time_str();
    printf("[Arpenteur] Model loaded in %s\n", dur_str.c_str());

    //
    int num_slices = glm::ceil(m_model->size().y);

    m_slicer = std::make_unique<Slicer>(*m_model, m_input.resolution, m_input.alpha_test_threshold);
    m_model.reset();  // We don't need host-side model anymore

    // INIT
    m_prev_placements.fill(0xFFFF);
    m_cur_placements.fill(0);
    m_prev_proximity_map.fill(PROXIMITY_MAP_HIGH_VALUE);

    for (m_slice_y = 0; m_slice_y < num_slices; m_slice_y++)
    {
        if (m_stop) return;

        printf("[Arpenteur] Slice %d/%d\n", m_slice_y, num_slices);

        m_stacked_placements.clear();
        m_colored_placements.clear();
        m_next_pid = 0;

        // COMPUTE SLICE (i.e. voxelization)
        stop_watch.reset();

        m_slicer->slice(m_slice_y, m_color_map);

        printf("[Arpenteur]   COMPUTE SLICE; %s\n", stop_watch.elapsed_time_str().c_str());

        // PLACEMENT BEGIN
        if (m_listener) m_listener->on_placement_begin(m_slice_y);

        size_t num_placed_bricks;

        // PLACE0
        stop_watch.reset();

        num_placed_bricks = place_on_subslice<0>(m_slice_y);

        m_prev_placements.copy_from(m_cur_placements);
        m_cur_placements.fill(0);

        printf("[Arpenteur]   PLACE 0; Placed bricks: %zu, Elapsed: %s\n",
               num_placed_bricks, stop_watch.elapsed_time_str().c_str());

        // PLACE1
        stop_watch.reset();

        num_placed_bricks = place_on_subslice<1>(m_slice_y);

        m_prev_placements.copy_from(m_cur_placements);
        m_cur_placements.fill(0);

        printf("[Arpenteur]   PLACE 1; Placed bricks: %zu, Elapsed: %s\n",
               num_placed_bricks, stop_watch.elapsed_time_str().c_str());

        // PLACE2
        stop_watch.reset();

        num_placed_bricks = place_on_subslice<2>(m_slice_y);

        m_prev_placements.copy_from(m_cur_placements);
        m_cur_placements.fill(0);

        printf("[Arpenteur]   PLACE 2; Placed bricks: %zu, Elapsed: %s\n",
               num_placed_bricks, stop_watch.elapsed_time_str().c_str());

        // LINEARIZE & COLORIZE
        linearize_and_colorize();

        // SLICE END
        if (m_listener) m_listener->on_placement_end(m_slice_y);

        // COMPUTE PROXIMITY MAP
        stop_watch.reset();

        init_proximity_map_from_color_map();          // Init colored cells to PROXIMITY_MAP_HIGH_VALUE
        m_spread_value.spread(m_prev_proximity_map);  // Spread the init values on the proximity map

        printf("[Arpenteur]   COMPUTE PROXIMITY MAP; %s\n", stop_watch.elapsed_time_str().c_str());
    }
}
