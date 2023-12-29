#pragma once

#include <cstdint>

#include <glm/glm.hpp>

#include "misc.cuh"

namespace lego_builder
{
/// Represents an image allocated on device.
/// Pixels are organized in a row-first manner and (0, 0) is the top-left pixel.
template<uint32_t FORMAT, typename DATA_TYPE>
class DeviceImage
{
    using PixelT = glm::vec<FORMAT, DATA_TYPE>;
    static_assert(sizeof(PixelT) == sizeof(DATA_TYPE) * FORMAT);  // No unexpected padding please :/

public:  // TODO make private ?
    uint32_t m_width, m_height;

    /// A device buffer for the image pixels.
    PixelT* m_data;  // TODO rename to m_data_d

public:
    DeviceImage() = default;  // Should be private, but it's not to ease lazy initialization
    DeviceImage(const DeviceImage&) = delete;
    DeviceImage(DeviceImage&& other) noexcept :
        m_width(other.m_width),
        m_height(other.m_height),
        m_data(other.m_data)
    {
        m_data = nullptr;
    }

    ~DeviceImage()
    {
        if (m_data)
        {
            CHECK_CU(cudaFree(m_data));
            m_data = nullptr;
        }
    }

    [[nodiscard]] uint32_t width() const { return m_width; }
    [[nodiscard]] uint32_t height() const { return m_height; }

    [[nodiscard]] size_t pixel_size() const { return sizeof(PixelT); }

    [[nodiscard]] size_t data_size() const { return m_width * m_height * sizeof(PixelT); };

    __host__ __device__
    bool is_valid_pixel(int x, int y) const
    {
        return x >= 0 && x < m_width &&
            y >= 0 && y < m_height;
    }

    __device__
    PixelT read_pixel(uint32_t x, uint32_t y) const
    {
        return m_data[y * m_height + x];
    }

    __host__
    void write_region(uint32_t dst_x, uint32_t dst_y, uint32_t src_w, uint32_t src_h, const PixelT* src_data)
    {
        CHECK_STATE(dst_x + src_w <= m_width);
        CHECK_STATE(dst_y + src_h <= m_height);
        CHECK_STATE(src_data);

        for (uint32_t y = 0; y < src_h; y++)
        {
            PixelT* dst_row = &m_data[dst_y * m_width + dst_x];
            const PixelT* src_row = &src_data[y * src_w];
            CHECK_CU(cudaMemcpy(dst_row, src_row, src_w * sizeof(PixelT), cudaMemcpyHostToDevice));
        }
    }

    __host__ __device__
    void write_pixel(uint32_t x, uint32_t y, const PixelT& value)
    {
#ifdef __CUDA_ARCH__
        m_data[y * m_width + x] = value;
#else
        write_region(x, y, 1, 1, &value);
#endif
    }

    /// Fills image data with the supplied int value.
    __host__
    void fill(int value)
    {
        CHECK_CU(cudaMemset(m_data, value, m_width * m_height * sizeof(PixelT)));
        CHECK_CU(cudaDeviceSynchronize());  // cudaMemset is async with respect to the host (according to docs)
    }

    __host__
    void copy_from(const DeviceImage& other)
    {
        assert(m_width == other.m_width && m_height == other.m_height);

        CHECK_CU(cudaMemcpy(m_data, other.m_data, m_width * m_height * sizeof(PixelT), cudaMemcpyDeviceToDevice));
        CHECK_CU(cudaDeviceSynchronize());
    }

    void operator=(const DeviceImage&) = delete;

    DeviceImage& operator=(DeviceImage&& other) noexcept
    {
        m_width = other.m_width;
        m_height = other.m_height;
        m_data = other.m_data;

        other.m_data = nullptr;

        return *this;
    }

    /// Creates a host-local struct (still allocating its data on device).
    static DeviceImage create(uint32_t width, uint32_t height, const uint8_t* data = nullptr)
    {
        DeviceImage<FORMAT, DATA_TYPE> image{};
        image.m_width = width;
        image.m_height = height;
        CHECK_CU(cudaMalloc(&image.m_data, image.data_size()));

        if (data) CHECK_CU(cudaMemcpy(image.m_data, data, image.data_size(), cudaMemcpyHostToDevice));

        return image;
    }
};

}  // namespace lego_builder
