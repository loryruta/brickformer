#include "primitives.cuh"

#include <optional>
#include <random>

#include "misc.cuh"

using namespace lego_builder;

template<typename OPERATION>
__global__ void calc_warp_reduce_cuda(const float* data, float* result)
{
    // Note: The kernel launch configuration is expected to fit the data

    uint32_t warp_id = blockIdx.x * (blockDim.x >> 5) + (threadIdx.x >> 5);
    uint32_t lane_id = cub::LaneId();

    result[warp_id] = warp_reduce<float, OPERATION>(data[(warp_id << 5) + lane_id]);
}

template<typename OPERATION>
void calc_warp_reduce_cpu(const float* data, size_t num_warps, float* result)
{
    static const OPERATION op;

    for (size_t i = 0; i < num_warps; i++)
    {
        float val = data[i * 32];
        for (size_t j = 1; j < 32; j++) val = op(val, data[i * 32 + j]);
        result[i] = val;
    }
}

template<typename OPERATION>
void test_reduce()
{
    // Configurable:
    const size_t k_num_blocks = 1024;
    const size_t k_block_dim = 1024;

    const size_t k_num_warps = (k_block_dim >> 5) * k_num_blocks;

    float* data;
    CHECK_CU(cudaMallocManaged(&data, 32 * k_num_warps * sizeof(float)));

    float ground_truth[k_num_warps];

    float* result;
    CHECK_CU(cudaMallocManaged(&result, k_num_warps * sizeof(float)));

    // Randomly initialize the input
    uint32_t seed = 10;
    std::minstd_rand random_engine(seed);
    std::uniform_real_distribution<float> data_dist{};
    std::uniform_int_distribution<uint32_t> mask_dist{};

    for (uint32_t i = 0; i < k_num_warps; i++)
    {
        for (uint32_t j = 0; j < 32; j++) data[i * 32 + j] = data_dist(random_engine);
    }

    // Calculate the ground truth (no CUDA)
    calc_warp_reduce_cpu<OPERATION>(data, k_num_warps, ground_truth);

    // Use warp_reduce() CUDA function
    calc_warp_reduce_cuda<OPERATION><<<k_num_blocks, k_block_dim>>>(data, result);
    CHECK_CU(cudaDeviceSynchronize());

    // Check the ground truth against the result
    for (uint32_t i = 0; i < k_num_warps; i++)
    {
        if (std::abs(ground_truth[i] - result[i]) > 0.0001f)
        {
            printf("Warp %d:\n", i);
            for (uint32_t j = 0; j < 32; j++) printf("%d: %.3f, ", j, data[i * 32 + j]);

            printf("\n");
            printf("  CPU result: %.3f\n", ground_truth[i]);
            printf("  CUDA result: %.3f\n", result[i]);

            CHECK_STATE(false);
        }
    }

    printf("Check passed!\n");
}

void test_reduce_all()
{
    printf("Reduce MIN:\n");
    test_reduce<Min<float>>(); // TODO better relation between operation and data type

    printf("Reduce MAX:\n");
    test_reduce<Max<float>>();

    printf("Reduce ADD:\n");
    test_reduce<Add<float>>();
}


int main(int argc, char* argv[])
{
    test_reduce_all();

    return 0;
}
