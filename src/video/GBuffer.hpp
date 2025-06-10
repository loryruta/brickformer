#pragma once

#include <glad/gl.h>

namespace lego_builder
{
class GBuffer
{
private:
    int m_width;
    int m_height;

    GLuint m_framebuffer;
    GLuint m_depth_buffer;

    GLuint m_position_texture;
    GLuint m_normal_texture;
    GLuint m_albedo_texture;

public:
    explicit GBuffer(int width, int height);
    GBuffer(const GBuffer&) = delete;
    GBuffer(const GBuffer&&) = delete; // TODO
    ~GBuffer();

    [[nodiscard]] int width() const { return m_width; }
    [[nodiscard]] int height() const { return m_height; }

    [[nodiscard]] GLuint depth_buffer() const { return m_depth_buffer; }
    [[nodiscard]] GLuint framebuffer() const { return m_framebuffer; }

    [[nodiscard]] GLuint position_texture() const { return m_position_texture; }
    [[nodiscard]] GLuint normal_texture() const { return m_normal_texture; }
    [[nodiscard]] GLuint albedo_texture() const { return m_albedo_texture; }

    void clear();
};
} // namespace lego_builder
