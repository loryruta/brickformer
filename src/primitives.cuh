#pragma once

#include <cstdint>
#include <cub/cub.cuh>

#define FULL_MASK 0xffffffff

namespace lego_builder
{
    template<typename T>
    struct Max
    {
        __host__ __device__ T operator()(const T& a, const T& b) const { return a > b ? a : b; }
    };

    template<typename T>
    struct Min
    {
        __host__ __device__ T operator()(const T& a, const T& b) const { return a < b ? a : b; }
    };

    template<typename T>
    struct Add
    {
        __host__ __device__ T operator()(const T& a, const T& b) const { return a + b; }
    };

    template<typename T, typename OPERATION>
    __device__ T warp_reduce(T val)
    {
        static const OPERATION op; // TODO better constraint between T and OPERATION

        // Reference:
        // https://developer.nvidia.com/blog/using-cuda-warp-level-primitives/

        for (int off = 16; off > 0; off /= 2)
        {
            T other_val = __shfl_down_sync(FULL_MASK, val, off);
            val = op(other_val, val);
        }
        return val;
    }

    template<typename T>
    __device__ T warp_min(T value) { return warp_reduce<T, Min<T>>(value); }

    template<typename T>
    __device__ T warp_max(T value) { return warp_reduce<T, Max<T>>(value); }

    template<typename T>
    __device__ T warp_add(T value) { return warp_reduce<T, Add<T>>(value); }
}
