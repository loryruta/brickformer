#include "SpreadValue.cuh"


using namespace lego_builder;

__global__
void spread_kernel(DeviceImage<1, uint8_t>* image, uint32_t* changes)
{
    uint32_t px = blockIdx.x * blockDim.x + threadIdx.x;
    uint32_t py = blockIdx.y * blockDim.y + threadIdx.y;

    if (px < image->m_width && py < image->m_height)
    {
        uint8_t v0 = px > 0 ? image->read_pixel(px - 1, py).r : 0;
        uint8_t v1 = py > 0 ? image->read_pixel(px, py - 1).r : 0;
        uint8_t v2 = px < image->m_width - 1 ? image->read_pixel(px + 1, py).r : 0;
        uint8_t v3 = py < image->m_height - 1 ? image->read_pixel(px, py + 1).r : 0;

        uint8_t v = image->read_pixel(px, py).r;
        uint8_t maxv = glm::max(v0, glm::max(v1, glm::max(v2, v3)));

        if (maxv > 0 && v != maxv)
        {
            image->write_pixel(px, py, glm::vec<1, uint8_t>{uint8_t(maxv - 1)});
            (*changes)++;
        }
    }
}

void SpreadValue::spread(DeviceImage<1, uint8_t>& image)
{
    DeviceImage<1, uint8_t>* image_d = to_device(image);
    uint32_t* changes_d = to_device<uint32_t>(0);

    size_t iteration = 0;

    while (true)
    {
        CHECK_CU(cudaMemset(changes_d, 0, sizeof(uint32_t)));

        dim3 num_blocks;
        num_blocks.x = div_ceil<size_t>(image.m_width, 32);
        num_blocks.y = div_ceil<size_t>(image.m_height, 32);
        num_blocks.z = 1;

        dim3 block_dim(32, 32, 1);
        spread_kernel<<<num_blocks, block_dim>>>(image_d, changes_d);

        uint32_t changes = to_host(changes_d);

        printf("[SpreadVal] Iteration %zu; Changes: %d\n", iteration, changes);

        if (changes == 0) break;

        ++iteration;
    }

    printf("[SpreadVal] Done!\n");
}
