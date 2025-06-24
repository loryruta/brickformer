#pragma once

#include <memory>

#include <glad/gl.h>

#include "Camera.hpp"

namespace bf
{
class BrickPlaneRenderer
{
private:
    GLuint m_program;
    GLuint m_brick_texture;

public:
    explicit BrickPlaneRenderer();
    ~BrickPlaneRenderer();

    void render(float y, const Camera& camera, float border_r);

private:
    void create_brick_texture();
};
} // namespace bf
