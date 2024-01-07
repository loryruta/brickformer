#include "SpreadValue.cuh"

#include <glm/ext/scalar_constants.hpp>

#include "primitives.cuh"

using namespace lego_builder;

__global__
void spread_kernel(
    DeviceImage<1, uint8_t>* src_image,
    DeviceImage<1, uint8_t>* dst_image,
    uint32_t kernel_size,
    uint32_t* changes
    )
{
    assert(src_image->m_width == dst_image->m_width && src_image->m_height == dst_image->m_height);
    assert(kernel_size > 0);

    // One warp = one pixel

    int32_t px = blockIdx.x;
    int32_t py = blockIdx.y;

    if (px >= src_image->m_width || py >= src_image->m_height) return;  // Discard the warp

    int32_t half_k = kernel_size >> 1;

    int lane_x = threadIdx.x % 5;
    int lane_y = threadIdx.x / 5;

    uint8_t max_val = 0;
    if (lane_y < 5)
    {
        int num_items_x = div_ceil<int32_t>(kernel_size, 5);
        int num_items_y = div_ceil<int32_t>(kernel_size, 5);

        for (int ix = lane_x * num_items_x - half_k; ix < (lane_x + 1) * num_items_x - half_k; ix++)
        {
            for (int iy = lane_y * num_items_y - half_k; iy < (lane_y + 1) * num_items_y - half_k; iy++)
            {
                int nx = px + ix;
                int ny = py + iy;

                uint8_t nv = 0;
                if (nx < src_image->m_width && ny < src_image->m_height)
                    nv = src_image->read_pixel(nx, ny).x & 0x7F;
                max_val = glm::max(max_val, nv);
            }
        }
    }

    max_val = warp_max<uint8_t>(max_val);

    if ((threadIdx.x & 0x1F) != 0) return;

    uint8_t new_val;
    uint8_t cur_val = src_image->read_pixel(px, py).x;
    if ((cur_val & 0x80) != 0)
    {
        // Already processed, write the value as is;
        // Could do the check at the beginning, but doing the check at the end to allow warp operations
        new_val = cur_val;
    }
    else
    {
        if (max_val > 0)
        {
            // This should be in relation to the size of the slice
            new_val = max_val / 2;
        }
        else
        {
            new_val = 0;
        }

        if (cur_val != new_val) atomicAdd(changes, 1);
    }
    dst_image->write_pixel(px, py, glm::vec<1, uint8_t>{uint8_t(new_val)});
}

void SpreadValue::spread(DeviceImage<1, uint8_t>& image)
{
    DeviceImage<1, uint8_t>* src_image_d = to_device(image);

    DeviceImage<1, uint8_t> tmp_image = DeviceImage<1, uint8_t>::create(image.m_width, image.m_height);
    tmp_image.fill(0);

    DeviceImage<1, uint8_t>* tmp_image_d = to_device(tmp_image);

    DeviceImage<1, uint8_t>* paired_images[2]{src_image_d, tmp_image_d};

    uint32_t* changes_d = to_device<uint32_t>(0);

    const uint32_t k_kernel_size = 3;
    const uint32_t k_num_iterations = 8;

    size_t i = 0;
    while (true)
    {
        CHECK_CU(cudaMemset(changes_d, 0, sizeof(uint32_t)));
        CHECK_CU(cudaDeviceSynchronize());

        dim3 num_blocks;
        num_blocks.x = image.m_width;
        num_blocks.y = image.m_height;
        num_blocks.z = 1;

        size_t block_dim = 32;  // Each pixel is fit in a warp (used to visit the kernel)
        spread_kernel<<<num_blocks, block_dim>>>(paired_images[i % 2], paired_images[(i + 1) % 2], k_kernel_size, changes_d);
        CHECK_CU(cudaDeviceSynchronize());

        uint32_t changes = to_host(changes_d);
        printf("[SpreadValue] Iteration %zu; Changes: %d\n", i, changes);

        // TODO (improvement) exit when no change is done! (now leads to infinite loop ... why? ... :( )

        //if (changes == 0) break;

        ++i;
        if (i >= k_num_iterations) break;
    }

    if (i % 2 == 0) image.copy_from(tmp_image);

    CHECK_CU(cudaFree(changes_d));
    CHECK_CU(cudaFree(src_image_d));
    CHECK_CU(cudaFree(tmp_image_d));
}
