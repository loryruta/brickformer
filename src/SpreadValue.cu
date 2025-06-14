#include "SpreadValue.h"

#include <glm/ext/scalar_constants.hpp>

#include "primitives.cuh"

using namespace lego_builder;

__global__ void spread_kernel(SpreadValue::DeviceImageT src_image, SpreadValue::DeviceImageT dst_image)
{
    assert(src_image.m_width == dst_image.m_width && src_image.m_height == dst_image.m_height);
    int px = blockIdx.x * 32 + threadIdx.x;
    int py = blockIdx.y * 32 + threadIdx.y;
    if (px >= src_image.m_width || py >= src_image.m_height) {
        return; // Outside the image, discard the warp
    }

    uint8_t max_neighbor_val = 0;
    if (px > 0) { // Left neighbor
        max_neighbor_val = glm::max(max_neighbor_val, src_image.read_pixel(px - 1, py).x);
    }
    if (py > 0) { // Bottom neighbor
        max_neighbor_val = glm::max(max_neighbor_val, src_image.read_pixel(px, py - 1).x);
    }
    if (px < src_image.m_width - 1) { // Right neighbor
        max_neighbor_val = glm::max(max_neighbor_val, src_image.read_pixel(px + 1, py).x);
    }
    if (py < src_image.m_height - 1) { // Top neighbor
        max_neighbor_val = glm::max(max_neighbor_val, src_image.read_pixel(px, py + 1).x);
    }
    uint8_t cur_val = src_image.read_pixel(px, py).x;
    if (cur_val < max_neighbor_val) {
        dst_image.write_pixel(px, py, glm::vec<1, uint8_t>(max_neighbor_val - 1));
    } else {
        dst_image.write_pixel(px, py, glm::vec<1, uint8_t>(cur_val));
    }
}

void SpreadValue::spread(DeviceImageT& image, int num_iterations, cudaStream_t stream)
{
    DeviceImageT tmp_image = DeviceImageT::create(image.m_width, image.m_height, nullptr, stream);
    tmp_image.fill(0, stream);

    DeviceImageT paired_images[2]{image, tmp_image};

    int i = 0;
    while (true) {
        dim3 num_blocks{};
        num_blocks.x = div_ceil<int>(image.m_width, 32);
        num_blocks.y = div_ceil<int>(image.m_height, 32);
        dim3 block_dim{32, 32};
        spread_kernel<<<num_blocks, block_dim, 0, stream>>>(paired_images[i % 2], paired_images[(i + 1) % 2]);
        CHECK_CU(cudaStreamSynchronize(stream)); // Not to overload the device with work
        ++i;
        if (i == num_iterations) break;
    }

    if (i % 2 == 1) image.copy_from(tmp_image, stream);

    CHECK_CU(cudaStreamSynchronize(stream));
}
