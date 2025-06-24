#pragma once

#include <cstdint>
#include <unordered_set>

#include "lego_dataset.h"

namespace lego_builder
{
class PaidPlan
{
public:
    explicit PaidPlan() = default;
    virtual ~PaidPlan() = default;

    [[nodiscard]] virtual std::string name() const = 0;
    /// Check whether the given Brick Color ID (cid) is allowed by the plan.
    [[nodiscard]] virtual bool is_brick_color_allowed(int cid) const = 0;
    /// Check whether the given XZ resolution is allowed by the plan.
    [[nodiscard]] virtual bool is_resolution_allowed(int resolution) const = 0;
};

/// \brief Free plan
class FreePlan : public PaidPlan
{
public:
    [[nodiscard]] std::string name() const override { return "Free"; }

    [[nodiscard]] bool is_brick_color_allowed(int cid) const override
    {
        static const std::unordered_set<int> k_allowed_lego_color_ids = {
            26,  // Black
            23,  // Blue
            28,  // Green
            107, // Dark Turquoise
            21,  // Red
            25,  // Brown
            2,   // Light Gray
            27,  // Dark Gray
            37,  // Bright Green
            9,   // Pink
            24,  // Yellow
            1,   // White
            5,   // Tan
            104, // Purple
            106, // Orange
            102, // Medium Blue
            18,  // Nougat
            118, // Aqua
            140, // Dark Blue
            141, // Dark Green
            308, // Dark Brown
            154, // Dark Red
            321, // Dark Azure
        };
        return k_allowed_lego_color_ids.contains(k_brick_colors[cid].lego_id);
    }

    [[nodiscard]] bool is_resolution_allowed(int resolution) const override { return resolution <= 40; }
};

/// \brief Premium plan
class PremiumPlan : public PaidPlan
{
public:
    [[nodiscard]] std::string name() const override { return "Premium"; }

    [[nodiscard]] bool is_brick_color_allowed(int cid) const override { return true; }

    [[nodiscard]] bool is_resolution_allowed(int resolution) const override { return true; }
};

/*
 * Singletons
 */

// clang-format off
inline FreePlan    s_plan_free;
inline PremiumPlan s_plan_premium;
// clang-format on

} // namespace lego_builder
