#pragma once

#include "Arpenteur.cuh"
#include "bricks.hpp"
#include "reward_func.cuh"
#include "types.cuh"

namespace lego_builder
{
/// Computes the placement color as the average of the colors being covered.
__device__
glm::vec<4, uint8_t> compute_placement_color(Arpenteur& arpenteur, const Placement& placement)
{
    ColorMapT* color_map = arpenteur.m_color_map_d;

    glm::vec<4, float> color_sum{};
    int num_colored_cells = 0;

    auto& brick = k_bricks[placement.m_bid];
    iterate_brick_grid([&](int bx, int bz)
    {
        int mx = placement.m_x + bx;
        int mz = placement.m_y + bz;

        if (brick[bz][bx])
        {
            glm::vec<4, uint8_t> v = color_map->read_pixel(mx, mz);
            if (v.a > 0)
            {
                color_sum += v;
                ++num_colored_cells;
            }
        }
    });

    // Reduction
    for (int offset = 16; offset > 0; offset >>= 1)
    {
        color_sum.r += __shfl_down_sync(FULL_MASK, color_sum.r, offset);
        color_sum.g += __shfl_down_sync(FULL_MASK, color_sum.g, offset);
        color_sum.b += __shfl_down_sync(FULL_MASK, color_sum.b, offset);
        num_colored_cells += __shfl_down_sync(FULL_MASK, num_colored_cells, offset);
    }

    //
    glm::vec<4, uint8_t> result{color_sum / (float) num_colored_cells};
    result.a = num_colored_cells > 0 ? 255 : 0;
    return result;
}

__global__
void compute_placements_color_kernel(
        Arpenteur* arpenteur,
        ColoredPlacement* colored_placements,
        size_t num_colored_placements
        )
{
    int warp_i = blockIdx.x * 32 + (threadIdx.x >> 5);

    if (warp_i < num_colored_placements)
    {
        const Placement& placement = colored_placements[warp_i].m_placement;

        glm::vec<4, uint8_t> color = compute_placement_color(*arpenteur, placement);
        if ((threadIdx.x & 0x1F) == 0) colored_placements[warp_i].m_color = color;
    }
}

}