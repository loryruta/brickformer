#pragma once

#include <cstdint>
#include <span>

namespace lego_builder
{
class PaidPlan
{
public:
    explicit PaidPlan() = default;
    ~PaidPlan() = default;

    /// Brick IDs available with the plan.
    virtual std::span<uint32_t> brick_ids() const = 0;
    /// Brick color IDs available with the plan.
    virtual std::span<uint32_t> brick_color_ids() const = 0;
    /// Maximum XZ resolution available with the plan.
    virtual int max_resolution() const = 0;
    /// If this plan enables to export PDF build instructions.
    virtual bool can_export_pdf() const = 0;
    /// If this plan enables to export the construction model as a .glb.
    virtual bool can_export_glb() const = 0;
    /// If this plan enables exporting bricks as .cart file (can be imported to Bricklink).
    virtual bool can_export_cart() const = 0;
};
} // namespace lego_builder
