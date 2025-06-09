#pragma once

#include <cstdio>
#include <cuda.h>
#include <cuda_runtime.h>

#include "Converter.h"
#include "brick_colors.hpp"
#include "bricks.hpp"
#include "reward_func.cuh"
#include "types.cuh"

// TODO put in some general utility file
#define ARP_ARRAY_SIZE(_array) (sizeof(_array) / sizeof(_array[0]))

namespace lego_builder
{
__device__ int search_nearest_brick_color(const glm::vec<4, uint8_t>& color)
{
    int min_cid = -1;
    int min_dist = INT32_MAX;
    for (int i = 0; i < ARP_ARRAY_SIZE(k_brick_colors); ++i)
    {
        using Colori32 = glm::vec<4, int>;
        Colori32 diff{};
        diff = Colori32(color) - Colori32(k_brick_colors[i].color_u8());
        diff *= diff;
        int d = diff.r + diff.g + diff.b;
        if (d < min_dist)
        {
            min_cid = i;
            min_dist = d;
        }
    }
    assert(min_cid >= 0);
    return min_cid;
}

/// Computes the placement color as the average of the colors being covered.
__device__ void assign_placement_color(Converter& converter, Placement& placement)
{
    int pi = (blockIdx.x << 5) + (threadIdx.x >> 5); // One warp per placement
    int wi = threadIdx.x >> 5;
    int lane_idx = threadIdx.x & 0x1f;

    ColorMapT* color_map = converter.m_color_map_d;

    __shared__ int histogram[32 /* warp */][96]; // 12KB
    static_assert(ARP_ARRAY_SIZE(k_brick_colors) <= ARP_ARRAY_SIZE(histogram[wi]));

    // Zero-initialize the histogram
    for (int cid = lane_idx * 3; cid < (lane_idx + 1) * 3; ++cid)
    {
        histogram[wi][cid] = 0;
    }
    __syncwarp();

    auto& brick = k_bricks[placement.m_bid];
    iterate_brick_grid(
        [&](int bx, int by)
        {
            if (brick[by][bx])
            {
                int mx = placement.m_x + bx;
                int my = placement.m_y + by;
                glm::vec<4, uint8_t> color = color_map->read_pixel(mx, my);
                if (color.a == UINT8_MAX) // Consider the color only if a valid rasterized voxel
                {
                    int cid = search_nearest_brick_color(color);
                    atomicAdd_block(&histogram[wi][cid], 1);
                }
            }
        }
    );
    __syncwarp();

    // Keep alive only the first thread of the warp
    if (lane_idx != 0) return;

    int max_cid = -1;
    int max_val = INT32_MIN;
    for (int cid = 0; cid < ARP_ARRAY_SIZE(histogram[wi]); ++cid)
    {
        if (histogram[wi][cid] > max_val)
        {
            max_cid = cid;
            max_val = histogram[wi][cid];
        }
    }

    // There must be at least one non-zero histogram bucket because a placement is considered valid
    // if 30% of its cells are colored (see reward function definition)
    assert(max_cid >= 0);
    placement.m_cid = uint8_t(max_cid); // Assign CID
}

__global__ void assign_placements_color_kernel(Converter* converter, Placement* placements, size_t num_placements)
{
    int pi = (blockIdx.x << 5) + (threadIdx.x >> 5); // One warp per placement
    if (pi >= num_placements) return;

    assign_placement_color(*converter, placements[pi]);
}
} // namespace lego_builder
