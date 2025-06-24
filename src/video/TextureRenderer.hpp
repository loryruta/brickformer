#pragma once

#include "glad/gl.h"

namespace bf
{
class TextureRenderer
{
private:
    GLuint m_program;
    GLuint m_vao;  // Required to avoid "Array object is not active" (even if not used)

public:
    explicit TextureRenderer();
    TextureRenderer(const TextureRenderer& other) = delete;
    ~TextureRenderer();

    void render(GLuint texture);
};
}