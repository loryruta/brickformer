#include "AssignPlacementColor.h"

#include "bricks.h"
#include "lego_dataset.h"

using namespace bf;

namespace
{
__host__ __device__ glm::vec3 rgb_to_xyz(const glm::vec3& rgb)
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

__host__ __device__ glm::vec3 xyz_to_lab(const glm::vec3& xyz)
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
    var_X = var_X > 0.008856f ? powf(var_X, 0.333333333f) : (7.787 * var_X) + 0.13793103f;
    var_Y = var_Y > 0.008856f ? powf(var_Y, 0.333333333f) : (7.787 * var_Y) + 0.13793103f;
    var_Z = var_Z > 0.008856f ? powf(var_Z, 0.333333333f) : (7.787 * var_Z) + 0.13793103f;
    glm::vec3 out_cielab;
    out_cielab[0] = (116 * var_Y) - 16;
    out_cielab[1] = 500 * (var_X - var_Y);
    out_cielab[2] = 200 * (var_Y - var_Z);
    return out_cielab;
}

__global__ void assign_placements_cid_kernel(ColorMapT color_map,
                                             Placement* placements,
                                             uint32_t num_placements,
                                             const bool* color_masks)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= num_placements) return;
    Placement& placement = placements[i];

    glm::vec3 query_color(0.0f);
    int num_colors = 0;
    auto& brick = k_bricks[placement.bid];
    for (int bz = 0; bz < BRICK_MAX_EXTENT_Z; ++bz) {
        for (int bx = 0; bx < BRICK_MAX_EXTENT_X; ++bx) {
            if (brick[bz][bx]) {
                int x = placement.x + bx;
                int z = placement.z + bz;
                glm::vec<4, uint8_t> color = color_map.read_pixel(x, z);
                if (color.a == UINT8_MAX) {
                    query_color += glm::vec3(color);
                    ++num_colors;
                }
            }
        }
    }
    if (num_colors == 0) {
        // If the placement isn't overlapping any color of the color map, assign it to the color closer to BLACK.
        query_color = glm::vec3(0);
    } else {
        query_color /= float(num_colors);
    }

    const bool* color_mask = &color_masks[placement.bid * k_num_brick_colors];
    int cid = AssignPlacementColor::search_nearest_cid(query_color, color_mask);
    placement.cid = cid;
}
} // namespace

/// Provided with a query color, and a mask indicating valid colors (e.g. allowed by plan or available for the brick),
/// find the color that is closest to the query color.
/// \param query_color Query color to find closest CID of (values in [0, 255])
/// \param color_mask  A color mask to use to unavailable colors (length is color cardinality)
__host__ __device__ int AssignPlacementColor::search_nearest_cid(const glm::vec3& query_color, const bool* color_mask)
{
    // Computing color difference:
    // https://stackoverflow.com/a/67294772/7358682
    int min_cid = -1;
    float min_dist_sq = INFINITY;
    for (uint32_t cid = 0; cid < k_num_brick_colors; ++cid) {
        if (!color_mask || color_mask[cid]) {
            glm::vec3 b = k_brick_colors_rgb_d[cid];
            // Compute color difference in CIELAB color space (closer to human perception)
            // TODO cache CIELAB color conversions!
            glm::vec3 q_lab = xyz_to_lab(rgb_to_xyz(query_color));
            glm::vec3 b_lab = xyz_to_lab(rgb_to_xyz(b));
            glm::vec3 diff = q_lab - b_lab;
            float dist_sq = glm::dot(diff, diff);
            if (dist_sq < min_dist_sq) {
                min_cid = cid;
                min_dist_sq = dist_sq;
            }
        }
    }
    // If min_cid is negative, it means no color is enabled in color_mask which is an invalid state!
    assert(min_cid >= 0);
    return min_cid;
}

void AssignPlacementColor::assign(const ColorMapT& color_map,
                                  Placement* placements,
                                  size_t num_placements,
                                  const bool* color_masks)
{
    dim3 num_blocks = div_ceil<uint32_t>(num_placements, 256);
    dim3 block_dims = 256;
    assign_placements_cid_kernel<<<num_blocks, block_dims>>>(color_map, placements, num_placements, color_masks);
}
