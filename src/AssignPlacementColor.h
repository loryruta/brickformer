#pragma once

#include "types.h"

namespace bf
{
class AssignPlacementColor
{
public:
    __host__ __device__ static int search_nearest_cid(const glm::vec3& query_color, const bool* color_mask);

    static void
    assign(const ColorMapT& color_map, Placement* placements, size_t num_placements, const bool* color_masks);

private:
    explicit AssignPlacementColor() = default;
    ~AssignPlacementColor() = default;
};

} // namespace bf