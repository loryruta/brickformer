#pragma once

#include <cstdint>

#define BRICK_MAX_EXTENT_X 8 // Must be a power of 2
#define BRICK_MAX_EXTENT_Z 8 // TODO "HEIGHT"? IT'S NOT AN HEIGHT!
#define BRICK_MAX_SIZE (BRICK_MAX_EXTENT_X * BRICK_MAX_EXTENT_Z)

#ifndef __CUDACC__
#define __constant__
#endif

namespace lego_builder
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

            // 16: 4x4
            {{1,1,1,1},
             {1,1,1,1},
             {1,1,1,1},
             {1,1,1,1}},

            // 17: 6x1
            {{1},
             {1},
             {1},
             {1},
             {1},
             {1}},

            // 18: 1x6
            {{1,1,1,1,1,1}},

            // 19: 6x2
            {{1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1}},

            // 20: 2x6
            {{1,1,1,1,1,1},
             {1,1,1,1,1,1}},

            // 21: 8x2
            {{1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1}},

            // 22: 2x8
            {{1,1,1,1,1,1,1,1},
             {1,1,1,1,1,1,1,1}},
    };
// clang-format on

__constant__ const size_t k_num_bricks = sizeof(k_bricks) / sizeof(k_bricks[0]);
} // namespace lego_builder
