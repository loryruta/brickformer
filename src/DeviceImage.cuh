#pragma once

#include <cstdint>

#include <glm/glm.hpp>

#include "misc.cuh"

namespace lego_builder
{
/// Represents an image allocated on device.
/// Pixels are organized in a row-first manner and (0, 0) is the top-left pixel.
template<uint32_t FORMAT, typename DATA_TYPE>
struct DeviceImage
{
    using PixelT = glm::vec<FORMAT, DATA_TYPE>;
    static_assert(sizeof(PixelT) == sizeof(DATA_TYPE) * FORMAT);  // No unexpected padding please :/

    uint32_t m_width, m_height;

    // TODO Use a better memory layout to store a 2D array?
    PixelT* m_data; ///< A device buffer for the image pixels.

public:
    [[nodiscard]] size_t pixel_size() const { return sizeof(PixelT); }

    [[nodiscard]] size_t data_size() const { return m_width * m_height * sizeof(PixelT); };

    __device__ PixelT read_pixel(uint32_t x, uint32_t y) const
    {
        return m_data[y * m_height + x];
    }

    __host__ void write_region(
            uint32_t dst_x, uint32_t dst_y,
            uint32_t src_w, uint32_t src_h,
            const PixelT* src_data
            )
    {
        DeviceImage<FORMAT, DATA_TYPE> host_copy = to_host(this);
        CHECK_STATE(dst_x + src_w < host_copy.m_width);
        CHECK_STATE(dst_y + src_h < host_copy.m_height);
        CHECK_STATE(src_data);

        for (uint32_t y = 0; y < src_h; y++)
        {
            PixelT* dst_row = &host_copy.m_data[dst_y * host_copy.m_width + dst_x];
            const PixelT* src_row = &src_data[y * src_w];
            CHECK_CU(cudaMemcpy(dst_row, src_row, src_w * sizeof(PixelT), cudaMemcpyHostToDevice));
        }
    }

    __host__ __device__ void write_pixel(uint32_t x, uint32_t y, const PixelT& value)
    {
#ifdef __CUDA_ARCH__
        m_data[y * m_width + x] = value;
#else
        write_region(x, y, 1, 1, &value);
#endif
    }

    /// Fills image data with the supplied int value.
    __host__ void fill(int value)
    {
        DeviceImage<FORMAT, DATA_TYPE> host_image = to_host(this);
        CHECK_CU(cudaMemset(host_image.m_data, value, host_image.data_size()));
    }

    /// Creates a host-local struct (still allocating its data on device).
    static DeviceImage<FORMAT, DATA_TYPE> create(uint32_t width, uint32_t height, const uint8_t* data)
    {
        DeviceImage<FORMAT, DATA_TYPE> image{};
        image.m_width = width;
        image.m_height = height;
        image.m_data = nullptr;

        CHECK_CU(cudaMalloc(&image.m_data, image.data_size()));
        if (data) CHECK_CU(cudaMemcpy(image.m_data, data, image.data_size(), cudaMemcpyHostToDevice));
        return image;
    }

    /// Creates a device-local image having (if non-null) the given data.
    static DeviceImage<FORMAT, DATA_TYPE>* create_device_ptr(uint32_t width, uint32_t height, const uint8_t* data)
    {
        DeviceImage<FORMAT, DATA_TYPE> init_struct = create(width, height, data);  // Just used for initialization

        DeviceImage<FORMAT, DATA_TYPE>* image;
        CHECK_CU(cudaMalloc(&image, sizeof(DeviceImage<FORMAT, DATA_TYPE>)));
        CHECK_CU(cudaMemcpy(image, &init_struct, sizeof(init_struct), cudaMemcpyHostToDevice));
        return image;
    }
};

using ColorMapT = DeviceImage<4, uint8_t>;
using PlacementMapT = DeviceImage<1, uint16_t>;

}  // namespace lego_builder
