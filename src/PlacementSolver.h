#pragma once

#include "types.cuh"

namespace lego_builder
{
namespace internal
{
    __global__ void init_placements_kernel(Placement* placements, size_t num_placements, int resolution);
    __global__ void eval_brick_size_kernel(const Placement* placements, size_t num_placements, int* out_brick_sizes);
    __global__ void eval_num_connectible_sides_kernel(const Placement* placements, size_t num_placements, int* out_num_connectible_sides);

    struct ColorMapCoverageResult
    {
        static constexpr int k_max_color_distance = 255 + 255 + 255; // Maximum Manhattan distance

        /// A value proportional to the biggest color gap covered by the placement (lower => higher color homogeneity).

        /// The biggest Manhattan distance between colors covered by the placement.
        int color_distance;
        int num_covered_cells; ///< The number of colored map cells covered by the placement.
    };

    __global__ void
    eval_color_map_coverage_kernel(const Placement* placements, size_t num_placements, ColorMapT* color_map, ColorMapCoverageResult* out_results);
    __global__ void eval_num_neighbors_kernel(const Placement* placements, size_t num_placements, PlacementMapT* current_placement_map, int* out_num_neighbors);
    __global__ void
    eval_num_connected_bricks_kernel(const Placement* placements, size_t num_placements, PlacementMapT* previous_placement_map, int* out_num_connected_bricks);
    __global__ void eval_highest_proximity_kernel(const Placement* placements, size_t num_placements, ProximityMapT* proximity_map, int* out_highest_proximity);
} // namespace internal

/// Finds the optimal placement for the given input using parallel brute force.
class PlacementSolver
{
public:
    const size_t m_num_placements;
    const int m_resolution;

    size_t m_num_blocks;
    Placement* m_placements_d; // Search space

    int* m_brick_size_d;
    int* m_num_connectible_sides_d;

    internal::ColorMapCoverageResult* m_color_map_coverage_results_d;
    int* m_num_neighbors_d;
    int* m_num_connected_bricks_d;
    int* m_highest_proximity_d;
    float* m_rewards_d;

    explicit PlacementSolver(size_t num_placements, int resolution, cudaStream_t stream);
    ~PlacementSolver();

    struct Input
    {
        bool is_subslice0;
        ColorMapT* color_map_d;
        PlacementMapT* previous_placement_map_d;
        PlacementMapT* current_placement_map_d;
        ProximityMapT* proximity_map_d;
    };

    /// \return A pair containing the optimal placement and its reward
    std::pair<Placement, float> solve(const Input& input, cudaStream_t stream);
};

namespace internal
{
    __global__ void eval_reward_kernel(const PlacementSolver* self, const PlacementSolver::Input* params, float* out_rewards);
}
} // namespace lego_builder
