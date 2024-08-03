#pragma once

#include <glm/glm.hpp>

namespace lego_builder
{
struct BoundingBox3f
{
    glm::vec3 min;
    glm::vec3 max;

    explicit BoundingBox3f() = default;
    ~BoundingBox3f() = default;

    [[nodiscard]] glm::vec3 get_center() const { return (max - min) / 2.f; }
};
}
