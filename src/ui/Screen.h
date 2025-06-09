#pragma once

#include <glm/glm.hpp>

namespace lego_builder
{
class Screen
{
public:
    explicit Screen() = default;
    ~Screen() = default;

    [[nodiscard]] virtual const char* name() const = 0;

    virtual void resize(glm::ivec2 resolution) = 0;
    virtual void update(float dt) = 0;
    virtual void render() = 0;
    virtual void ui() = 0;
};
} // namespace lego_builder
