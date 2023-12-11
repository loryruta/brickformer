#pragma once

#include <cstdint>

namespace lego_builder
{
    using BlockLayoutT = uint8_t[16][16];

    // clang-format off
    __constant__ const BlockLayoutT k_bricks[] = {
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
    };
    // clang-format on

    __constant__ const size_t k_num_bricks = sizeof(k_bricks) / sizeof(k_bricks[0]);
}

