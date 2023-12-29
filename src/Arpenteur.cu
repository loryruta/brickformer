#include "Arpenteur.cuh"

#include <thrust/extrema.h>

#include "bricks.cuh"
#include "model/GltfLoader.hpp"
#include "reward_func.cuh"
#include "util/StopWatch.hpp"

using namespace lego_builder;

Arpenteur::Arpenteur(const std::filesystem::path& model_path, uint32_t slice_side, ArpenteurListener& listener)
{
    m_model_path = model_path;
    m_slice_side = slice_side;
    m_listener = &listener;

    m_num_placements = slice_side * slice_side * k_num_bricks;

    CHECK_CU(cudaMalloc(&m_placements_d, m_num_placements * sizeof(Placement)));
    init_placements();

    CHECK_CU(cudaMalloc(&m_rewards_d, m_num_placements * sizeof(float)));

    m_color_map = ColorMapT::create(slice_side, slice_side, nullptr);
    m_color_map_d = to_device(m_color_map);

    m_prev_proximity_map = ProximityMapT::create(slice_side, slice_side, nullptr);
    m_prev_proximity_map_d = to_device(m_prev_proximity_map);

    m_prev_placements = PlacementMapT::create(slice_side, slice_side, nullptr);
    m_prev_placements_d = to_device(m_prev_placements);

    m_cur_placements = PlacementMapT::create(slice_side, slice_side, nullptr);
    m_cur_placements_d = to_device(m_cur_placements);
}

__global__
void init_placements_kernel(Arpenteur* self)
{
    size_t i = blockIdx.x * blockDim.x + threadIdx.x;

    uint32_t slice_side = self->m_slice_side;

    if (i < self->m_num_placements)
    {
        Placement& placement = self->m_placements_d[i];

        placement.m_bid = i % k_num_bricks;
        placement.m_x = (i / k_num_bricks) % slice_side;
        placement.m_y = i / (slice_side * k_num_bricks);
    }
}

void Arpenteur::init_placements()
{
    size_t num_blocks = div_ceil<size_t>(m_num_placements, 1024);
    init_placements_kernel<<<num_blocks, 1024>>>(to_device(*this));  // this to device, even if some fields aren't initialized yet
}

void Arpenteur::transform_model_to_grid()
{
    glm::vec3 model_size = m_model->size();
    float max_xz_side = glm::max(model_size.x, model_size.z);

    glm::mat4 transform = glm::identity<glm::mat4>();
    transform = glm::scale(transform, glm::vec3(m_slice_side / max_xz_side));
    transform = glm::translate(transform, -m_model->m_min);

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
    num_blocks.x = div_ceil<size_t>(m_slice_side, 32);
    num_blocks.y = div_ceil<size_t>(m_slice_side, 32);
    num_blocks.z = 1;

    dim3 block_dim(32, 32, 1);
    init_proximity_map_from_color_map_kernel<<<num_blocks, block_dim>>>(m_color_map_d, m_prev_proximity_map_d);
    CHECK_CU(cudaDeviceSynchronize());
}

template<bool IS_SUBSLICE0>
__global__
void eval_placements_kernel(Arpenteur* self)
{
    size_t i = blockIdx.x;

    if (i < self->m_num_placements)
    {
        Placement& placement = self->m_placements_d[i];

        float reward = eval_placement<IS_SUBSLICE0>(*self, placement);
        self->m_rewards_d[i] = reward;
    }
}

template<uint32_t SUBSLICE>
std::pair<Placement, float> Arpenteur::compute_next_placement()
{
    CHECK_CU(cudaMemset(m_rewards_d, 0, m_num_placements * sizeof(float)));
    CHECK_CU(cudaDeviceSynchronize());

    size_t num_blocks = m_num_placements;
    size_t dim_block = 32;
    eval_placements_kernel<SUBSLICE == 0><<<num_blocks, dim_block>>>(m_self_d);
    CHECK_CU(cudaDeviceSynchronize());

    float* max_reward_d = thrust::max_element(
        thrust::device, m_rewards_d, m_rewards_d + m_num_placements);  // Fake IDE error on CLion :')
    size_t max_i = max_reward_d - m_rewards_d;

    return {to_host(&m_placements_d[max_i]), to_host(max_reward_d)};
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
            if (brick[bx][by])
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

    StopWatch log_stop_watch{};

    while (true)
    {
        auto [placement, reward] = compute_next_placement<SUBSLICE>();

        //printf("PLACEMENT %zu; Placement: (%d, %d) -> BID %d; Reward: %.3f\n", i + 1, placement.m_x, placement.m_y, placement.m_bid, reward);

        if (reward < m_min_reward) break;

        place(placement);

        uint8_t subslice_bit = 1 << SUBSLICE;
        auto [iterator, inserted] = m_stacked_placements.emplace(placement, subslice_bit);
        if (!inserted) iterator->second |= subslice_bit;
        // If the placement is stacked 3 times (3 equal placements for the slice), then can be compacted

        if (m_listener) m_listener->on_place(slice_y, placement, reward);

        if (log_stop_watch.elapsed_millis() >= 5000)
        {
            printf("[Arpenteur] PLACE %d; Placed bricks: %zu, Last placement: (%d, %d) -> BID %d, Last reward: %.3f, Reward threshold: %.3f\n",
                   SUBSLICE, num_placed_bricks,
                   placement.m_x, placement.m_y, placement.m_bid,
                   reward,
                   m_min_reward
                   );
            log_stop_watch.reset();
        }

        ++num_placed_bricks;
    }

    return num_placed_bricks;
}

void Arpenteur::run()
{
    m_self_d = to_device(*this);  // Make a screenshot of "this" and transfer it on device

    StopWatch stop_watch{};
    std::string dur_str;

    // LOAD MODEL
    printf("[Arpenteur] Loading model: %s\n", m_model_path.c_str());

    stop_watch.reset();

    GltfLoader gltf_loader{};
    m_model = std::make_unique<Model>(gltf_loader.load_file(m_model_path));

    transform_model_to_grid();

    if (m_listener) m_listener->on_model_load(*m_model);

    dur_str = stop_watch.elapsed_time_str();
    printf("[Arpenteur] Model loaded in %s\n", dur_str.c_str());

    //
    uint32_t num_slices = glm::ceil(m_model->size().y);

    m_slicer = std::make_unique<Slicer>(*m_model, m_slice_side);
    m_model.reset();  // We don't need host-side model anymore

    // INIT
    m_prev_placements.fill(0xFFFF);
    m_cur_placements.fill(0);
    m_prev_proximity_map.fill(PROXIMITY_MAP_HIGH_VALUE);

    for (uint32_t slice_y = 0; slice_y < num_slices; slice_y++)
    {
        printf("[Arpenteur] Slice %d/%d\n", slice_y, num_slices);

        m_stacked_placements.clear();
        m_next_pid = 0;

        // COMPUTE SLICE (i.e. voxelization)
        stop_watch.reset();

        m_slicer->slice(slice_y, m_color_map);

        printf("[Arpenteur]   COMPUTE SLICE; %s\n", stop_watch.elapsed_time_str().c_str());

        // PLACEMENT BEGIN
        if (m_listener) m_listener->on_placement_begin(slice_y);

        size_t num_placed_bricks;

        // PLACE0
        stop_watch.reset();

        num_placed_bricks = place_on_subslice<0>(slice_y);

        m_prev_placements.copy_from(m_cur_placements);
        m_cur_placements.fill(0);

        printf("[Arpenteur]   PLACE 0; Placed bricks: %zu, Elapsed: %s\n",
               num_placed_bricks, stop_watch.elapsed_time_str().c_str());

        // PLACE1
        stop_watch.reset();

        num_placed_bricks = place_on_subslice<1>(slice_y);

        m_prev_placements.copy_from(m_cur_placements);
        m_cur_placements.fill(0);

        printf("[Arpenteur]   PLACE 1; Placed bricks: %zu, Elapsed: %s\n",
               num_placed_bricks, stop_watch.elapsed_time_str().c_str());

        // PLACE2
        stop_watch.reset();

        num_placed_bricks = place_on_subslice<2>(slice_y);

        m_prev_placements.copy_from(m_cur_placements);
        m_cur_placements.fill(0);

        printf("[Arpenteur]   PLACE 2; Placed bricks: %zu, Elapsed: %s\n",
               num_placed_bricks, stop_watch.elapsed_time_str().c_str());

        // SLICE END
        if (m_listener) m_listener->on_placement_end(slice_y);

        // COMPUTE PROXIMITY MAP
        stop_watch.reset();

        init_proximity_map_from_color_map();          // Init colored cells to PROXIMITY_MAP_HIGH_VALUE
        m_spread_value.spread(m_prev_proximity_map);  // Spread the init values on the proximity map

        printf("[Arpenteur]   COMPUTE PROXIMITY MAP; %s\n", stop_watch.elapsed_time_str().c_str());
    }
}
