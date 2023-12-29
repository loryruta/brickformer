#pragma once

#include <functional>

#include <glad/gl.h>

namespace lego_builder
{
struct CustomFramebuffer
{
    uint32_t m_width, m_height;

    GLuint m_framebuffer;
    GLuint m_texture;
    GLuint m_renderbuffer;

    explicit CustomFramebuffer(uint32_t width, uint32_t height);
    CustomFramebuffer(const CustomFramebuffer&) = delete;
    CustomFramebuffer(CustomFramebuffer&&) = default;
    ~CustomFramebuffer();

    void render(const std::function<void()>& render_func) const;
};
}