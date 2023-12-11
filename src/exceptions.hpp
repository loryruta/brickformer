#pragma once

#include <cstdio>

#define CHECK_STATE(condition) \
    lego_builder::check_state(condition, #condition, __FILE__, __LINE__, nullptr)

#define CHECK_STATE_MSG(condition, message) \
    lego_builder::check_state(condition, #condition, __FILE__, __LINE__, message)

#define CHECK_CU(error) \
    lego_builder::check_cuda((error), __FILE__, __LINE__)

namespace lego_builder
{
    inline void check_state(
            bool condition,
            char const* check_str,
            char const* file,
            int line,
            char const* message
            )
    {
        if (!condition) // TODO Mark as unlikely path
        {
            fprintf(stderr, "Invalid state: %s (file: %s, line: %d)", check_str, file, line);
            if (message) fprintf(stderr, "; %s", message);
            fprintf(stderr, "\n");
            exit(1);
        }
    }

    inline void check_cuda(cudaError_t error, const char* file, int line)
    {
        if (error != cudaSuccess) // TODO Mark as unlikely path
        {
            fprintf(stderr, "CUDA error: %s %s %d\n", cudaGetErrorString(error), file, line);
            exit(error);
        }
    }
}
