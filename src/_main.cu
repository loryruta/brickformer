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

#include "DeviceImage.cuh"
#include "_App.cuh"
#include "bricks.cuh"
#include "primitives.cuh"
#include "util/StopWatch.hpp"

#define MAP_WIDTH  256
#define MAP_HEIGHT 256

using namespace lego_builder;

struct Placement
{
    uint8_t m_x, m_y;
    uint8_t m_brick_id;
};

__constant__
const size_t k_num_placements = MAP_WIDTH * MAP_HEIGHT * k_num_bricks;

/// Iterates the brick grid within the warp and callbacks every occurrence.
/// Important: don't perform warp sync operations within the callback.
template<typename CALLBACK>
__device__
void iterate_brick_grid(CALLBACK callback)
{
    uint32_t lane_i = cub::LaneId();
    uint32_t lane_x = lane_i % 5;
    uint32_t lane_y = lane_i / 5;

    if (lane_y >= 5) return;

    const uint32_t k_item_w = div_ceil(BRICK_MAX_WIDTH, 5);
    const uint32_t k_item_h = div_ceil(BRICK_MAX_HEIGHT, 5);

    for (uint32_t item_x = 0; item_x < k_item_w; item_x++)
    {
        for (uint32_t item_y = 0; item_y < k_item_h; item_y++)
        {
            uint32_t bx = lane_x * k_item_w + item_x;
            uint32_t by = lane_y * k_item_h + item_y;

            if (bx < BRICK_MAX_WIDTH && by < BRICK_MAX_HEIGHT) callback(bx, by);
        }
    }
}

__device__
void inspect_neighborhood(
    const Placement& placement,
    int32_t bx, int32_t by,
    const PlacementMapT* placement_map,
    size_t& num_neighbors,
    size_t& num_connectible_sides
    )
{
    auto& brick = k_bricks[placement.m_brick_id];

    int32_t mx = placement.m_x + bx;
    int32_t my = placement.m_y + by;

    if (mx + 1 < placement_map->m_width && (bx + 1 >= BRICK_MAX_WIDTH || !brick[bx + 1][by]))
    {
        if (placement_map->read_pixel(mx + 1, my).x > 0) ++num_neighbors;
        ++num_connectible_sides;
    }

    if (my + 1 < placement_map->m_width && (by + 1 >= BRICK_MAX_HEIGHT || !brick[bx][by + 1]))
    {
        if (placement_map->read_pixel(mx, my + 1).x > 0) ++num_neighbors;
        ++num_connectible_sides;
    }

    if (mx - 1 >= 0 && (bx - 1 < 0 || !brick[bx - 1][by]))
    {
        if (placement_map->read_pixel(mx - 1, my).x > 0) ++num_neighbors;
        ++num_connectible_sides;
    }

    if (my - 1 >= 0 && (by - 1 < 0 || !brick[bx][by - 1]))
    {
        if (placement_map->read_pixel(mx, my - 1).x > 0) ++num_neighbors;
        ++num_connectible_sides;
    }
}

__device__ float eval_placement(
        Placement const& placement,
        ColorMapT const* color_map,
        PlacementMapT const* cur_placement_map,
        PlacementMapT const* prv_placement_map
        )
{
    auto& brick = k_bricks[placement.m_brick_id];

    // "Reward" the placement based on:
    // - the number of colored cells covered of the current layer
    // - the number of adjacent placements
    // - the size of the brick
    // - TODO the number of underlying bricks covered by the current placement
    bool is_outside = false;
    bool is_overlapping = false;
    size_t num_covered_map_cells = 0;  // The number of cells of the underlying color_map being covered by the placement
    size_t brick_size = 0;             // The number of set cells of the brick's grid
    size_t num_neighbors = 0;          // A number *proportional* to the number of bricks adjacent to the placement (likely >=)
    size_t num_connectible_sides = 0;  // A number *proportional* to the number of connectible sides

    iterate_brick_grid([&](int32_t bx, int32_t by)
    {
        uint32_t mx = placement.m_x + bx;
        uint32_t my = placement.m_y + by;

        if (brick[bx][by])
        {
            // Placement out of bounds
            is_outside |= mx >= color_map->m_width && my >= color_map->m_height;

            // Placement would overlap a previous placement on the current layer
            is_overlapping |= cur_placement_map->read_pixel(mx, my).x != 0;

            // Count the number of colored cells covered
            num_covered_map_cells += color_map->read_pixel(mx, my).a > 0;

            // Count the size of the brick (number of cells set in brick's grid)
            brick_size++;

            // Inspect the neighborhood to get:
            // - the number of adjacent bricks in the current layer
            // - whether this brick is covering a hole (all neighbors are set)
            inspect_neighborhood(placement, bx, by, cur_placement_map, num_neighbors, num_connectible_sides);
        }
    });

    // Important: If the warp's thread didn't cover any grid's cell (i.e. callback wasn't invoked).
    // The score must be zero!

    bool is_invalid = is_outside || is_overlapping;
    is_invalid = __any_sync(FULL_MASK, is_invalid);

    num_covered_map_cells = warp_add(num_covered_map_cells);  // TODO maybe group to a single reduction
    brick_size = warp_add(brick_size);
    num_neighbors = warp_add(num_neighbors);
    num_connectible_sides = warp_add(num_connectible_sides);

    float cn = float(num_covered_map_cells) / float(brick_size);
    float an = float(num_neighbors) / float(num_connectible_sides);
    float bn = float(brick_size) / float(BRICK_MAX_WIDTH * BRICK_MAX_HEIGHT);

    float score = 0.0f; // How good is this placement?
    if (!is_invalid)
    {
        float c = 0.7f * (cn * cn * cn) + 0.1f; // Color factor [0.1, 0.8]
        float a = an * an * an;                 // Adjacency factor [0.0, 1.0]
        float b = bn * 0.2f + 0.8f;             // Block size factor [0.8, 1.0]
        score = glm::max(a, c) * b;
    }
    return score;
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
    size_t i = (blockIdx.x << 5) + (threadIdx.x >> 5);

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
    for (uint8_t bx = 0; bx < BRICK_MAX_WIDTH; bx++)
    {
        for (uint8_t by = 0; by < BRICK_MAX_HEIGHT; by++)
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

    std::filesystem::path resource_dir = std::filesystem::path(__FILE__).parent_path().parent_path() / "resources";
    std::string color_map_path = (resource_dir / "layer1.png").string();

    printf("Loading color map at \"%s\"...\n", color_map_path.c_str());
    ColorMapT* color_map = load_color_map(color_map_path.c_str());

    printf("Allocating %zu possible placements (%.3f Mb)...\n", k_num_placements, (k_num_placements * sizeof(Placement)) / 1e6);

    Placement* d_placements;  // The list of all possible placements
    CHECK_CU(cudaMalloc(&d_placements, k_num_placements * sizeof(Placement)));

    // A block processes at most 32 placements, a placement takes 32 threads (1 warp)
    // An arch of 1024 threads per block is required!
    const size_t num_blocks = div_ceil(k_num_placements, size_t(32));
    size_t block_dim = 1024;

    init_placements<<<num_blocks, block_dim>>>(d_placements);  // We could use a fitter configuration
    CHECK_CU(cudaDeviceSynchronize());

    float* d_eval_result;  // The value of the objective function for all the placements
    CHECK_CU(cudaMalloc(&d_eval_result, k_num_placements * sizeof(float)));

    PlacementMapT* cur_placement_map = PlacementMapT::create_device_ptr(MAP_WIDTH, MAP_HEIGHT, nullptr);
    to_host(cur_placement_map).fill(0);

    PlacementMapT* prv_placement_map = PlacementMapT::create_device_ptr(MAP_WIDTH, MAP_HEIGHT, nullptr);
    to_host(prv_placement_map).fill(0);

    App app;
    app.set_color_map(color_map);

    float stop_threshold = 0.3f;

    for (size_t i = 0;; i++)
    {
        app.draw();

        StopWatch stop_watch{};

        // Evaluate the objective function on all the possible placements
        stop_watch.reset();

        // TODO Solution space could be reduced by trimming already occupied positions
        eval_placements<<<num_blocks, block_dim>>>(d_placements, color_map, cur_placement_map, prv_placement_map, d_eval_result);
        CHECK_CU(cudaDeviceSynchronize());

        uint64_t eval_placements_dt = stop_watch.elapsed_millis();

        // Get the placement that maximizes the objective function
        stop_watch.reset();

        std::pair<size_t, float*> max_pair = find_max_element(d_eval_result, k_num_placements);

        Placement placement = to_host(d_placements + max_pair.first);
        float max_reward = to_host(max_pair.second);
        CHECK_STATE(max_reward > 0.0f);  // If 0 it's an invalid placement!

        if (max_reward < stop_threshold) break;

        uint64_t reduce_dt = stop_watch.elapsed_millis();

        // Place the brick in the current layer
        stop_watch.reset();

        place(placement, uint16_t(i), cur_placement_map);

        uint64_t placement_dt = stop_watch.elapsed_millis();

        //
        printf("Round %zu; "
               "Placement: (%d, %d) -> %d, "
               "Value: %.3f, "
               "Eval in %" PRIu64 " ms, "
               "Reduced in %" PRIu64 " ms, "
               "Placed in: %" PRIu64 " ms\n",
               i,
               placement.m_x, placement.m_y, placement.m_brick_id,
               max_reward,
               eval_placements_dt, reduce_dt, placement_dt);

        //
        if (i % 1000 == 0) app.set_placement_map(cur_placement_map);
        //printf("  Placement added in: %" PRIu64 " ms\n", stop_watch.elapsed_millis());
    }

    printf("Done!\n");

    app.set_placement_map(cur_placement_map);

    while (!app.should_close())
    {
        app.draw();
    }

    return 0;
}
