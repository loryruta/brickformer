#pragma once

#include <filesystem>
#include <unordered_map>

#include <glm/glm.hpp>

#include "ArpenteurListener.hpp"
#include "Slicer.cuh"
#include "SpreadValue.cuh"
#include "types.cuh"

namespace lego_builder
{

/// The class that manages the whole conversion process: from the raw Model to the Construction.
/// Important: this data structure must also be available in device code.
class Arpenteur  // Arpenteur in French = Surveyor in English (= Geometra in Italian)
{
public:
    /// A copy of this class' data on device.
    Arpenteur* m_self_d;  // Used to avoid having kernels with many parameters

    std::string m_model_path;
    uint32_t m_slice_side;
    ArpenteurListener* m_listener;

    uint8_t m_proximity_threshold = 1;  ///< If floating placement proximity is below this value, then it's allowed

    /// The minimum accepted reward.
    /// If the best placement for a subslice has its reward lower than this threshold, the subslice is completed.
    float m_min_reward = 0.3f;

    size_t m_num_placements;

    Placement* m_placements_d;  ///< Device array containing all possible placements.
    float* m_rewards_d;         ///< Device array of rewards, each corresponding to a placement.

    bool* m_valid_placements_d;  ///< Device array telling if the i-th placement is valid (optimization).

    ColorMapT m_color_map;
    ColorMapT* m_color_map_d;

    ProximityMapT m_prev_proximity_map;
    ProximityMapT* m_prev_proximity_map_d;

    PlacementMapT m_prev_placements;
    PlacementMapT* m_prev_placements_d;

    PlacementMapT m_cur_placements;
    PlacementMapT* m_cur_placements_d;

    int m_slice_y;

    std::unique_ptr<Model> m_model;

    std::unique_ptr<Slicer> m_slicer;
    SpreadValue m_spread_value;

    std::unordered_map<Placement, uint8_t, PlacementHash> m_stacked_placements;

    const size_t k_max_colored_placements = 1024 * 1024;  // >1MB
    std::vector<ColoredPlacement> m_colored_placements;
    ColoredPlacement* m_colored_placements_d;

    /// The placement ID used for filling the Placement map.
    uint32_t m_next_pid = 0;

    explicit Arpenteur(const std::filesystem::path& model_path, uint32_t slice_side, ArpenteurListener& listener);

    // @param model_path valid path to the input model
    // @param grid the grid that the model has to fit in. "Slice side" would be a sufficient input, but 3D grid is more user-friendly
    //explicit Arpenteur(const std::filesystem::path& model_path, const glm::uvec3& grid); // TODO :)

    ~Arpenteur() = default;

    void run();

    void init_placements();  // TODO should be private but error...

private:
    /// Transforms the model vertices such that fits the user input grid (i.e. the Slicer space).
    /// Also applies a correction for brick height.
    void transform_model();

    /// Initializes the proximity map so that colored cells have a high value (others zero).
    void init_proximity_map_from_color_map();

    template<uint32_t SUBSLICE>
    std::pair<Placement, float> compute_next_placement();

    /// Writes the given placement into the current placement map.
    void place(const Placement& placement);

    template<uint32_t SUBSLICE>
    size_t place_on_subslice(uint32_t slice_y);

    /// Linearizes the placements list (for faster iteration), and colorizes them according to the Color map.
    void linearize_and_colorize();
};

}