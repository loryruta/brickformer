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

    virtual void on_model_load(const Model& model) {};

    virtual void on_placement_begin(uint32_t slice_y) {};

    virtual void on_place(uint32_t slice_y, const Placement& placement, float reward) {};

    virtual void on_placement_end(uint32_t slice_y) {};
};
} // namespace lego_builder