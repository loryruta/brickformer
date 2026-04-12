#pragma once

#include <cstdint>

#include "DeviceImage.cuh"

#define ARP_NO_PLACEMENT_VALUE uint16_t(UINT16_MAX)

namespace lego_builder
{

/// A struct representing a placement within a slice: (x, y) and brick ID (= bid).
struct Placement
{
    /* Keys */
    uint8_t m_bid; ///< The Brick Index to bricks.hpp
    uint8_t m_x;   ///< The X coordinate of the brick's top-left corner within the slice
    uint8_t m_y;   ///< The Y coordinate of the brick's top-left corner within the slice
    // TODO rename m_y to m_z please

    mutable uint8_t m_cid = UINT8_MAX;           ///< The Color Index to brick_colors.hpp
    mutable uint8_t m_subslice_mask = UINT8_MAX; ///< 3 bits bitmask; if i-th is set, this placement occupies the i-th subslice (out of 3)

    bool operator==(const Placement& other) const { return m_bid == other.m_bid && m_x == other.m_x && m_y == other.m_y; }
};

struct PlacementHash // Used for stacking placements
{
    uint64_t operator()(const Placement& key) const
    {
        uint32_t hash = 0;
        hash |= key.m_bid;
        hash |= key.m_x << 8;
        hash |= key.m_y << 16;
        return hash;
    }
};

/// The color map is the output of the slicing process: a 2D slice (fixed Y) of model voxels.
using ColorMapT = DeviceImage<4, uint8_t>;

/// The proximity map is an image where every pixel indicates the proximity to colored pixels of the color map.
/// The higher is the value, the nearer are the colored pixels. Used during placement evaluation (detect floating
/// placements).
using ProximityMapT = DeviceImage<1, uint8_t>;

/// The placement map is an image where pixels with the same value correspond to the same placement. Pixel ID is
/// meaningless and only useful to identify the occupied region.
using PlacementMapT = DeviceImage<1, uint16_t>;

} // namespace lego_builder
