#pragma once

#include <cstdio>
#include <chrono>

#include <glm/glm.hpp>

#define CHECK_STATE(condition) \
    lego_builder::check_state(condition, #condition, __FILE__, __LINE__, nullptr)

#define CHECK_STATE_MSG(condition, message) \
    lego_builder::check_state(condition, #condition, __FILE__, __LINE__, message)

#define CHECK_CU(error) \
    lego_builder::check_cuda((error), __FILE__, __LINE__)

#define FULL_MASK UINT32_MAX

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
            fprintf(stderr, "CUDA error: %s (%s) (file: %s, line: %d)\n", cudaGetErrorName(error), cudaGetErrorString(error), file, line);
            exit(error);
        }
    }

    template<typename T>
    std::string to_string(const T& element)  // TODO Move it in a more generic file (this is cuda-specific)
    {
        return std::to_string(element);
    }

    template<typename T>
    T* to_device(const T* elements, size_t num_elements)
    {
        T* d_elements;
        CHECK_CU(cudaMalloc(&d_elements, num_elements * sizeof(T)));
        CHECK_CU(cudaMemcpy(d_elements, elements, num_elements * sizeof(T), cudaMemcpyHostToDevice));
        return d_elements;
    }

    /// Transfers the given host object to device.
    template<typename T>
    T* to_device(const T& element)
    {
        return to_device(&element, 1);
    }

    template<typename T>
    void to_host(const T* d_elements, size_t num_elements, T* out_elements)
    {
        CHECK_CU(cudaMemcpy(out_elements, d_elements, num_elements * sizeof(T), cudaMemcpyDeviceToHost));
    }

    /// Transfers the given device object to host and returns it.
    template<typename T>
    T to_host(const T* d_element)
    {
        T element{};
        CHECK_CU(cudaMemcpy(&element, d_element, sizeof(T), cudaMemcpyDeviceToHost));
        return element;
    }

    template<typename T>
    void dump_device_buffer(const T* d_elements, size_t num_elements)
    {
        T* elements = (T*) malloc(num_elements * sizeof(T));
        CHECK_STATE(elements);
        to_host(d_elements, num_elements, elements);

        printf("{");
        for (size_t i = 0; i < num_elements; i++)
        {
            printf("[%zu]: %s, ", i, to_string(elements[i]).c_str());
        }
        printf("}\n");
    }

    template<typename IntegerT>
    __host__ __device__
    constexpr IntegerT div_round_up(IntegerT n, IntegerT d)
    {
        // Source:
        // https://stackoverflow.com/questions/17944/how-to-round-up-the-result-of-integer-division

        return (n + d - 1) / d;
    }

    inline uint64_t current_ms_since_epoch()
    {
        using namespace std::chrono;
        return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
    }

    __host__ __device__
    inline glm::vec4 to_fvec4(const uchar4& v) { return {v.x, v.y, v.z, v.w}; }

    __host__ __device__
    inline glm::vec4 to_fvec4(const uint4& v) { return {v.x, v.y, v.z, v.w}; }

    __host__ __device__
    inline glm::vec4 to_fvec4(const float4& v) { return {v.x, v.y, v.z, v.w}; }
}
