#pragma once

#include "model/Model.h"
#include "types.h"

namespace bf
{
class ConverterListener
{
public:
    explicit ConverterListener() = default;
    ~ConverterListener() = default;

    /// Function invoked when the model has loaded.
    virtual void on_model_load(const Model& model) = 0;
    /// Function invoked when placement starts for \c slice_y (before all sub-slices).
    virtual void on_placement_begin(uint32_t slice_y) = 0;
    /// Function invoked at every winner placement for a \b subslice (placements not stacked yet).
    virtual void on_place(uint32_t slice_y, const Placement& placement, float reward) = 0;
    /// Function invoked when placement ends for \c slice_y (after all sub-slices and stacking).
    virtual void on_placement_end(uint32_t slice_y, const std::vector<Placement>& placements) = 0;
};
} // namespace bf