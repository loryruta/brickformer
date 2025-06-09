#pragma once

#include "Converter.h"
#include "bricks.hpp"
#include "primitives.cuh"
#include "types.cuh"

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

    int num_items_x = div_ceil(BRICK_MAX_EXTENT_X, 5);   // 2
    int num_items_y = div_ceil(BRICK_MAX_EXTENT_Z, 5);  // 2

    for (int ix = 0; ix < num_items_x; ix++)
    {
        for (int iy = 0; iy < num_items_y; iy++)
        {
            int bx = lane_x * num_items_x + ix;
            int by = lane_y * num_items_y + iy;

            if (bx < BRICK_MAX_EXTENT_X && by < BRICK_MAX_EXTENT_Z) callback(bx, by);
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
    auto& brick = k_bricks[placement.bid];

    int mx = placement.x + bx;
    int my = placement.z + by;

    if (mx + 1 < placement_map->m_width && (bx + 1 >= BRICK_MAX_EXTENT_X || !brick[by][bx + 1]))
    {
        if (placement_map->read_pixel(mx + 1, my).x > 0) ++inout_num_neighbors; // TODO: bug: increment atomically
        ++inout_num_connectible_sides;
    }

    if (my + 1 < placement_map->m_height && (by + 1 >= BRICK_MAX_EXTENT_Z || !brick[by + 1][bx]))
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
inline bool eval_placement(const Converter& converter, Placement& placement, float& out_reward)
{
    auto& brick = k_bricks[placement.bid];

    int warp_i = threadIdx.x >> 5;

    ColorMapT* color_map_d = converter.m_color_map_d;
    ProximityMapT* prev_proximity_map_d = converter.m_prev_proximity_map_d;
    PlacementMapT* prev_placements_d = converter.m_prev_placements_d;
    PlacementMapT* cur_placements_d = converter.m_cur_placements_d;

    // The placement reward depends on:
    // - the number of colored cells covered of the current subslice
    // - the number of adjacent placements
    // - the size of the brick
    // - if subslice0, the mismatching to previous slice placements covered
    // - if not subslice0, the similarity to previous slice placements covered (we want to stack them)
    bool is_outside = false;
    bool is_overlapping = false;
    int num_covered_map_cells = 0;   // The number of cells of the color map covered by the placement
    int brick_size = 0;              // The number of set cells of the brick's grid
    int num_neighbors = 0;           // A number *proportional* to the number of bricks adjacent to the placement (likely >=)
    int num_connectible_sides = 0;   // A number *proportional* to the number of connectible sides
    int num_connected_bricks = 0;    // A number *proportional* to the number of different connected bricks in the previous subslice
    int last_prev_bid = 0;
    int highest_proximity = 0;
    glm::vec<4, uint8_t> min_color{UINT8_MAX};
    glm::vec<4, uint8_t> max_color{};

    iterate_brick_grid([&](int32_t bx, int32_t by)
    {
        int mx = placement.x + bx;
        int my = placement.z + by;

        if (brick[by][bx])
        {
           // Placement out of bounds
           is_outside |= mx >= color_map_d->m_width || my >= color_map_d->m_height;

           // Placement would overlap a previous placement on the current layer
           is_overlapping |= cur_placements_d->read_pixel(mx, my).x != 0;

           glm::vec<4, uint8_t> color = color_map_d->read_pixel(mx, my);

           min_color = glm::min(color, min_color);
           max_color = glm::max(color, max_color);
           if (color.a > 0) ++num_covered_map_cells;  // Count the number of colored cells covered

           // Count the size of the brick (number of cells set in brick's grid)
           ++brick_size;

           // Inspect the neighborhood to get:
           // - the number of adjacent bricks in the current layer
           // - whether this brick is covering a hole (all neighbors are set)
           inspect_neighborhood(placement, bx, by, cur_placements_d, num_neighbors, num_connectible_sides);

           // Take the previous slice, and check the BID. If different from *the last* (heuristic to optimize), then
           // we count it as a newly connected brick
           uint16_t prev_bid = prev_placements_d->read_pixel(mx, my).x;
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

        min_color.r = glm::min<uint8_t>(min_color.r, __shfl_down_sync(FULL_MASK, min_color.r, offset));
        min_color.g = glm::min<uint8_t>(min_color.g, __shfl_down_sync(FULL_MASK, min_color.g, offset));
        min_color.b = glm::min<uint8_t>(min_color.b, __shfl_down_sync(FULL_MASK, min_color.b, offset));

        max_color.r = glm::max<uint8_t>(max_color.r, __shfl_down_sync(FULL_MASK, max_color.r, offset));
        max_color.g = glm::max<uint8_t>(max_color.g, __shfl_down_sync(FULL_MASK, max_color.g, offset));
        max_color.b = glm::max<uint8_t>(max_color.b, __shfl_down_sync(FULL_MASK, max_color.b, offset));

        highest_proximity = glm::max(highest_proximity, __shfl_down_sync(FULL_MASK, highest_proximity, offset));
    }

    // After reduction, only the first thread of the warp holds the aggregated values:
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
        is_floating &= highest_proximity > converter.m_proximity_threshold;
    }
    discard |= is_floating;

    if (discard) return false; // Invalid!

    // Evaluate the reward: how good is this placement?

    float an = float(num_neighbors) / float(num_connectible_sides);
    float bn = float(brick_size) / float(BRICK_MAX_EXTENT_X * BRICK_MAX_EXTENT_Z);
    float cn = float(num_covered_map_cells) / float(brick_size);
    float dn = float(num_connected_bricks) / float(brick_size);
    float pn = float(highest_proximity) / float(converter.m_proximity_max_value);

    static constexpr float max_color_diff = 260100.0f;  // 255^2 + 255^2 + 255^2 + 255^2
    glm::vec4 minmax_color_diff = max_color - min_color;

    // Color homogeneity factor [0.0, 1.0] (0.0 -> low, 1.0 -> high)
    float ch = glm::dot(minmax_color_diff, minmax_color_diff) / max_color_diff;
    ch = 1.0f - ch;
    ch = ch * ch * ch;

//    float a = 0.8f * an * an * an;  // Adjacency factor [0.0, 0.8]
//    float c = 0.8f * cn * ch;

    // Connectivity factor [0.0, 1.0]
    if constexpr (!IS_SUBSLICE0)
    {
        // For subslice >0, we want to stack up bricks. So we reverse the connectivity factor!
        dn = 1.0f - dn;
    }

    // TODO OLD out_reward = glm::max(cn * a, c) + 0.2f * (cn * bn);  // TODO dn

    if (num_covered_map_cells == 0) {
        if (num_neighbors == num_connectible_sides) {
            // If this placement doesn't cover the color map, it is only allowed to fill holes!
            out_reward = bn;
        } else {
            out_reward = 0.f;
        }
    } else {
        out_reward = bn * (an + dn + ch) + (.2f + cn * .8f);
    }

    return true;
}
}  // namespace lego_builder
