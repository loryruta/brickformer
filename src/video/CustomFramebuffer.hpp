#pragma once

#include <functional>

#include "glad/gl.h"

namespace lego_builder
{
class CustomFramebuffer
{
private:
    int m_width, m_height;
    float m_aspect_ratio;

    GLuint m_framebuffer;
    GLuint m_texture;
    GLuint m_renderbuffer;

public:
    explicit CustomFramebuffer(int width, int height);
    CustomFramebuffer(const CustomFramebuffer&) = delete;
    CustomFramebuffer(CustomFramebuffer&&) = default;
    ~CustomFramebuffer();

    [[nodiscard]] int get_width() const { return m_width; }
    [[nodiscard]] int get_height() const { return m_height; }
    [[nodiscard]] float get_aspect_ratio() const { return m_aspect_ratio; }

    [[nodiscard]] GLuint get_framebuffer() const { return m_framebuffer; }
    [[nodiscard]] GLuint get_texture() const { return m_texture; }

    using RenderFuncT = std::function<void()>;
    void render(const RenderFuncT& render_func) const;
};
}
