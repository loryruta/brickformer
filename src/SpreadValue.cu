#include "SpreadValue.cuh"
#include "primitives.cuh"

#include <glm/ext/scalar_constants.hpp>

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

    uint8_t pv = src_image->read_pixel(px, py).x;
    if ((pv & 0x80) != 0)
    {
        // Already processed, write the value as is
        dst_image->write_pixel(px, py, glm::vec<1, uint8_t>{pv});
        return;
    }

    int32_t half_k = kernel_size >> 1;

    int32_t lane_x = threadIdx.x;
    int32_t lane_y = threadIdx.y;

    int32_t num_items_x = div_ceil<int32_t>(kernel_size, 5);
    int32_t num_items_y = div_ceil<int32_t>(kernel_size,5);

    uint8_t max_val = 0;
    for (int32_t ix = lane_x * num_items_x - half_k; ix < (lane_x + 1) * num_items_x - half_k; ix++)
    {
        for (int32_t iy = lane_y * num_items_y - half_k; iy < (lane_y + 1) * num_items_y - half_k; iy++)
        {
            int32_t nx = px + ix;
            int32_t ny = py + iy;

            uint8_t nv = 0;
            if (nx < src_image->m_width && ny < src_image->m_height)
                nv = src_image->read_pixel(nx, ny).x & 0x7F;

            max_val = glm::max(max_val, nv);
        }
    }

    max_val = warp_max(max_val);

    uint8_t new_val = max_val > 0 ? max_val - 1 : 0;
    if (pv != new_val) atomicAdd(changes, 1);
    dst_image->write_pixel(px, py, glm::vec<1, uint8_t>{uint8_t(new_val)});
}

/*
__global__
void conv_gaussian_kernel(
    DeviceImage<1, uint8_t>* src_image,
    DeviceImage<1, uint8_t>* dst_image,
    uint32_t k
    )
{
    assert(src_image->m_width == dst_image->m_width && src_image->m_height == dst_image->m_height);
    assert(k > 0);

    bool should_print = blockIdx.x == 0 && blockIdx.y == 0;

    // One warp = one pixel

    int32_t px = blockIdx.x;
    int32_t py = blockIdx.y;

    if (px >= src_image->m_width || py >= src_image->m_height) return;  // Discard the warp

    int32_t half_k = k >> 1;

    int32_t lane_x = threadIdx.x;
    int32_t lane_y = threadIdx.y;

    int32_t num_items_x = div_ceil<int32_t>(k, 5);
    int32_t num_items_y = div_ceil<int32_t>(k ,5);

    // I've kinda tested it: https://www.geogebra.org/3d/vsrgadxg
    float sigma = 0.3f * k;
    float sigma2 = sigma * sigma;

    float kv_den = 1.0f / glm::sqrt(2.0f * glm::pi<float>() * sigma2);

//    if (should_print)
//    {
//        printf("k: %d, half_k: %d, lane_x: %d, lane_y: %d, num_items_x: %d, num_items_y: %d, sigma: %f, kv_den: %f\n",
//               k, half_k,
//               lane_x, lane_y, num_items_x, num_items_y,
//               sigma, kv_den
//        );
//    }

    float v = 0.0f;
    for (int32_t ix = lane_x * num_items_x - half_k; ix < (lane_x + 1) * num_items_x - half_k; ix++)
    {
        for (int32_t iy = lane_y * num_items_y - half_k; iy < (lane_y + 1) * num_items_y - half_k; iy++)
        {
            int32_t nx = px + ix;
            int32_t ny = py + iy;

            float kv = kv_den * glm::exp(-((ix * ix + iy * iy) / (2.0f * sigma2)));  // Compute kernel on-the-fly
//            if (should_print) printf("(%d, %d) -> %f\n", ix, iy, kv);

            uint8_t nv = 0;
            if (nx < src_image->m_width && ny < src_image->m_height) nv = src_image->read_pixel(nx, ny).x;

            v += float(nv) * kv;
        }
    }

    v = warp_add(v);  // Sum the partial sums within the warp

    dst_image->write_pixel(px, py, glm::vec<1, uint8_t>{uint8_t(v)});
}*/

/*
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
}*/

void SpreadValue::spread(DeviceImage<1, uint8_t>& image)
{
    DeviceImage<1, uint8_t>* src_image_d = to_device(image);

    DeviceImage<1, uint8_t> tmp_image = DeviceImage<1, uint8_t>::create(image.m_width, image.m_height);
    tmp_image.fill(0);
    DeviceImage<1, uint8_t>* tmp_image_d = to_device(tmp_image);

    DeviceImage<1, uint8_t>* paired_images[2]{src_image_d, tmp_image_d};

    uint32_t* changes_d = to_device<uint32_t>(0);

    const uint32_t k_kernel_size = 3;
    const uint32_t k_num_iterations = 64;

    size_t i = 0;

    while (true)
    {
        CHECK_CU(cudaMemset(changes_d, 0, sizeof(uint32_t)));
        CHECK_CU(cudaDeviceSynchronize());

        dim3 num_blocks;
        num_blocks.x = image.m_width;
        num_blocks.y = image.m_height;
        num_blocks.z = 1;

        dim3 block_dim(5, 5, 1);  // Each pixel is fit in a warp (used to visit the kernel)
        spread_kernel<<<num_blocks, block_dim>>>(paired_images[i % 2], paired_images[(i + 1) % 2], k_kernel_size, changes_d);
        CHECK_CU(cudaDeviceSynchronize());

        uint32_t changes = to_host(changes_d);

        //printf("[SpreadValue] Iteration %zu; Changes: %d\n", i, changes);

        // TODO (improvement) exit when no change is done! (now leads to infinite loop :( )

        //if (changes == 0) break;
        if (i > 100) break;

        ++i;
    }

    if (i % 2 == 0) image.copy_from(tmp_image);

    CHECK_CU(cudaFree(tmp_image_d));

    /*
    size_t num_iterations = 0;

    while (true)
    {
        CHECK_CU(cudaMemset(changes_d, 0, sizeof(uint32_t)));

        dim3 num_blocks;
        num_blocks.x = div_ceil<size_t>(image.m_width, 32);
        num_blocks.y = div_ceil<size_t>(image.m_height, 32);
        num_blocks.z = 1;

        dim3 block_dim(32, 32, 1);
        conv_gaussian_kernel<<<num_blocks, block_dim>>>(src_image_d, image_d, );

        uint32_t changes = to_host(changes_d);

        printf("[SpreadVal] Iteration %zu; Changes: %d\n", num_iterations, changes);

        if (changes == 0) break;
        //if (num_iterations > 300000) break;

        ++num_iterations;
    }

    printf("[SpreadVal ] Values spread; Iterations: %zu\n", num_iterations);*/
}
