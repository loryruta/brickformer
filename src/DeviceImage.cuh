#pragma once

#include <cstdint>

#include <glm/glm.hpp>

#include "util/misc.cuh"

namespace lego_builder
{

template <uint32_t FORMAT, typename DATA_TYPE>
class DeviceImage;

template <uint32_t SRC_IMAGE_FORMAT,
          typename SRC_IMAGE_TYPE,
          uint32_t DST_IMAGE_FORMAT,
          typename DST_IMAGE_TYPE,
          typename TRANSFORM_FUNC>
__global__ void transform_image_kernel(const DeviceImage<SRC_IMAGE_FORMAT, SRC_IMAGE_TYPE>* src_image,
                                       DeviceImage<DST_IMAGE_FORMAT, DST_IMAGE_TYPE>* dst_image,
                                       TRANSFORM_FUNC transform_func);

/// Represents an image allocated on device.
/// Pixels are organized in a row-first manner and (0, 0) is the top-left pixel.
template <uint32_t FORMAT, typename DATA_TYPE>
class DeviceImage
{
public:
    using PixelT = glm::vec<FORMAT, DATA_TYPE>;
    static_assert(sizeof(PixelT) == sizeof(DATA_TYPE) * FORMAT); // No unexpected padding please :/

public: // TODO make private ?
    uint32_t m_width, m_height;
    /// A device buffer for the image pixels.
    PixelT* m_data; // TODO rename to m_data_d
    bool owned = false;

public:
    DeviceImage() = default; // Should be private, but it's not to ease lazy initialization
    /// Create a non-owning copy of the image.
    DeviceImage(const DeviceImage& other)
        : m_width(other.m_width), m_height(other.m_height), m_data(other.m_data), owned(false)
    {
    }
    /// Move the image, possibly transferring ownership.
    DeviceImage(DeviceImage&& other) noexcept
        : m_width(other.m_width), m_height(other.m_height), m_data(other.m_data), owned(other.owned)
    {
        other.m_data = nullptr;
        other.owned = false;
    }
    ~DeviceImage()
    {
#ifndef __CUDA_ARCH__
        if (m_data && owned) {
            CHECK_CU(cudaFree(m_data));
            m_data = nullptr;
        }
#endif
    }

    [[nodiscard]] uint32_t width() const { return m_width; }
    [[nodiscard]] uint32_t height() const { return m_height; }
    [[nodiscard]] size_t pixel_size() const { return sizeof(PixelT); }
    [[nodiscard]] size_t data_size() const { return m_width * m_height * sizeof(PixelT); };

    __host__ __device__ bool is_valid_pixel(int x, int y) const
    {
        return x >= 0 && x < m_width && y >= 0 && y < m_height;
    }

    __device__ PixelT read_pixel(int x, int y) const
    {
        assert(x >= 0 && x < m_width);
        assert(y >= 0 && y < m_height);
        return m_data[y * m_height + x];
    }

    __host__ void write_region(
        uint32_t dst_x, uint32_t dst_y, uint32_t src_w, uint32_t src_h, const PixelT* src_data, cudaStream_t stream)
    {
        CHECK_STATE(dst_x + src_w <= m_width);
        CHECK_STATE(dst_y + src_h <= m_height);
        CHECK_STATE(src_data);
        for (uint32_t y = 0; y < src_h; y++) {
            PixelT* dst_row = &m_data[dst_y * m_width + dst_x];
            const PixelT* src_row = &src_data[y * src_w];
            CHECK_CU(cudaMemcpyAsync(dst_row, src_row, src_w * sizeof(PixelT), cudaMemcpyHostToDevice, stream));
        }
    }

    __device__ void write_pixel(int x, int y, const PixelT& value) { m_data[y * m_width + x] = value; }

    __host__ void write_pixel(int x, int y, const PixelT& value, cudaStream_t stream)
    {
        write_region(x, y, 1, 1, &value, stream);
    }

    /// Transform every pixel of the current image into a pixel of some other format (using the supplied device
    /// function). Finally writes the result in the destination image.
    template <uint32_t DST_IMAGE_FORMAT, typename DST_IMAGE_TYPE, typename TRANSFORM_FUNC>
    void transform_to(const DeviceImage<DST_IMAGE_FORMAT, DST_IMAGE_TYPE>& dst_image,
                      TRANSFORM_FUNC transform_func,
                      cudaStream_t stream)
    {
        assert(m_width == dst_image.m_width && m_height == dst_image.m_height);

        DeviceImage<FORMAT, DATA_TYPE>* src_image_d = to_device(*this, stream);
        DeviceImage<DST_IMAGE_FORMAT, DST_IMAGE_TYPE>* dst_image_d = to_device(dst_image, stream);

        dim3 num_blocks{};
        num_blocks.x = div_ceil<uint32_t>(m_width, 32);
        num_blocks.y = div_ceil<uint32_t>(m_height, 32);
        num_blocks.z = 1;
        dim3 block_dim(32, 32, 1);
        transform_image_kernel<<<num_blocks, block_dim, 0, stream>>>(src_image_d, dst_image_d, transform_func);

        CHECK_CU(cudaFreeAsync(src_image_d, stream));
        CHECK_CU(cudaFreeAsync(dst_image_d, stream));
    }

    /// Fills image data with the supplied int value.
    __host__ void fill(int value, cudaStream_t stream)
    {
        CHECK_CU(cudaMemsetAsync(m_data, value, m_width * m_height * sizeof(PixelT), stream));
    }

    __host__ void copy_from(const DeviceImage& other, cudaStream_t stream)
    {
        assert(m_width == other.m_width && m_height == other.m_height);
        CHECK_CU(cudaMemcpyAsync(
            m_data, other.m_data, m_width * m_height * sizeof(PixelT), cudaMemcpyDeviceToDevice, stream));
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
    static DeviceImage create(uint32_t width, uint32_t height, const uint8_t* data, cudaStream_t stream)
    {
        DeviceImage<FORMAT, DATA_TYPE> image{};
        image.m_width = width;
        image.m_height = height;
        CHECK_CU(cudaMallocAsync(&image.m_data, image.data_size(), stream));
        image.owned = true;
        if (data) {
            CHECK_CU(cudaMemcpyAsync(image.m_data, data, image.data_size(), cudaMemcpyHostToDevice, stream));
        }
        return image;
    }
};

template <uint32_t SRC_IMAGE_FORMAT,
          typename SRC_IMAGE_TYPE,
          uint32_t DST_IMAGE_FORMAT,
          typename DST_IMAGE_TYPE,
          typename TRANSFORM_FUNC>
__global__ void transform_image_kernel(const DeviceImage<SRC_IMAGE_FORMAT, SRC_IMAGE_TYPE>* src_image,
                                       DeviceImage<DST_IMAGE_FORMAT, DST_IMAGE_TYPE>* dst_image,
                                       TRANSFORM_FUNC transform_func)
{
    size_t x = blockIdx.x * blockDim.x + threadIdx.x;
    size_t y = blockIdx.y * blockDim.y + threadIdx.y;

    if (x < src_image->m_width && y < src_image->m_height) {
        auto old_val = src_image->read_pixel(x, y);
        auto new_val = transform_func(old_val);
        dst_image->write_pixel(x, y, new_val);
    }
}

} // namespace lego_builder
