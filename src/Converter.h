#pragma once

#include <filesystem>
#include <unordered_set>

#include <glm/glm.hpp>

#include "ConverterListener.h"
#include "PlacementSolver.h"
#include "Slicer.cuh"
#include "SpreadValue.h"
#include "types.cuh"

namespace lego_builder
{
struct ConverterParams {
    std::string model_path = "";
    int resolution = -1;
    bool flip_x = false;
    bool flip_y = false;
    bool flip_z = false;
    float alpha_test_threshold = 0.7f;
    uint8_t proximity_threshold =
        1; ///< If a floating placement's proximity value is below this value, then it's allowed

    /// The value to which the proximity map is initialized where voxels are set (UINT8_MAX to make it automatically
    /// assigned).
    uint8_t proximity_max_value = UINT8_MAX;
};

/// The class that manages the whole conversion process: from the raw Model to the Construction.
/// Important: this data structure must also be available in device code.
class Converter
{
public:
    /// A copy of this class' data on device.
    Converter* m_self_d; // Used to avoid having kernels with many parameters

    /* Input */
    const ConverterParams m_params;

    uint8_t m_proximity_threshold = UINT8_MAX;
    uint8_t m_proximity_max_value = UINT8_MAX;

    std::vector<ConverterListener*> m_listeners;

    /// The minimum accepted reward.
    /// If the best placement for a subslice has its reward lower than this threshold, the subslice is completed.
    float m_min_reward = 0.001f;

    size_t m_num_placements;

    bool* m_valid_placements_d; ///< Device array telling if the i-th placement is valid (optimization).

    ColorMapT m_color_map;
    ColorMapT* m_color_map_d;

    ProximityMapT m_prev_proximity_map;
    ProximityMapT* m_prev_proximity_map_d;

    PlacementMapT m_prev_placements;
    PlacementMapT* m_prev_placements_d;

    PlacementMapT m_cur_placements;
    PlacementMapT* m_cur_placements_d;

    std::unique_ptr<PlacementSolver> m_placement_solver;

    int m_slice_y;

    std::unique_ptr<Model> m_model;

    std::unique_ptr<Slicer> m_slicer;
    SpreadValue m_spread_value;

    std::unordered_set<Placement, PlacementHash> m_stacked_placements;
    std::vector<Placement> m_linear_stacked_placements;
    Placement* m_linear_stacked_placements_d = nullptr;

    /// The placement ID used for filling the Placement map.
    uint32_t m_next_pid = 0;

    bool m_stop = false;

    explicit Converter(const ConverterParams& params);
    ~Converter() = default;

    void add_listener(ConverterListener* listener) { m_listeners.emplace_back(listener); }

    void start();

    static uint8_t calc_proximity_threshold(int resolution);

    /// If unassigned, this function helps to calculate the proximity max value given the resolution.
    static uint8_t calc_proximity_max_value(int resolution);

private:
    /// Transforms the model vertices such that fits the user input grid (i.e. the Slicer space).
    /// Also applies a correction for brick height.
    void transform_model();

    /// Initializes the proximity map so that colored cells have a high value (others zero).
    void init_proximity_map_from_color_map();

    /// Writes the given placement into the current placement map.
    void place(const Placement& placement);

    size_t place_on_subslice(uint32_t slice_y, int subslice);

    /// Linearizes the placements from a hashset to linear memory (for fast iteration).
    void linearize_placements_to_output();
};

} // namespace lego_builder