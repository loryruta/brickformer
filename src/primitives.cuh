#pragma once

#include <cstdint>

#include "util/misc.cuh"

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

    /// Perform a reduction within a warp. We expect all threads to run this function.
    /// @return the reduced value for the current lane. The aggregated value is held by the lane 0
    template<typename T, typename OPERATION>
    __device__ T warp_reduce(T val)
    {
        static const OPERATION op; // TODO better constraint between T and OPERATION

        assert(__activemask() == FULL_MASK);

        // Reference:
        // https://developer.nvidia.com/blog/using-cuda-warp-level-primitives/

#pragma unroll
        for (int offset = 16; offset > 0; offset /= 2)
        {
            T other_val = __shfl_down_sync(FULL_MASK, val, offset);
            val = op(other_val, val);
        }
    }

    template<typename T>
    __device__ T warp_min(T value) { return warp_reduce<T, Min<T>>(value); }

    template<typename T>
    __device__ T warp_max(T value) { return warp_reduce<T, Max<T>>(value); }

    template<typename T>
    __device__ T warp_add(T value) { return warp_reduce<T, Add<T>>(value); }
}
