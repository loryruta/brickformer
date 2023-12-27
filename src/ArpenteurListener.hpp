#pragma once

#include "types.hpp"

namespace lego_builder
{
class ArpenteurListener
{
public:
    explicit ArpenteurListener() = default;
    ~ArpenteurListener() = default;

    virtual void on_place(uint32_t slice_y, const Placement& placement, float reward) {}

    virtual void on_slice_end(uint32_t slice_y);
};
} // namespace lego_builder