#pragma once

#include <vector>

#include <glm/glm.hpp>

#include "bricks.h"
#include "lego_dataset.h"
#include "util/misc.h"

namespace bf
{
/// \brief Front-end class for accessing bricks color
class BrickColors
{
private:
    bool m_has_uploaded = false;

    std::vector<bool> m_enabled_colors;

    /// A color mask valid for all bricks which excludes disabled and disallowed colors.
    /// It is used, for example, in the Similarity Test window.
    std::vector<uint8_t /* bool */> m_color_mask_all_bricks;
    std::vector<uint8_t /* bool */> m_color_masks;

    /// An array of cardinality \c num_bricks * num_brick_colors that has a \c true value if the j-th color exists
    /// and it is usable for the i-th color.
    bool* m_color_masks_d = nullptr;

public:
    explicit BrickColors();
    BrickColors(const BrickColors&) = delete;
    BrickColors(BrickColors&&) = delete;
    ~BrickColors();

    [[nodiscard]] bool has_uploaded() const { return m_has_uploaded; }
    void upload_colors();

    [[nodiscard]] bool is_enabled(int cid) const;
    void set_enabled(int cid, bool flag);

    [[nodiscard]] const bool* color_mask_all_bricks() const
    {
        CHECK_STATE(m_has_uploaded, "Call upload_colors() first");
        return (bool*) m_color_mask_all_bricks.data();
    }

    [[nodiscard]] const bool* color_masks_d() const
    {
        CHECK_STATE(m_has_uploaded, "Call upload_colors() first");
        return m_color_masks_d;
    }

    static BrickColors& get();
};
} // namespace bf