#pragma once

#include "Arpenteur.cuh"
#include "bricks.cuh"
#include "primitives.cuh"
#include "types.hpp"

namespace lego_builder
{

/// Iterates the brick grid within the warp and callbacks every occurrence.
/// Important: don't perform warp operations within the callback.
template<typename CALLBACK>
__device__
inline void iterate_brick_grid(CALLBACK callback)
{
    int lane_i = threadIdx.x & 0x1f;
    int lane_x = lane_i % 5;
    int lane_y = lane_i / 5;

    int num_items_x = div_ceil(BRICK_MAX_WIDTH, 5);   // 2
    int num_items_y = div_ceil(BRICK_MAX_HEIGHT, 5);  // 2

    for (int ix = 0; ix < num_items_x; ix++)
    {
        for (int iy = 0; iy < num_items_y; iy++)
        {
            int bx = lane_x * num_items_x + ix;
            int by = lane_y * num_items_y + iy;

            if (bx < BRICK_MAX_WIDTH && by < BRICK_MAX_HEIGHT) callback(bx, by);
        }
    }
}

__device__
inline void inspect_neighborhood(
    const Placement& placement,
    int bx, int by,
    const PlacementMapT* placement_map,
    int& inout_num_neighbors,
    int& inout_num_connectible_sides
    )
{
    auto& brick = k_bricks[placement.m_bid];

    int32_t mx = placement.m_x + bx;
    int32_t my = placement.m_y + by;

    if (mx + 1 < placement_map->m_width && (bx + 1 >= BRICK_MAX_WIDTH || !brick[by][bx + 1]))
    {
        if (placement_map->read_pixel(mx + 1, my).x > 0) ++inout_num_neighbors;
        ++inout_num_connectible_sides;
    }

    if (my + 1 < placement_map->m_width && (by + 1 >= BRICK_MAX_HEIGHT || !brick[by + 1][bx]))
    {
        if (placement_map->read_pixel(mx, my + 1).x > 0) ++inout_num_neighbors;
        ++inout_num_connectible_sides;
    }

    if (mx - 1 >= 0 && (bx - 1 < 0 || !brick[by][bx - 1]))
    {
        if (placement_map->read_pixel(mx - 1, my).x > 0) ++inout_num_neighbors;
        ++inout_num_connectible_sides;
    }

    if (my - 1 >= 0 && (by - 1 < 0 || !brick[by - 1][bx]))
    {
        if (placement_map->read_pixel(mx, my - 1).x > 0) ++inout_num_neighbors;
        ++inout_num_connectible_sides;
    }
}

template<bool IS_SUBSLICE0>
__device__
inline bool eval_placement(const Arpenteur& arpenteur, Placement& placement, float& out_reward)
{
    uint32_t warp_i = blockIdx.x * 32 + (threadIdx.x >> 5);

    auto& brick = k_bricks[placement.m_bid];

    const bool should_print = warp_i == 10938;
    //should_print = (blockIdx.x == 10123 || blockIdx.x == 3648 || blockIdx.x == 1182 || blockIdx.x == 1 || blockIdx.x == 68939) && threadIdx.x == 0;
    //should_print = placement.m_x == 134 && placement.m_y == 255 && placement.m_bid == 14;

    ColorMapT* color_map_d = arpenteur.m_color_map_d;
    ProximityMapT* prev_proximity_map_d = arpenteur.m_prev_proximity_map_d;
    PlacementMapT* prev_placements_d = arpenteur.m_prev_placements_d;
    PlacementMapT* cur_placements_d = arpenteur.m_cur_placements_d;

    // The placement reward depends on:
    // - the number of colored cells covered of the current subslice
    // - the number of adjacent placements
    // - the size of the brick
    // - if subslice0, the mismatching to previous slice placements covered
    // - if not subslice0, the similarity to previous slice placements covered (we want to stack them)
    bool is_outside = false;
    bool is_overlapping = false;
    int num_covered_map_cells = 0;   // The number of cells of the underlying color_map being covered by the placement
    int brick_size = 0;              // The number of set cells of the brick's grid
    int num_neighbors = 0;           // A number *proportional* to the number of bricks adjacent to the placement (likely >=)
    int num_connectible_sides = 0;   // A number *proportional* to the number of connectible sides
    int num_connected_bricks = 0;    // A number *proportional* to the number of bricks connected in the previous subslice
    int last_prev_bid = 0;
    int highest_proximity = 0;

    iterate_brick_grid([&](int32_t bx, int32_t by)
    {
        int mx = placement.m_x + bx;
        int my = placement.m_y + by;

        if (brick[by][bx])
        {
//            if (should_print) printf("%d : bx: %d, by: %d, mx: %d, my: %d, colormap w: %d, colormap h: %d\n",
//                       blockIdx.x, bx, by, mx, my, color_map_d->m_width, color_map_d->m_height);

           // Placement out of bounds
           is_outside |= mx >= color_map_d->m_width || my >= color_map_d->m_height;

           // Placement would overlap a previous placement on the current layer
           is_overlapping |= cur_placements_d->read_pixel(mx, my).x != 0;

           // Count the number of colored cells covered
           num_covered_map_cells += color_map_d->read_pixel(mx, my).a > 0;

           // Count the size of the brick (number of cells set in brick's grid)
           ++brick_size;

           // Inspect the neighborhood to get:
           // - the number of adjacent bricks in the current layer
           // - whether this brick is covering a hole (all neighbors are set)
           inspect_neighborhood(placement, bx, by, cur_placements_d, num_neighbors, num_connectible_sides);

           // Take the previous slice, and check the BID. If different from *the last* (heuristic to optimize), then
           // we count it as a newly connected brick
           uint16_t prev_bid = prev_placements_d->read_pixel(mx, my).x;
           //if (should_print) printf("%d : prev_bid: %d\n", blockIdx.x, prev_bid);
           if (last_prev_bid != prev_bid)
           {
               ++num_connected_bricks;
               last_prev_bid = prev_bid;
           }

           int proximity_val = prev_proximity_map_d->read_pixel(mx, my).x;
           highest_proximity = glm::max(highest_proximity, proximity_val);
        }
    });

    // WARP REDUCTION
    bool is_outside_or_overlapping = __any_sync(FULL_MASK, is_outside || is_overlapping);

    for (int offset = 16; offset > 0; offset /= 2)
    {
        num_covered_map_cells += __shfl_down_sync(FULL_MASK, num_covered_map_cells, offset);
        brick_size += __shfl_down_sync(FULL_MASK, brick_size, offset);
        num_neighbors += __shfl_down_sync(FULL_MASK, num_neighbors, offset);
        num_connectible_sides += __shfl_down_sync(FULL_MASK, num_connectible_sides, offset);
        num_connected_bricks += __shfl_down_sync(FULL_MASK, num_connected_bricks, offset);
        highest_proximity = glm::max(highest_proximity, __shfl_down_sync(FULL_MASK, highest_proximity, offset));
    }

    // After reduction, only the first thread holds the aggregated values:
    // it's the only one able to compute validity/reward!
    if ((threadIdx.x & 0x1f) != 0) return false;

    // ONLY THREAD 0 IS VALID FROM NOW ON

    bool discard = false;
    discard |= brick_size == 0;  // Empty brick
    discard |= is_outside_or_overlapping;

    // The brick doesn't connect to any brick of the previous subslice; note: for the very first subslice (first call),
    // the previous placements map is expected to be filled with values >0!
    bool is_floating = num_connected_bricks == 0;
    if constexpr (IS_SUBSLICE0)
    {
        // For the first subslice0, we have to consider that the model could be made of separated voxel clusters. If a
        // cluster is "far enough" (albeit the threshold), then accept the placement
        is_floating &= highest_proximity > arpenteur.m_proximity_threshold;
    }
    discard |= is_floating;

//    if (should_print)
//    {
//        printf("AFTER REDUCTION - WARP IDX: %d , THREAD IDX: %d, (%d, %d) -> BID: %d, Brick size: %d, Num neighbors: %d, "
//               "Num connectible sides: %d, Num connected bricks: %d, Highest proximity: %d, Outside OR overlapping: %d, "
//               "Floating: %d, Discard: %d\n",
//               warp_i, threadIdx.x, placement.m_x, placement.m_y, placement.m_bid, brick_size,
//               num_neighbors, num_connectible_sides, num_connected_bricks, highest_proximity, is_outside_or_overlapping,
//               is_floating, discard
//               );
//    }

    if (discard) return false; // Invalid!

    // Evaluate the reward: how good is this placement?

    float an = float(num_neighbors) / float(num_connectible_sides);
    float bn = float(brick_size) / float(BRICK_MAX_WIDTH * BRICK_MAX_HEIGHT);
    float cn = float(num_covered_map_cells) / float(brick_size);
    float dn = float(num_connected_bricks) / float(brick_size);
    float pn = float(highest_proximity) / float(PROXIMITY_MAP_HIGH_VALUE);

    //if (should_print) printf("%d : an: %.3f, bn: %.3f, cn: %.3f, dn: %.3f, pn: %.3f\n", blockIdx.x,an,bn,cn,dn,pn);

    float a = an * an * an;                  // Adjacency factor [0.0, 1.0]
    float b = bn;                            // Block size factor [0.0, 1.0]
    float c = 0.7f * (cn * cn * cn) + 0.1f;  // Color factor [0.1, 0.8]

    float d = dn;  // Connectivity factor [0.0, 1.0]
    if constexpr (!IS_SUBSLICE0)
    {
        // For subslice >0, we want to stack up bricks. So we reverse the connectivity factor!
        d = 1.0f - dn;
    }

    // Proximity factor [0.0, 1.0]
    // Reward the more the brick is near to the model!
    float p = pn;

    out_reward = glm::max(a, c) * ((b + d + p) / 3.0f);

    return true;
}
}  // namespace lego_builder
