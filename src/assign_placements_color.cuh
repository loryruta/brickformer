#pragma once

#include <cstdio>
#include <cuda.h>
#include <cuda_runtime.h>

#include "Converter.h"
#include "brick_colors.hpp"
#include "bricks.hpp"
#include "types.cuh"
#include "PlacementSolver.h"

// TODO put in some general utility file
#define ARP_ARRAY_SIZE(_array) (sizeof(_array) / sizeof(_array[0]))

namespace lego_builder
{
__device__ glm::vec3 rgb_to_xyz(const glm::vec3& rgb)
{
    // Code from:
    // http://www.easyrgb.com/en/math.php
    // sR, sG and sB (Standard RGB) input range = 0 - 255
    // X, Y and Z output refer to a D65/2° standard illuminant.
    float var_R = rgb.r / 255.0f;
    float var_G = rgb.g / 255.0f;
    float var_B = rgb.b / 255.0f;
    var_R = var_R > 0.04045 ? powf((var_R + 0.055f) / 1.055f, 2.4f) : var_R / 12.92;
    var_G = var_G > 0.04045 ? powf((var_G + 0.055) / 1.055, 2.4f) : var_G / 12.92;
    var_B = var_B > 0.04045 ? powf((var_B + 0.055) / 1.055, 2.4) : var_B / 12.92;
    var_R = var_R * 100;
    var_G = var_G * 100;
    var_B = var_B * 100;
    glm::vec3 out_xyz;
    out_xyz.x = var_R * 0.4124 + var_G * 0.3576 + var_B * 0.1805;
    out_xyz.y = var_R * 0.2126 + var_G * 0.7152 + var_B * 0.0722;
    out_xyz.z = var_R * 0.0193 + var_G * 0.1192 + var_B * 0.9505;
    return out_xyz;
}

__device__ glm::vec3 xyz_to_lab(const glm::vec3& xyz)
{
    // Code from:
    // http://www.easyrgb.com/en/math.php
    // D65 illuminant
    const float ref_x = 95.047f;
    const float ref_y = 100.000f;
    const float ref_z = 108.883f;
    float var_X = xyz.x / ref_x;
    float var_Y = xyz.y / ref_y;
    float var_Z = xyz.z / ref_z;
    var_X = var_X > 0.008856f ? pow(var_X, 0.333333333f) : (7.787 * var_X) + 0.13793103f;
    var_Y = var_Y > 0.008856f ? pow(var_Y, 0.333333333f) : (7.787 * var_Y) + 0.13793103f;
    var_Z = var_Z > 0.008856f ? pow(var_Z, 0.333333333f) : (7.787 * var_Z) + 0.13793103f;
    glm::vec3 out_cielab;
    out_cielab[0] = (116 * var_Y) - 16;
    out_cielab[1] = 500 * (var_X - var_Y);
    out_cielab[2] = 200 * (var_Y - var_Z);
    return out_cielab;
}

__device__ int search_nearest_brick_color(const glm::vec3& q)
{
    // Computing color difference:
    // https://stackoverflow.com/a/67294772/7358682
    int min_cid = -1;
    float min_dist = INFINITY;
    for (int i = 0; i < ARP_ARRAY_SIZE(k_brick_colors); ++i) {
        glm::vec3 b = k_brick_colors[i].color();
        // Compute color difference in CIELAB color space (closer to human perception)
        // TODO cache CIELAB color conversions!
        glm::vec3 q_lab = xyz_to_lab(rgb_to_xyz(q));
        glm::vec3 b_lab = xyz_to_lab(rgb_to_xyz(b));
        glm::vec3 diff = q_lab - b_lab;
        float dist_sq = glm::dot(diff, diff);
        if (dist_sq < min_dist) {
            min_cid = i;
            min_dist = dist_sq;
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
    for (int cid = lane_idx * 3; cid < (lane_idx + 1) * 3; ++cid) {
        histogram[wi][cid] = 0;
    }
    __syncwarp();

    auto& brick = k_bricks[placement.bid];
    iterate_brick_grid([&](int bx, int bz) {
        if (brick[bz][bx]) {
            int mx = placement.x + bx;
            int mz = placement.z + bz;
            glm::vec<4, uint8_t> color = color_map->read_pixel(mx, mz);
            // Consider the color only if a valid rasterized voxel
            if (color.a == UINT8_MAX) {
                int cid = search_nearest_brick_color(glm::vec3(color));
                atomicAdd_block(&histogram[wi][cid], 1);
            }
        }
    });
    __syncwarp();

    if (lane_idx == 0) { // Only first thread of each warp
        int max_cid = -1;
        int max_val = INT32_MIN;
        for (int cid = 0; cid < ARP_ARRAY_SIZE(histogram[wi]); ++cid) {
            if (histogram[wi][cid] > max_val) {
                max_cid = cid;
                max_val = histogram[wi][cid];
            }
        }

        // There must be at least one non-zero histogram bucket because a placement is considered valid
        // if 30% of its cells are colored (see reward function definition)
        assert(max_cid >= 0);
        placement.cid = uint8_t(max_cid); // Assign CID
    }
}

__global__ void assign_placements_color_kernel(Converter* converter, Placement* placements, size_t num_placements)
{
    int pi = (blockIdx.x << 5) + (threadIdx.x >> 5); // One warp per placement
    if (pi >= num_placements) return;

    assign_placement_color(*converter, placements[pi]);
}
} // namespace lego_builder
