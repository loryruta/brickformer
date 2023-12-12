#include <iostream>

#include <cassert>
#include <cstdint>
#include <cinttypes>
#include <cstdio>
#include <filesystem>

#include <glm/glm.hpp>
#include <thrust/device_ptr.h>
#include <thrust/device_vector.h>
#include <thrust/extrema.h>
#include <stb_image.h> // STB_IMAGE_IMPLEMENTATION already by raylib

#include "bricks.cuh"
#include "DeviceImage.cuh"
#include "primitives.cuh"
#include "App.cuh"
#include "StopWatch.hpp"

#define MAP_WIDTH  256
#define MAP_HEIGHT 256

using namespace lego_builder;

struct Placement
{
    uint8_t m_x, m_y;
    uint8_t m_brick_id;
};

__constant__ const size_t k_num_placements = MAP_WIDTH * MAP_HEIGHT * k_num_bricks;

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
    if (!is_brick_grid_thread()) return;

    uint32_t lane_id = cub::LaneId();
    uint32_t lane_x = lane_id % 4;
    uint32_t lane_y = lane_id / 4;

    for (uint32_t item_x = 0; item_x < 4; item_x++)
    {
        for (uint32_t item_y = 0; item_y < 4; item_y++)
        {
            uint32_t bx = lane_x * 4 + item_x;
            uint32_t by = lane_y * 4 + item_y;
            assert(bx < 16 && by < 16);

            callback(bx, by);
        }
    }
}

__device__ size_t count_adjacent_bricks(
        Placement const& placement,
        int32_t bx,
        int32_t by,
        PlacementMapT const* cur_placement_map
        )
{
    auto& brick = k_bricks[placement.m_brick_id];

    int32_t map_x = placement.m_x + bx;
    int32_t map_y = placement.m_y + by;

    size_t count = 0;
    count += map_x + 1 < cur_placement_map->m_width && (bx + 1 >= 16 || !brick[bx + 1][by]) &&
            cur_placement_map->read_pixel(map_x + 1, map_y).x > 0;
    count += map_y + 1 < cur_placement_map->m_width && (by + 1 >= 16 || !brick[bx][by + 1]) &&
            cur_placement_map->read_pixel(map_x, map_y + 1).x > 0;
    count += map_x - 1 >= 0 && (bx - 1 < 0 || !brick[bx - 1][by]) &&
            cur_placement_map->read_pixel(map_x - 1, map_y).x > 0;
    count += map_y - 1 >= 0 && (by - 1 < 0 || !brick[bx][by - 1]) &&
            cur_placement_map->read_pixel(map_x, map_y - 1).x > 0;
    return count;
}

__device__ float eval_placement(
        Placement const& placement,
        ColorMapT const* color_map,
        PlacementMapT const* cur_placement_map,
        PlacementMapT const* prv_placement_map
        )
{
    assert(placement.m_brick_id < 16);
    auto& brick = k_bricks[placement.m_brick_id];

    // Check if the current placement is invalid:
    // - goes outside the color_map
    // - overlaps a previous placement on this layer
    bool invalid = false;
    iterate_brick_grid([&](uint32_t bx, uint32_t by)
    {
        uint32_t pos_x = placement.m_x + bx;
        uint32_t pos_y = placement.m_y + by;

        if (brick[bx][by])
        {
            invalid |= pos_x >= color_map->m_width && pos_y >= color_map->m_height;  // The placement goes out of bounds
            invalid |= cur_placement_map->read_pixel(pos_x, pos_y).x != 0; // The placement would overlap a previous placement
        }
    });
    invalid = __any_sync(FULL_MASK, invalid);

    // "Reward" the placement based on:
    // - the number of colored cells covered of the current layer
    // - the number of adjacent placements
    // - the size of the brick
    // - TODO the number of underlying bricks covered by the current placement
    size_t num_covered_map_cells = 0;  // The number of cells of the underlying color_map being covered by the placement
    size_t brick_size = 0;             // The number of set cells of the brick's grid
    size_t num_adjacent_bricks = 0;    // A number proportional to the number of bricks adjacent to the placement (likely >=)

    iterate_brick_grid([&](int32_t bx, int32_t by)
    {
        int32_t map_x = placement.m_x + bx;
        int32_t map_y = placement.m_y + by;

        if (brick[bx][by])
        {
            num_covered_map_cells += color_map->read_pixel(map_x, map_y).a > 0;
            brick_size++;
            num_adjacent_bricks += count_adjacent_bricks(placement, bx, by, cur_placement_map);
        }
    });

    num_covered_map_cells = warp_add(num_covered_map_cells);
    brick_size = warp_add(1);
    num_adjacent_bricks = warp_add(num_adjacent_bricks);

    float val = 0.0f; // How good is this placement?
    if (!invalid)
    {
        val += float(num_covered_map_cells);
        val += float(brick_size);
        val += float(num_adjacent_bricks);
    }
    return val;
}

__global__ void eval_placements(
        Placement const* placements,
        ColorMapT const* color_map,
        PlacementMapT const* cur_placement_map,
        PlacementMapT const* prv_placement_map,
        float* out_result
        )
{
    size_t i = (blockIdx.x << 5) + (threadIdx.x >> 5);

    float val = eval_placement(placements[i], color_map, cur_placement_map, prv_placement_map);
    if (threadIdx.x % 32 == 0) out_result[i] = val;
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

ColorMapT* load_color_map(char const* path)
{
    int width, height;
    int channels;
    uint8_t* data = stbi_load(path, &width, &height, &channels, STBI_rgb_alpha);
    CHECK_STATE(data);
    CHECK_STATE(channels == STBI_rgb_alpha);

    ColorMapT* color_map = ColorMapT::create_device_ptr(width, height, data);

    stbi_image_free(data);

    return color_map;
}

template<typename T>
std::pair<size_t, T*> find_max_element(T* d_array, size_t size)
{
    thrust::device_ptr<T> d_base_ptr = thrust::device_pointer_cast(d_array);
    thrust::device_ptr<T> d_result = thrust::max_element(d_base_ptr, d_base_ptr + size);

    size_t i = d_result - d_base_ptr;
    return {i, d_result.get()};
}

void place(const Placement& placement, uint16_t placement_id, PlacementMapT* placement_map)
{
    auto& brick = k_bricks[placement.m_brick_id];

    PlacementMapT::PixelT value{placement_id};
    for (uint8_t bx = 0; bx < 16; bx++)
    {
        for (uint8_t by = 0; by < 16; by++)
        {
            if (brick[bx][by])
            {
                placement_map->write_pixel(placement.m_x + bx, placement.m_y + by, value);
            }
        }
    }
}

int main(int argc, char* argv[])
{
    printf("Bricks: %zu\n", k_num_bricks);

    std::filesystem::path resource_dir = std::filesystem::path(__FILE__).parent_path().parent_path() / "layers";
    std::string color_map_path = (resource_dir / "layer1.png").string();

    printf("Loading color map at \"%s\"...\n", color_map_path.c_str());
    ColorMapT* color_map = load_color_map(color_map_path.c_str());

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

    PlacementMapT* cur_placement_map = PlacementMapT::create_device_ptr(MAP_WIDTH, MAP_HEIGHT, nullptr);
    cur_placement_map->fill(0);

    PlacementMapT* prv_placement_map = PlacementMapT::create_device_ptr(MAP_WIDTH, MAP_HEIGHT, nullptr);
    prv_placement_map->fill(0);

    for (size_t i = 0; i < 10; i++)
    {
        StopWatch stop_watch{};

        printf("Round %zu\n", i);

        // Evaluate the objective function on all the possible placements
        stop_watch.reset();

        eval_placements<<<num_blocks, block_dim>>>(d_placements, color_map, cur_placement_map, prv_placement_map, d_eval_result);
        CHECK_CU(cudaDeviceSynchronize());

        printf("  Evaluation performed in: %" PRIu64 " ms\n", stop_watch.elapsed_millis());

        // Get the placement that maximizes the objective function
        stop_watch.reset();

        std::pair<size_t, float*> max_pair = find_max_element(d_eval_result, k_num_placements);

        Placement placement = to_host(d_placements + max_pair.first);
        float max_reward = to_host(max_pair.second);
        CHECK_STATE(max_reward > 0.0f);  // If 0 it's an invalid placement!

        printf("  Best placement index: %zu\n", max_pair.first);
        printf("  Placement: (%d, %d) -> %d\n", placement.m_x, placement.m_y, placement.m_brick_id);
        printf("  Reward: %.3f\n", max_reward);
        //printf("  Best solution found in: %" PRIu64 " ms\n", stop_watch.elapsed_millis());

        // Place the brick in the current layer
        stop_watch.reset();

        place(placement, uint16_t(i), cur_placement_map);

        //printf("  Placement added in: %" PRIu64 " ms\n", stop_watch.elapsed_millis());

        //
    }

    /*
    App app;
    app.set_color_map(color_map);
    app.set_placement_map(cur_placement_map);

    while (!app.should_close())
    {
        app.draw();
    }*/

    return 0;
}
