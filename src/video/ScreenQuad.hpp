#pragma once

#include <memory>

#include <glad/gl.h>

namespace lego_builder
{
class ScreenQuad
{
private:
    inline static std::unique_ptr<ScreenQuad> s_instance;

    GLuint m_vao;
    GLuint m_vbo;
    GLuint m_vertex_shader;

public:
    explicit ScreenQuad();
    ScreenQuad(const ScreenQuad&) = delete;
    ScreenQuad(const ScreenQuad&&) = delete; // TODO
    ~ScreenQuad() = default;

    [[nodiscard]] GLuint get_vertex_shader() const { return m_vertex_shader; }

    void draw() const;

    static ScreenQuad& get()
    {
        if (!s_instance) s_instance = std::make_unique<ScreenQuad>();
        return *s_instance;
    }
};
}
