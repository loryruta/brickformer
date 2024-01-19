#pragma once

#include <cstdint>

#define BRICK_MAX_WIDTH  8 // Must be a power of 2
#define BRICK_MAX_HEIGHT 8 // TODO "HEIGHT"? IT'S NOT AN HEIGHT!
#define BRICK_MAX_SIZE   (BRICK_MAX_WIDTH * BRICK_MAX_HEIGHT)

#ifndef __CUDACC__
#   define __constant__
#endif

namespace lego_builder
{
    using BlockLayoutT = uint8_t[BRICK_MAX_HEIGHT][BRICK_MAX_WIDTH];

    // clang-format off
    __constant__
    const BlockLayoutT k_bricks[] = {
            // 1x1
            {{1}},

            // 1x2
            {{1, 1}},

            // 2x1
            {{1},
             {1}},

            // 2x2 corner
            {{0, 1},
             {1, 1}},

            {{0, 1},
             {1, 1}},

            {{1, 1},
             {0, 1}},

            {{1, 1},
             {1, 0}},

            // 2x2
            {{1, 1},
             {1, 1}},

            // 3x1
            {{1},
             {1},
             {1}},

            // 1x3
            {{1, 1, 1}},

            // 2x3
            {{1, 1, 1},
             {1, 1, 1}},

            // 3x2
            {{1, 1},
             {1, 1},
             {1, 1}},

            // 1x4
            {{1, 1, 1, 1}},

            // 4x1
            {{1},
             {1},
             {1},
             {1}},

            // 2x4
            {{1, 1, 1, 1},
             {1, 1, 1, 1}},

            // 4x2
            {{1, 1},
             {1, 1},
             {1, 1},
             {1, 1}},

            // 4x4
            {{1,1,1,1},
             {1,1,1,1},
             {1,1,1,1},
             {1,1,1,1}},

            // 6x1
            {{1},
             {1},
             {1},
             {1},
             {1},
             {1}},

            // 1x6
            {{1,1,1,1,1,1}},

            // 6x2
            {{1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1}},

            // 2x6
            {{1,1,1,1,1,1},
             {1,1,1,1,1,1}},

            // 8x2
            {{1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1},
             {1,1}},

            // 2x8
            {{1,1,1,1,1,1,1,1},
             {1,1,1,1,1,1,1,1}},
    };
    // clang-format on

    __constant__
    const size_t k_num_bricks = sizeof(k_bricks) / sizeof(k_bricks[0]);
}

