#pragma once

#include <cstdio>

#include "glm/glm.hpp"

#include "util/misc.h"

#define CHECK_CU(error) bf::check_cuda((error), __FILE__, __LINE__)

#define FULL_MASK UINT32_MAX

namespace bf
{
inline void check_cuda(cudaError_t error, const char* file, int line)
{
    if (error != cudaSuccess) // TODO Mark as unlikely path
    {
        fprintf(stderr,
                "CUDA error: %s (%s) (file: %s, line: %d)\n",
                cudaGetErrorName(error),
                cudaGetErrorString(error),
                file,
                line);
        exit(error);
    }
}

template <typename T>
T* to_device(const T* elements, size_t num_elements, cudaStream_t stream)
{
    T* d_elements;
    CHECK_CU(cudaMallocAsync(&d_elements, num_elements * sizeof(T), stream));
    CHECK_CU(cudaMemcpyAsync(d_elements, elements, num_elements * sizeof(T), cudaMemcpyHostToDevice, stream));
    return d_elements;
}

/// Transfers the given host object to device.
template <typename T>
T* to_device(const T& element, cudaStream_t stream)
{
    return to_device(&element, 1, stream);
}

template <typename T>
void to_host(const T* d_elements, size_t num_elements, T* out_elements, cudaStream_t stream)
{
    CHECK_CU(cudaMemcpyAsync(out_elements, d_elements, num_elements * sizeof(T), cudaMemcpyDeviceToHost, stream));
    CHECK_CU(cudaStreamSynchronize(stream));
}

/// Transfers the given device object to host and returns it.
template <typename T>
T to_host(const T* d_element, cudaStream_t stream)
{
    T element{};
    CHECK_CU(cudaMemcpyAsync(&element, d_element, sizeof(T), cudaMemcpyDeviceToHost, stream));
    CHECK_CU(cudaStreamSynchronize(stream));
    return element;
}

template <typename T>
void dump_device_buffer(const T* d_elements, size_t num_elements)
{
    T* elements = (T*) malloc(num_elements * sizeof(T));
    CHECK_STATE(elements);
    to_host(d_elements, num_elements, elements);

    printf("{");
    for (size_t i = 0; i < num_elements; i++) {
        printf("[%zu]: %s, ", i, to_string(elements[i]).c_str());
    }
    printf("}\n");
}

template <typename IntegerT>
__host__ __device__ constexpr IntegerT div_ceil(IntegerT n, IntegerT d)
{
    // Source:
    // https://stackoverflow.com/questions/17944/how-to-round-up-the-result-of-integer-division

    return (n + d - 1) / d;
}

__host__ __device__ inline glm::vec4 to_fvec4(const uchar4& v) { return {v.x, v.y, v.z, v.w}; }

__host__ __device__ inline glm::vec4 to_fvec4(const uint4& v) { return {v.x, v.y, v.z, v.w}; }

__host__ __device__ inline glm::vec4 to_fvec4(const float4& v) { return {v.x, v.y, v.z, v.w}; }

__host__ __device__ inline int pmod(int i, int n) { return (i % n + n) % n; }
} // namespace bf
