#pragma once

#include "types.hpp"
#include "bricks.cuh"
#include "primitives.cuh"
#include "Arpenteur.cuh"

namespace lego_builder
{

/// Iterates the brick grid within the warp and callbacks every occurrence.
/// Important: don't perform warp operations within the callback.
template<typename CALLBACK>
__device__
inline void iterate_brick_grid(CALLBACK callback)
{
    uint32_t lane_i = cub::LaneId();  // TODO threadIdx.x & 0x1F ?
    uint32_t lane_x = lane_i % 5;
    uint32_t lane_y = lane_i / 5;

    if (lane_y >= 5) return;

    const uint32_t k_item_w = div_ceil(BRICK_MAX_WIDTH, 5);
    const uint32_t k_item_h = div_ceil(BRICK_MAX_HEIGHT, 5);

    for (uint32_t item_x = 0; item_x < k_item_w; item_x++)
    {
        for (uint32_t item_y = 0; item_y < k_item_h; item_y++)
        {
            uint32_t bx = lane_x * k_item_w + item_x;
            uint32_t by = lane_y * k_item_h + item_y;

            if (bx < BRICK_MAX_WIDTH && by < BRICK_MAX_HEIGHT) callback(bx, by);
        }
    }
}

__device__
inline void inspect_neighborhood(
    const Placement& placement,
    int32_t bx,
    int32_t by,
    const PlacementMapT* placement_map,
    size_t& num_neighbors,
    size_t& num_connectible_sides
)
{
    auto& brick = k_bricks[placement.m_bid];

    int32_t mx = placement.m_x + bx;
    int32_t my = placement.m_y + by;

    if (mx + 1 < placement_map->m_width && (bx + 1 >= BRICK_MAX_WIDTH || !brick[bx + 1][by]))
    {
        if (placement_map->read_pixel(mx + 1, my).x > 0) ++num_neighbors;
        ++num_connectible_sides;
    }

    if (my + 1 < placement_map->m_width && (by + 1 >= BRICK_MAX_HEIGHT || !brick[bx][by + 1]))
    {
        if (placement_map->read_pixel(mx, my + 1).x > 0) ++num_neighbors;
        ++num_connectible_sides;
    }

    if (mx - 1 >= 0 && (bx - 1 < 0 || !brick[bx - 1][by]))
    {
        if (placement_map->read_pixel(mx - 1, my).x > 0) ++num_neighbors;
        ++num_connectible_sides;
    }

    if (my - 1 >= 0 && (by - 1 < 0 || !brick[bx][by - 1]))
    {
        if (placement_map->read_pixel(mx, my - 1).x > 0) ++num_neighbors;
        ++num_connectible_sides;
    }
}

template<bool IS_SUBSLICE0>
__device__
inline float eval_placement(const Arpenteur& arpenteur, Placement& placement)
{
    auto& brick = k_bricks[placement.m_bid];

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
    size_t num_covered_map_cells = 0;   // The number of cells of the underlying color_map being covered by the placement
    size_t brick_size = 0;              // The number of set cells of the brick's grid
    size_t num_neighbors = 0;           // A number *proportional* to the number of bricks adjacent to the placement (likely >=)
    size_t num_connectible_sides = 0;   // A number *proportional* to the number of connectible sides
    size_t num_connected_bricks = 0;    // A number *proportional* to the number of bricks connected in the previous subslice
    uint32_t last_prev_bid = 0;
    uint8_t highest_proximity = 0.0f;

    iterate_brick_grid([&](int32_t bx, int32_t by)
    {
        uint32_t mx = placement.m_x + bx;
        uint32_t my = placement.m_y + by;

        if (brick[bx][by])
        {
           // Placement out of bounds
           is_outside |= mx >= color_map_d->m_width && my >= color_map_d->m_height;

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
           if (last_prev_bid != prev_bid)
           {
               ++num_connected_bricks;
               last_prev_bid = prev_bid;
           }

           highest_proximity = glm::max(highest_proximity, prev_proximity_map_d->read_pixel(mx, my).x);
        }
    });

    // Important: if the warp's thread didn't cover any grid's cell (i.e. callback wasn't invoked).
    // The score must be zero!

    bool discard = is_outside || is_overlapping;
    discard = __any_sync(FULL_MASK, discard);

    // Warp reduce (loops are unrolled)
    num_covered_map_cells = warp_add(num_covered_map_cells);
    brick_size = warp_add(brick_size);
    num_neighbors = warp_add(num_neighbors);
    num_connectible_sides = warp_add(num_connectible_sides);
    num_connected_bricks = warp_add(num_connected_bricks);
    highest_proximity = warp_max(highest_proximity);

    bool is_floating = num_connected_bricks == 0;
    if constexpr (IS_SUBSLICE0)
    {
        // For the first subslice0, we have to consider that the model could be made of separated voxel clusters. If a
        // cluster is "far enough" (albeit the threshold), then accept the placement
        is_floating &= highest_proximity > arpenteur.m_proximity_threshold;
    }
    discard |= is_floating;

    float an = float(num_neighbors) / float(num_connectible_sides);
    float bn = float(brick_size) / float(BRICK_MAX_WIDTH * BRICK_MAX_HEIGHT);
    float cn = float(num_covered_map_cells) / float(brick_size);
    float dn = float(num_connected_bricks) / float(brick_size);
    float pn = float(highest_proximity) / float(PROXIMITY_MAP_HIGH_VALUE);

    float reward = 0.0f; // How good is this placement?
    if (!discard)
    {
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

        reward = glm::max(a, c) * ((b + d + p) / 3.0f);
    }
    return reward;
}
}  // namespace lego_builder
