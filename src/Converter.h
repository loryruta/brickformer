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
    bool use_subslices = false;
    float alpha_test_threshold = 0.7f;
    uint8_t proximity_threshold =
        1; ///< If a floating placement's proximity value is below this value, then it's allowed

    /// The value to which the proximity map is initialized where voxels are set (UINT8_MAX to make it automatically
    /// assigned).
    uint8_t proximity_max_value = UINT8_MAX;
};

struct CUDAStopwatch {
private:
    cudaEvent_t m_start;
    cudaEvent_t m_stop;

public:
    explicit CUDAStopwatch()
    {
        CHECK_CU(cudaEventCreate(&m_start));
        CHECK_CU(cudaEventCreate(&m_stop));
    }
    CUDAStopwatch(const CUDAStopwatch&) = delete;
    CUDAStopwatch(CUDAStopwatch&&) = delete;
    ~CUDAStopwatch()
    {
        CHECK_CU(cudaEventDestroy(m_start));
        CHECK_CU(cudaEventDestroy(m_stop));
    }

    void start(cudaStream_t stream) { CHECK_CU(cudaEventRecord(m_start, stream)); }
    void stop(cudaStream_t stream) { CHECK_CU(cudaEventRecord(m_stop, stream)); }
    float pull_sync()
    {
        if (cudaEventSynchronize(m_stop) != cudaSuccess) {
            float dt_ms;
            CHECK_CU(cudaEventElapsedTime(&dt_ms, m_start, m_stop));
            return dt_ms;
        } else {
            return -1.0f;
        }
    }
};

struct MeasurementSeries {
    double min_ = std::numeric_limits<double>::max();
    double max_ = std::numeric_limits<double>::min();
    double sum = 0.0;
    size_t count = 0;

    void add(double measure)
    {
        min_ = std::min(measure, min_);
        max_ = std::max(measure, max_);
        sum += measure;
        ++count;
    }

    [[nodiscard]] double avg() const { return sum / double(count); }
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
    cudaStream_t m_stream;

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
    int m_num_slices;

    std::unique_ptr<Slicer> m_slicer;
    SpreadValue m_spread_value;

    std::unordered_set<Placement, PlacementHash> m_stacked_placements;
    std::vector<Placement> m_linear_stacked_placements;

    /// The placement ID used for filling the Placement map.
    uint32_t m_next_pid = 0;

    bool m_stop = false;

    /* Performance Stats */
    struct {
        MeasurementSeries voxelization_dt;
        MeasurementSeries subslice_dt[3];
        MeasurementSeries subslice_solve_placement_dt[3];
        MeasurementSeries spread_proximity_map_dt;
        MeasurementSeries color_placements_dt;
    } m_stats;

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

    size_t place_on_subslice(uint32_t slice_y, int subslice);

    /// Linearize the placements from a hashset to linear memory.
    void linearize_placements();
    void color_placements();
};

} // namespace lego_builder