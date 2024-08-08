#pragma once

#include <cstdint>

#include "DeviceImage.cuh"

namespace lego_builder
{

/// A struct representing a placement within a slice: (x, y) and brick ID (= bid).
struct Placement
{
    uint8_t m_bid;
    uint8_t m_x;
    uint8_t m_y;
    uint8_t _pad;  // Autistic padding to 32bit

    struct {
        bool is_outside;
        bool is_overlapping;
        int num_covered_map_cells;
        int brick_size;
        int num_neighbors;
        int num_connectible_sides;
        int num_connected_bricks;
    } computed;

    bool operator==(const Placement& other) const
    {
        return m_bid == other.m_bid && m_x == other.m_x && m_y == other.m_y;
    }
};

struct PlacementHash  // Used for stacking placements
{
    size_t operator()(const Placement& key) const
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

/// A placement with exact information about its location within the slice (e.g. the subslice; possibly stacked), and
/// the color.
struct ColoredPlacement
{
    Placement m_placement;
    uint8_t m_subslice_mask;
    glm::vec<4, uint8_t> m_color;
};

}  // namespace lego_builder
