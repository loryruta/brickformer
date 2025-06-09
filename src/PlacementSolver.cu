#include "PlacementSolver.h"

#include <thrust/extrema.h>

#include "bricks.hpp"
#include "log.hpp"
#include "types.cuh"

#define ARP_WARP_INDEX (threadIdx.x >> 5)
#define ARP_IS_WARP_THREAD_0 ((threadIdx.x & 0x1F) == 0)

#define ARP_LOG_CONTEXT "PlacementSolver"

using namespace lego_builder;

/// Iterates the brick grid within the warp and callbacks every occurrence.
/// Important: don't perform warp operations within the callback.
template<typename CALLBACK>
__device__ void iterate_brick_grid(CALLBACK callback)
{
    int lane_i = threadIdx.x & 0x1f;
    int lane_x = lane_i % 5;
    int lane_y = lane_i / 5;

    int num_items_x = div_ceil(BRICK_MAX_EXTENT_X, 5);  // 2
    int num_items_y = div_ceil(BRICK_MAX_EXTENT_Z, 5); // 2

    for (int ix = 0; ix < num_items_x; ix++)
    {
        for (int iy = 0; iy < num_items_y; iy++)
        {
            int bx = lane_x * num_items_x + ix;
            int by = lane_y * num_items_y + iy;
            if (bx < BRICK_MAX_EXTENT_X && by < BRICK_MAX_EXTENT_Z)
            {
                callback(bx, by);
            }
        }
    }
}

/// The index of the placement. Only valid in a setup where every warp is dedicated to one placement.
__device__ int get_placement_index()
{
    return ((blockIdx.x << 5) + (threadIdx.x >> 5));
}

__global__ void internal::init_placements_kernel(Placement* placements, size_t num_placements, int resolution)
{
    int pi = blockIdx.x * blockDim.x + threadIdx.x;
    if (pi >= num_placements) return;

    Placement& placement = placements[pi];
    placement = {}; // Init with default values
    placement.bid = pi % k_num_bricks;
    placement.x = (pi / k_num_bricks) % resolution;
    placement.z = pi / (resolution * k_num_bricks);
    // placement.m_subslice_mask
    // placement.m_cid
}

__global__ void internal::eval_brick_size_kernel(const Placement* placements, size_t num_placements, int* out_brick_sizes)
{
    int pi = get_placement_index();
    if (pi >= num_placements) return;

    __shared__ int brick_size[32];

    int wi = ARP_WARP_INDEX;
    if (ARP_IS_WARP_THREAD_0) brick_size[wi] = 0;
    __syncwarp();

    const Placement& placement = placements[pi];
    auto const& brick = k_bricks[placement.bid];
    iterate_brick_grid(
        [&](int bx, int by)
        {
            if (brick[by][bx]) atomicAdd_block(&brick_size[wi], 1);
        }
    );

    if (ARP_IS_WARP_THREAD_0) out_brick_sizes[pi] = brick_size[wi];
}

/// Evaluate the number of connectible sides for every placement (e.g. a 2x2 brick has 8 connectible sides).
/// For performance, the evaluated value is a proportional approximation of the real value.
__global__ void internal::eval_num_connectible_sides_kernel(const Placement* placements, size_t num_placements, int* out_num_connectible_sides)
{
    // TODO this measure could be computed statically per Brick (type)

    int pi = get_placement_index();
    if (pi >= num_placements) return;

    __shared__ int connectible_sides[32];

    int wi = threadIdx.x >> 5; // Warp index
    if (ARP_IS_WARP_THREAD_0) connectible_sides[wi] = 0;
    __syncwarp();

    const Placement& placement = placements[pi];
    auto const& brick = k_bricks[placement.bid];
    iterate_brick_grid(
        [&](int bx, int by)
        {
            if (brick[by][bx])
            {
                int current_connectible_sides = 0;
                current_connectible_sides += bx - 1 < 0 ? 1 : !brick[by][bx - 1];
                current_connectible_sides += by - 1 < 0 ? 1 : !brick[by - 1][bx];
                current_connectible_sides += bx + 1 >= BRICK_MAX_EXTENT_X ? 1 : !brick[by][bx + 1];
                current_connectible_sides += by + 1 >= BRICK_MAX_EXTENT_Z ? 1 : !brick[by + 1][bx];
                atomicAdd_block(&connectible_sides[wi], current_connectible_sides);
            }
        }
    );
    if (ARP_IS_WARP_THREAD_0) out_num_connectible_sides[pi] = connectible_sides[wi];
}

__global__ void
internal::eval_color_map_coverage_kernel(const Placement* placements, size_t num_placements, ColorMapT* color_map, ColorMapCoverageResult* out_results)
{
    int pi = get_placement_index();
    if (pi >= num_placements) return;

    __shared__ int min_r[32], min_g[32], min_b[32];
    __shared__ int max_r[32], max_g[32], max_b[32];
    __shared__ int num_covered_cells[32];

    int wi = threadIdx.x >> 5; // Warp index
    if (ARP_IS_WARP_THREAD_0)
    {
        min_r[wi] = INT32_MAX, min_g[wi] = INT32_MAX, min_b[wi] = INT32_MAX;
        max_r[wi] = INT32_MIN, max_g[wi] = INT32_MIN, max_b[wi] = INT32_MIN;
        num_covered_cells[wi] = 0;
    }
    __syncwarp();

    const Placement& placement = placements[pi];
    auto const& brick = k_bricks[placement.bid];
    iterate_brick_grid(
        [&](int bx, int by)
        {
            if (brick[by][bx])
            {
                int mx = placement.x + bx;
                int my = placement.z + by;
                if (!color_map->is_valid_pixel(mx, my)) return; // Out of bounds

                glm::vec<4, uint8_t> v = color_map->read_pixel(mx, my);
                if (v.a > 0)
                {
                    atomicMin_block(&min_r[wi], v.r); // TODO use warp __reduce_min_sync? What's more performant?
                    atomicMin_block(&min_g[wi], v.g);
                    atomicMin_block(&min_b[wi], v.b);
                    atomicMax_block(&max_r[wi], v.r);
                    atomicMax_block(&max_g[wi], v.g);
                    atomicMax_block(&max_b[wi], v.b);
                    atomicAdd_block(&num_covered_cells[wi], 1);
                }
            }
        }
    );
    __syncwarp();

    int color_distance = -1;
    if (num_covered_cells[wi] > 0)
    {
        // clang-format off
        color_distance = abs(max_r[wi] - min_r[wi]) +
                         abs(max_g[wi] - min_g[wi]) +
                         abs(max_b[wi] - min_b[wi]);
        // clang-format on
        assert(color_distance <= ColorMapCoverageResult::k_max_color_distance);
    }

    if (ARP_IS_WARP_THREAD_0)
    {
        out_results[pi].color_distance = color_distance;
        out_results[pi].num_covered_cells = num_covered_cells[wi];
    }
}

/// Evaluate the number of neighboring sides every placement would have according to the current placement map. A high number of neighbors is usually better.
/// Can be normalized using the number of `connectible sides` (i.e. same scale).
__global__ void
internal::eval_num_neighbors_kernel(const Placement* placements, size_t num_placements, PlacementMapT* current_placement_map, int* out_num_neighbors)
{
    int pi = get_placement_index();
    if (pi >= num_placements) return;

    __shared__ int num_neighbors[32];

    int wi = threadIdx.x >> 5; // Warp index
    if (ARP_IS_WARP_THREAD_0) num_neighbors[wi] = 0;
    __syncwarp();

    const Placement& placement = placements[pi];
    iterate_brick_grid(
        [&](int bx, int by)
        {
            int mx = placement.x + bx;
            int my = placement.z + by;

            auto const& brick = k_bricks[placement.bid];
            if (brick[by][bx] && current_placement_map->is_valid_pixel(mx, my))
            {
                int current_num_neighbors = 0;

                bool has_left = bx - 1 < 0 || !brick[by][bx - 1];
                has_left = has_left && mx - 1 >= 0 &&
                           current_placement_map->read_pixel(mx - 1, my).x != ARP_NO_PLACEMENT_VALUE;
                current_num_neighbors += has_left;

                bool has_right = bx + 1 >= BRICK_MAX_EXTENT_X || !brick[by][bx + 1];
                has_right = has_right && mx + 1 < current_placement_map->m_width &&
                            current_placement_map->read_pixel(mx + 1, my).x != ARP_NO_PLACEMENT_VALUE;
                current_num_neighbors += has_right;

                bool has_bottom = by + 1 >= BRICK_MAX_EXTENT_Z || !brick[by + 1][bx];
                has_bottom = has_bottom && my + 1 < current_placement_map->m_height &&
                             current_placement_map->read_pixel(mx, my + 1).x != ARP_NO_PLACEMENT_VALUE;
                current_num_neighbors += has_bottom;

                bool has_top = by - 1 < 0 || !brick[by - 1][bx];
                has_top = has_top && my - 1 >= 0 &&
                          current_placement_map->read_pixel(mx, my - 1).x != ARP_NO_PLACEMENT_VALUE;
                current_num_neighbors += has_top;

                atomicAdd_block(&num_neighbors[wi], current_num_neighbors);
            }
        }
    );
    __syncwarp();

    if (ARP_IS_WARP_THREAD_0) out_num_neighbors[pi] = num_neighbors[wi];
}

/// Evaluate the number of underlying bricks every placement connects. A high number of connected bricks is usually better.
/// Can be normalized using the `brick size`.
__global__ void internal::eval_num_connected_bricks_kernel(
    const Placement* placements, size_t num_placements, PlacementMapT* previous_placement_map, int* out_num_connected_bricks
)
{
    // One thread per placement
    int pi = blockIdx.x * 1024 + threadIdx.x;
    if (pi >= num_placements) return;

    uint16_t unique_bid_list[BRICK_MAX_SIZE]; // List of unique underlying BIDs (128 bytes per thread)
    int unique_bid_list_length = 0;

    const Placement& placement = placements[pi];
    const auto& brick = k_bricks[placement.bid];
    for (int bx = 0; bx < BRICK_MAX_EXTENT_X; ++bx)
    {
        for (int by = 0; by < BRICK_MAX_EXTENT_Z; ++by)
        {
            if (brick[by][bx])
            {
                int mx = placement.x + bx;
                int my = placement.z + by;
                if (!previous_placement_map->is_valid_pixel(mx, my)) continue;

                uint16_t underlying_bid = previous_placement_map->read_pixel(mx, my).x;
                if (underlying_bid == ARP_NO_PLACEMENT_VALUE) continue; // No placement

                // Was the BID already added to the list? (non-unique)
                int i = 0;
                for (; i < unique_bid_list_length; ++i)
                {
                    if (unique_bid_list[i] == underlying_bid) break; // Already added
                }

                if (i == unique_bid_list_length) // Not added, add it!
                {
                    unique_bid_list[i] = underlying_bid;
                    ++unique_bid_list_length;
                }
            }
        }
    }

    out_num_connected_bricks[pi] = unique_bid_list_length;
}

__global__ void
internal::eval_highest_proximity_kernel(const Placement* placements, size_t num_placements, ProximityMapT* proximity_map, int* out_highest_proximity)
{
    int pi = get_placement_index();
    if (pi >= num_placements) return;

    __shared__ int highest_proximity[32];

    int wi = threadIdx.x >> 5; // Warp index
    if (ARP_IS_WARP_THREAD_0) highest_proximity[wi] = -1;
    __syncwarp();

    const Placement& placement = placements[pi];
    iterate_brick_grid(
        [&](int bx, int by)
        {
            int mx = placement.x + bx;
            int my = placement.z + by;
            if (proximity_map->is_valid_pixel(mx, my))
            {
                int proximity = proximity_map->read_pixel(mx, my).x;
                atomicMax_block(&highest_proximity[wi], proximity);
            }
        }
    );
    __syncwarp();

    out_highest_proximity[wi] = highest_proximity[wi];
}

/// Check whether the supplied placement is outside the slice, or overlapping a previous placement of the same slice.
__device__ bool is_outside_or_overlapping(const Placement& placement, const PlacementSolver::Input* input)
{
    __shared__ int result[32]; // Outside or overlapping

    int wi = threadIdx.x >> 5; // Warp index
    if (ARP_IS_WARP_THREAD_0) result[wi] = false;
    __syncwarp();

    const auto& brick = k_bricks[placement.bid];
    iterate_brick_grid(
        [&](int bx, int by)
        {
            if (brick[by][bx])
            {
                int mx = placement.x + bx;
                int my = placement.z + by;

                bool out_of_bounds = !input->color_map_d->is_valid_pixel(mx, my);
                bool overlapping = !out_of_bounds && input->current_placement_map_d->read_pixel(mx, my).x != ARP_NO_PLACEMENT_VALUE;
                if (out_of_bounds || overlapping) atomicOr_block(&result[wi], true);
            }
        }
    );
    __syncwarp();

    return result[wi];
}

/// Evaluate the reward function for the placement at index `pi`.
/// This device function expects a warp dedicated to every placement.
__device__ float eval_reward(const PlacementSolver* self, int pi, const PlacementSolver::Input* input)
{
    assert(pi < self->m_num_placements);
    const Placement& placement = self->m_placements_d[pi];

    bool outside_or_overlapping = is_outside_or_overlapping(placement, input);

    // Only what the first warp thread return is important for the caller
    if (!ARP_IS_WARP_THREAD_0) return -INFINITY;

    int brick_size = self->m_brick_size_d[pi];
    assert(brick_size > 0);
    int num_connectible_sides = self->m_num_connectible_sides_d[pi];
    internal::ColorMapCoverageResult& color_map_coverage = self->m_color_map_coverage_results_d[pi];
    int num_neighbors = self->m_num_neighbors_d[pi];
    int num_connected_bricks = self->m_num_connected_bricks_d[pi];
    int highest_proximity = self->m_highest_proximity_d[pi];

    /* Discard */
    bool discard = false;
    discard |= outside_or_overlapping;

    // The brick doesn't connect to any brick of the previous subslice; note: for the very first subslice (first call),
    // the previous placements map is expected to be filled with values >0!
    bool is_floating = num_connected_bricks == 0;
    if (input->is_subslice0)
    {
        // For the first subslice0, we have to consider that the model could be made of separated voxel clusters.
        // If a cluster is "far enough" (albeit the threshold), then accept the placement
        is_floating &= highest_proximity > 0 /* highest_proximity_threshold */;
    }
    discard |= is_floating;

    if (discard) return -INFINITY; // Very low reward (discarded)

    /* Evaluation */

    // an = number of neighboring bricks the placement has (normalized by number of connectible sides)
    // bn = brick size (normalized by maximum brick size)
    // cn = number of colored map cells covered by the placement (normalized by brick size)
    // dn = number of *different* bricks of the previous slice connected
    // hn = measure of the heterogeneity of colors covered by this placement (1 is color homogeneity)

    float an = float(num_neighbors) / float(num_connectible_sides);
    float bn = float(brick_size) / float(BRICK_MAX_EXTENT_X * BRICK_MAX_EXTENT_Z);
    float cn = float(color_map_coverage.num_covered_cells) / float(brick_size);
    float dn = float(num_connected_bricks) / float(brick_size);
    float hn = std::max(color_map_coverage.color_distance, 0);
    hn /= (float) internal::ColorMapCoverageResult::k_max_color_distance;
    hn = 1.0f - hn;

    // float pn = float(highest_proximity) / float(arpenteur.m_proximity_max_value);
    assert(an >= 0.f && an <= 1.f);
    assert(bn >= 0.f && bn <= 1.f);
    assert(cn >= 0.f && cn <= 1.f);
    assert(dn >= 0.f && dn <= 1.f);
    assert(hn >= 0.f && hn <= 1.f);

    // Connectivity factor [0.0, 1.0]
    if (!input->is_subslice0)
    {
        // For subslice >0, we want to stack up bricks. So we reverse the connectivity factor!
        dn = 1.0f - dn;
    }

    // If a placement doesn't cover any colored cell, it is only allowed to fill holes!
    if (color_map_coverage.num_covered_cells == 0 && num_neighbors != num_connectible_sides)
    {
        assert(num_neighbors < num_connectible_sides);
        return -INFINITY;
    }

    // Hole filling: the wider the hole, the better
    if (color_map_coverage.num_covered_cells == 0 && num_neighbors == num_connectible_sides) return bn;

    if (cn < 0.2f) return 0.f;

    float reward = bn * (an + dn + hn) + (.2f + cn * .8f);
    return reward;
}

__global__ void internal::eval_reward_kernel(const PlacementSolver* self, const PlacementSolver::Input* params, float* out_rewards)
{
    int pi = get_placement_index();
    if (pi >= self->m_num_placements) return;

    float reward = eval_reward(self, pi, params);
    if (ARP_IS_WARP_THREAD_0) out_rewards[pi] = reward;
}

PlacementSolver::PlacementSolver(size_t num_placements, int resolution) :
    m_num_placements(num_placements),
    m_resolution(resolution),
    m_num_blocks(div_ceil<int>(num_placements, 32))
{
    CHECK_CU(cudaMalloc(&m_placements_d, num_placements * sizeof(Placement)));
    CHECK_CU(cudaMalloc(&m_brick_size_d, num_placements * sizeof(int)));
    CHECK_CU(cudaMalloc(&m_num_connectible_sides_d, num_placements * sizeof(int)));
    CHECK_CU(cudaMalloc(&m_color_map_coverage_results_d, num_placements * sizeof(internal::ColorMapCoverageResult)));
    CHECK_CU(cudaMalloc(&m_num_neighbors_d, num_placements * sizeof(int)));
    CHECK_CU(cudaMalloc(&m_num_connected_bricks_d, num_placements * sizeof(int)));
    CHECK_CU(cudaMalloc(&m_highest_proximity_d, num_placements * sizeof(int)));
    CHECK_CU(cudaMalloc(&m_rewards_d, num_placements * sizeof(int)));

    internal::init_placements_kernel<<<div_ceil<int>(num_placements, 1024), 1024>>>(m_placements_d, num_placements, resolution);
    internal::eval_brick_size_kernel<<<m_num_blocks, 1024>>>(m_placements_d, num_placements, m_brick_size_d);
    internal::eval_num_connectible_sides_kernel<<<m_num_blocks, 1024>>>(m_placements_d, num_placements, m_num_connectible_sides_d);
    CHECK_CU(cudaDeviceSynchronize());
}

PlacementSolver::~PlacementSolver()
{
    CHECK_CU(cudaFree(&m_placements_d));
    CHECK_CU(cudaFree(&m_brick_size_d));
    CHECK_CU(cudaFree(&m_num_connectible_sides_d));
    CHECK_CU(cudaFree(&m_color_map_coverage_results_d));
    CHECK_CU(cudaFree(&m_num_neighbors_d));
    CHECK_CU(cudaFree(&m_num_connected_bricks_d));
    CHECK_CU(cudaFree(&m_highest_proximity_d));
    CHECK_CU(cudaFree(&m_rewards_d));
}

std::pair<Placement, float> PlacementSolver::solve(const Input& input)
{
    using namespace internal;

    PlacementSolver* self_d = to_device(*this);
    Input* params_d = to_device(input);

    /* Evaluate all rewards (parallel brute force) */
    // ARP_DEBUG("Evaluating rewards...");

    // clang-format off
    eval_color_map_coverage_kernel<<<m_num_blocks, 1024>>>(m_placements_d, m_num_placements, input.color_map_d, (internal::ColorMapCoverageResult*) m_color_map_coverage_results_d);
    eval_num_neighbors_kernel<<<m_num_blocks, 1024>>>(m_placements_d, m_num_placements, input.current_placement_map_d, m_num_neighbors_d);
    eval_num_connected_bricks_kernel<<<div_ceil<int>(m_num_placements, 1024), 1024>>>(m_placements_d, m_num_placements, input.previous_placement_map_d, m_num_connected_bricks_d);
    eval_highest_proximity_kernel<<<m_num_blocks, 1024>>>(m_placements_d, m_num_placements, input.proximity_map_d, m_highest_proximity_d);
    // clang-format on
    eval_reward_kernel<<<m_num_blocks, 1024>>>(self_d, params_d, m_rewards_d);
    CHECK_CU(cudaDeviceSynchronize());

    // ARP_DEBUG("Rewards evaluated");

    /* Find optimum */
    // ARP_DEBUG("Searching maximum reward...");

    float* max_reward_d = thrust::max_element(thrust::device, m_rewards_d, m_rewards_d + m_num_placements); // Fake IDE error on CLion :')
    size_t max_pi = max_reward_d - m_rewards_d;

    Placement placement = to_host(&m_placements_d[max_pi]);
    float reward = to_host(max_reward_d);

    ARP_DEBUG("Best placement found; PID: %5d, BID: %2d, X: %3d, Y: %3d, Reward: %.3f", max_pi, placement.bid, placement.x, placement.z, reward);

    return {placement, reward};
}
