#pragma once

#include <cstdint>

#include "DeviceImage.h"

#define ARP_NO_PLACEMENT_VALUE uint16_t(UINT16_MAX)

namespace bf
{

/// A struct representing a placement within a slice.
struct Placement {
    /* Keys */
    uint8_t bid; ///< The Brick Index to bricks.hpp
    uint8_t x;   ///< The X coordinate of the brick's top-left corner within the slice
    uint8_t z;   ///< The Z coordinate of the brick's top-left corner within the slice

    mutable uint8_t cid = UINT8_MAX;
    /// 3 bits bitmask; if i-th is set, this placement occupies the i-th subslice (out of 3)
    mutable uint8_t subslice_mask = UINT8_MAX;

    bool operator==(const Placement& other) const { return bid == other.bid && x == other.x && z == other.z; }

    bool is_subslice() const { return subslice_mask & 0x7; }
    bool is_full() const { return !is_subslice(); }
};

struct PlacementHash // Used for stacking placements
{
    uint64_t operator()(const Placement& key) const
    {
        uint32_t hash = 0;
        hash |= key.bid;
        hash |= key.x << 8;
        hash |= key.z << 16;
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

} // namespace bf
