#include "ScreenQuad.hpp"

#include "gl_helpers.hpp"

using namespace lego_builder;

namespace
{
const float k_vertices[]{
    0.0f, 0.0f,
    0.0f, 1.0f,
    1.0f, 1.0f,
    0.0f, 0.0f,
    1.0f, 1.0f,
    1.0f, 0.0f,
};

const char* k_vertex_shader_src = R"(#version 460 core
in vec2 a_position;

layout(location = 0) out vec2 v_uv;

void main()
{
    gl_Position = vec4(a_position * 2 - 1, 0, 1);
    v_uv = a_position;
}
)";
} // namespace

ScreenQuad::ScreenQuad()
{
    glGenVertexArrays(1, &m_vao);
    glBindVertexArray(m_vao);

    glGenBuffers(1, &m_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, m_vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(k_vertices), k_vertices, GL_STATIC_DRAW);

    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(float), 0);

    m_vertex_shader = create_shader(GL_VERTEX_SHADER, k_vertex_shader_src);
}

void ScreenQuad::draw() const
{
    glBindVertexArray(m_vao);
    glBindBuffer(GL_ARRAY_BUFFER, m_vbo);

    glDrawArrays(GL_TRIANGLES, 0, 6);
}
