#include <iostream>

#include <cassert>
#include <cstdint>
#include <cstdio>
#include <filesystem>

#define STB_IMAGE_IMPLEMENTATION
#include <stb_image.h>
#include <glm/glm.hpp>
#include <thrust/device_ptr.h>
#include <thrust/extrema.h>

#include "bricks.cuh"
#include "exceptions.hpp"

#define FULL_MASK 0xFFFFFFFF

#define MAP_WIDTH  256
#define MAP_HEIGHT 256

using namespace lego_builder;

struct Placement
{
    uint8_t m_x, m_y;
    uint8_t m_brick_id;
};

__constant__ const size_t k_num_placements = MAP_WIDTH * MAP_HEIGHT * k_num_bricks;

/// Represents an image whose pixels are organized in a row-first manner.
template<uint32_t FORMAT, typename DATA_TYPE>
struct Image
{
    uint32_t m_width, m_height;
    uint8_t* m_data;
};

using ColorMapT = Image<4, float>;
using PlacementMapT = Image<1, uint16_t>;

template<uint32_t FORMAT, typename DATA_TYPE>
__device__ glm::vec<FORMAT, DATA_TYPE> read_pixel(Image<FORMAT, DATA_TYPE> const& image, uint32_t x, uint32_t y)
{
    size_t base_pos = y * image.m_height * 4 + x;
    glm::vec<FORMAT, DATA_TYPE> pixel{};
    for (int i = 0; i < FORMAT; i++) pixel[i] = image.m_data[base_pos + i];
    return pixel;
}


template<typename T>
__device__ T warp_sum(uint32_t mask, T value)
{

}

/// Checks whether the thread executing this function covers a brick grid cell.
__device__ bool is_brick_grid_thread()
{
    uint32_t warp_y = cub::LaneId() / 4;
    return warp_y < 4;
}

/// Iterates the brick grid within the warp and callbacks every occurrence.
template<typename CALLBACK>
__device__ void iterate_brick_grid(CALLBACK callback)
{
    assert(is_brick_grid_thread());

    uint32_t warp_id = cub::LaneId();
    uint32_t warp_x = warp_id % 4; // TODO & 0xFF
    uint32_t warp_y = warp_id / 4; // TODO >> 2
    assert(warp_y < 4);

    for (uint32_t item_x = 0; item_x < 4; item_x++)
    {
        for (uint32_t item_y = 0; item_y < 4; item_y++)
        {
            uint32_t grid_x = warp_x * 4 + item_x;
            uint32_t grid_y = warp_y * 4 + item_y;
            assert(grid_x < 16 && grid_y < 16);

            callback(grid_x, grid_y);
        }
    }
}

__device__ size_t count_adjacent_bricks(
        Placement const& placement,
        int32_t bx,
        int32_t by,
        PlacementMapT const& cur_placement_map
        )
{
    uint8_t** brick; // TODO

    int32_t map_x = placement.m_x + bx;
    int32_t map_y = placement.m_y + by;

    size_t count = 0;
    count += map_x + 1 < cur_placement_map.m_width && (bx + 1 >= 16 || !brick[bx + 1][by]) &&
            read_pixel(cur_placement_map, map_x + 1, map_y).x > 0;
    count += map_y + 1 < cur_placement_map.m_width && (by + 1 >= 16 || !brick[bx][by + 1]) &&
            read_pixel(cur_placement_map, map_x, map_y + 1).x > 0;
    count += map_x - 1 >= 0 && (bx - 1 < 0 || !brick[bx - 1][by]) &&
            read_pixel(cur_placement_map, map_x - 1, map_y).x > 0;
    count += map_y - 1 >= 0 && (by - 1 < 0 || !brick[bx][by - 1]) &&
            read_pixel(cur_placement_map, map_x, map_y - 1).x > 0;
    return count;
}

__device__ float eval_placement(
        Placement const& placement,
        ColorMapT const& color_map,
        Image<1, uint16_t> const& cur_placement_map,
        Image<1, uint16_t> const& prv_placement_map
        )
{
    assert(is_brick_grid_thread());

    auto& brick = k_bricks[placement.m_brick_id];

    uint32_t mask = FULL_MASK;

    // TODO Avoid additional processing if a thread works on an empty area of the block's grid

    // Check if the current placement is invalid:
    // - goes outside the color_map
    // - overlaps a previous placement on this layer
    bool invalid = false;
    iterate_brick_grid([&](uint32_t x, uint32_t y)
    {
        uint32_t pos_x = placement.m_x + x;
        uint32_t pos_y = placement.m_y + y;

        bool cur_invalid = brick[x][y];
        cur_invalid = cur_invalid && pos_x >= color_map.m_width && pos_y >= color_map.m_height;    // The placement goes out of bounds
        cur_invalid = cur_invalid && read_pixel(cur_placement_map, pos_x, pos_y).x != 0;  // The placement would overlap a previous placement
        invalid = __any_sync(mask, cur_invalid);
    });

    // "Reward" the placement based on:
    // - the number of colored cells covered of the current layer
    // - the number of adjacent placements
    // - the size of the brick
    // - TODO the number of underlying bricks covered by the current placement
    size_t num_covered_map_cells = 0;  // The number of cells of the underlying color_map being covered by the placement
    size_t brick_size = 0;             // The size of the current brick
    size_t num_adjacent_bricks = 0;    // A number proportional to the number of bricks adjacent to the placement (likely >=)

    iterate_brick_grid([&](int32_t bx, int32_t by)
    {
        int32_t map_x = placement.m_x + bx;
        int32_t map_y = placement.m_y + by;

        if (brick[bx][by])
        {
            bool cover_map = read_pixel(color_map, map_x, map_y).a > 0;
            num_covered_map_cells += warp_sum(FULL_MASK, cover_map); // TODO maybe not FULL

            brick_size += warp_sum(FULL_MASK, 1); // TODO maybe not FULL

            size_t cur_adjacent_bricks = count_adjacent_bricks(placement, bx, by, cur_placement_map);
            num_adjacent_bricks += warp_sum(FULL_MASK, cur_adjacent_bricks); // TODO maybe not FULL
        }
    });

    float result = 0.0f; // How good is this placement?
    result += float(num_covered_map_cells);
    result += float(brick_size);
    result += float(num_adjacent_bricks);
    return result;
}

__global__ void eval_placements(
        Placement const* placements,
        ColorMapT const& color_map,
        PlacementMapT const& cur_placement_map,
        PlacementMapT const& prv_placement_map,
        float* out_result
        )
{
    size_t i = blockIdx.x * 32 + (threadIdx.x >> 5);
    out_result[i] = eval_placement(placements[i], color_map, cur_placement_map, prv_placement_map);
}

__global__ void init_placements(Placement* placements)
{
    size_t i = blockIdx.x * 32 + (threadIdx.x >> 5);

    if (threadIdx.x % 32 == 0)
    {
        Placement placement{};
        placement.m_x = (i / k_num_bricks) % MAP_WIDTH;
        placement.m_y = i / (MAP_WIDTH * k_num_bricks);
        placement.m_brick_id = i % k_num_bricks;
        placements[i] = placement;
    }
}

void print_devices()
{
    int num_devices;
    CHECK_CU(cudaGetDeviceCount(&num_devices));

    printf("Number of devices: %d\n", num_devices);

    for (int i = 0; i < num_devices; i++)
    {
        cudaDeviceProp prop{};
        cudaGetDeviceProperties(&prop, i);

        printf("Device Number: %d\n", i);
        printf("  Device name: %s\n", prop.name);
        printf("  Memory Clock Rate (MHz): %d\n", prop.memoryClockRate/1024);
        printf("  Memory Bus Width (bits): %d\n", prop.memoryBusWidth);
        printf("  Peak Memory Bandwidth (GB/s): %.1f\n", 2.0*prop.memoryClockRate*(prop.memoryBusWidth/8.0)/1.0e6);
        printf("  Total global memory (Gbytes) %.1f\n",(float)(prop.totalGlobalMem)/1024.0/1024.0/1024.0);
        printf("  Shared memory per block (Kbytes) %.1f\n",(float)(prop.sharedMemPerBlock)/1024.0);
        printf("  Minor-major: %d-%d\n", prop.minor, prop.major);
        printf("  Warp size: %d\n", prop.warpSize);
        printf("  Concurrent kernels: %s\n", prop.concurrentKernels ? "yes" : "no");
        printf("  Concurrent computation/communication: %s\n",prop.deviceOverlap ? "yes" : "no");
        printf("  Max threads per block: %d\n", prop.maxThreadsPerBlock);
    }
}

ColorMapT load_color_map(char const* path)
{
    FILE* f = fopen(path, "r");
    CHECK_STATE(f);

    int image_width, image_height;
    int channels;
    uint8_t* image_data = stbi_load_from_file(f, &image_width, &image_height, &channels, STBI_rgb_alpha);
    CHECK_STATE(channels == STBI_rgb_alpha);

    fclose(f);

    size_t image_size = image_width * image_height * 4;

    uint8_t* cuda_buffer;
    CHECK_CU(cudaMalloc(&cuda_buffer, image_size));

    CHECK_CU(cudaMemcpy(cuda_buffer, image_data, image_size, cudaMemcpyHostToDevice));

    stbi_image_free(image_data);

    ColorMapT color_map;
    color_map.m_width = image_width;
    color_map.m_height = image_height;
    color_map.m_data = cuda_buffer;
    return color_map;
}

PlacementMapT create_placement_map()
{
    PlacementMapT placement_map;
    placement_map.m_width = MAP_WIDTH;
    placement_map.m_height = MAP_HEIGHT;

    CHECK_CU(cudaMalloc(&placement_map.m_data, MAP_WIDTH * MAP_HEIGHT));
    CHECK_CU(cudaMemset(placement_map.m_data, 0, MAP_WIDTH * MAP_HEIGHT));
    return placement_map;
}

template<typename T>
std::pair<size_t, T*> find_max(const T* d_array, size_t size)
{
    thrust::device_ptr<T> d_array_ptr = thrust::device_pointer_cast(d_array);
}


int main(int argc, char* argv[])
{
    printf("Bricks: %zu\n", k_num_bricks);

    std::filesystem::path resource_dir = std::filesystem::path(__FILE__).parent_path().parent_path() / "layers";
    std::filesystem::path color_map_path = resource_dir / "layer1.png";

    printf("Loading color map at \"%s\"...\n", color_map_path.c_str());
    ColorMapT color_map = load_color_map(color_map_path.c_str());

    printf("Allocating %zu possible placements (%.3f Mb)...\n", k_num_placements, (k_num_placements * sizeof(Placement)) / 1e6);

    Placement* d_placements;  // The list of all possible placements
    CHECK_CU(cudaMalloc(&d_placements, k_num_placements * sizeof(Placement)));

    // A block processes at most 32 placements, a placement takes 32 threads (1 warp)
    // An arch of 1024 threads per block is required!
    size_t num_blocks = k_num_placements >> 5;
    size_t block_dim = 1024;

    init_placements<<<num_blocks, block_dim>>>(d_placements);  // We could use a fitter configuration
    CHECK_CU(cudaDeviceSynchronize());

    float* d_eval_result;  // The value of the objective function for all the placements
    CHECK_CU(cudaMalloc(&d_eval_result, k_num_placements * sizeof(float)));

    PlacementMapT cur_placement_map = create_placement_map();
    PlacementMapT prv_placement_map = create_placement_map();

    for (int i = 0; i < 5; i++)
    {
        // Evaluate the objective function on all the possible placements
        eval_placements<<<num_blocks, block_dim>>>(d_placements, color_map, cur_placement_map, prv_placement_map, d_eval_result);
        CHECK_CU(cudaDeviceSynchronize());

        // Get the placement that maximizes the objective function
        find_max();
        CHECK_CU(cudaDeviceSynchronize());


    }

    return 0;
}
