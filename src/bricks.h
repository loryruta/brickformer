#pragma once

#include <cstdint>

#define BRICK_MAX_EXTENT_X 8 // Must be a power of 2
#define BRICK_MAX_EXTENT_Z 8 // TODO "HEIGHT"? IT'S NOT AN HEIGHT!
#define BRICK_MAX_SIZE (BRICK_MAX_EXTENT_X * BRICK_MAX_EXTENT_Z)

#ifndef __CUDACC__
#define __constant__
#endif

namespace bf
{
using BlockLayoutT = uint8_t[BRICK_MAX_EXTENT_Z][BRICK_MAX_EXTENT_X];

// clang-format off
    __constant__
    const BlockLayoutT k_bricks[] = {
            // 0: 1x1
            {{1}},

            // 1: 1x2
            {{1, 1}},

            // 2: 2x1
            {{1},
             {1}},

            // 3: 2x2 corner
            {{0, 1},
             {1, 1}},

            // 4
            {{1, 0},
             {1, 1}},

            // 5
            {{1, 1},
             {0, 1}},

            // 6
            {{1, 1},
             {1, 0}},

            // 7: 2x2
            {{1, 1},
             {1, 1}},

            // 8: 3x1
            {{1},
             {1},
             {1}},

            // 9: 1x3
            {{1, 1, 1}},

            // 10: 2x3
            {{1, 1, 1},
             {1, 1, 1}},

            // 11: 3x2
            {{1, 1},
             {1, 1},
             {1, 1}},

            // 12: 1x4
            {{1, 1, 1, 1}},

            // 13: 4x1
            {{1},
             {1},
             {1},
             {1}},

            // 14: 2x4
            {{1, 1, 1, 1},
             {1, 1, 1, 1}},

            // 15: 4x2
            {{1, 1},
             {1, 1},
             {1, 1},
             {1, 1}},

            // 16: 6x1
            {{1},
             {1},
             {1},
             {1},
             {1},
             {1}},

            // 17: 1x6
            {{1,1,1,1,1,1}},

            // 18: 6x2
            {{1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1}},

            // 19: 2x6
            {{1,1,1,1,1,1},
             {1,1,1,1,1,1}},

            // 20: 8x2
            {{1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1}},

            // 21: 2x8
            {{1,1,1,1,1,1,1,1},
             {1,1,1,1,1,1,1,1}},
    };
// clang-format on

/// List of BrickLink IDs of the bricks.
const uint32_t k_brick_design_ids[] = {
    3005, // 1x1
    3004, // 1x2
    3004, // 1x2
    2357, // 2x2 corner
    2357, // 2x2 corner
    2357, // 2x2 corner
    2357, // 2x2 corner
    3003, // 2x2
    3622, // 1x3
    3622, // 1x3
    3002, // 2x3
    3002, // 2x3
    3010, // 1x4
    3010, // 1x4
    3001, // 2x4
    3001, // 2x4
    3009, // 1x6
    3009, // 1x6
    44237, // 2x6
    44237, // 2x6
    3007, // 2x8
    3007, // 2x8
};

static_assert(std::size(k_bricks) == std::size(k_brick_design_ids),
              "k_bricks and k_brick_design_ids must have the same length");

__constant__ const std::size_t k_num_bricks = sizeof(k_bricks) / sizeof(k_bricks[0]);
} // namespace bf
