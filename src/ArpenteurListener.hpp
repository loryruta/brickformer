#pragma once

#include "model/Model.hpp"
#include "types.cuh"

namespace lego_builder
{
class ArpenteurListener
{
public:
    explicit ArpenteurListener() = default;
    ~ArpenteurListener() = default;

    /// Function invoked when the model has loaded.
    virtual void on_model_load(const Model& model) {};
    /// Function invoked when placement starts for \c slice_y (before all sub-slices).
    virtual void on_placement_begin(uint32_t slice_y) {};
    /// Function invoked at every winner placement for a \b subslice.
    // TODO not really what I wanted, it doesn't account for stacked placements
    virtual void on_place(uint32_t slice_y, const Placement& placement, float reward) {};
    /// Function invoked when placement ends for \c slice_y (after all sub-slices and compaction).
    virtual void on_placement_end(uint32_t slice_y, const std::vector<Placement>& placements) {};
};
} // namespace lego_builder