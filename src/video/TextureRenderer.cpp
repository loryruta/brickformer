#include "TextureRenderer.hpp"

#include "gl_helpers.hpp"

using namespace bf;


namespace
{
const char* k_vert_shader_src = R"(#version 460 core

    out vec2 v_texcoord;

    void main()
    {
        const vec2 k_texcoords[] = vec2[](
            vec2(0.0, 0.0), // 0
            vec2(1.0, 0.0), // 1
            vec2(0.0, 1.0), // 3
            vec2(1.0, 0.0), // 1
            vec2(1.0, 1.0), // 2
            vec2(0.0, 1.0)  // 3
        );

        vec2 position = k_texcoords[gl_VertexID];
        position.y = 1.0 - position.y;
        position = position * 2.0 - 1.0;
        gl_Position = vec4(position, 0.0, 1.0);

        v_texcoord = k_texcoords[gl_VertexID];
    }
)";

const char* k_frag_shader_src = R"(#version 460 core

    in vec2 v_texcoord;

    uniform sampler2D u_texture;

    layout(location = 0) out vec4 f_color;

    void main()
    {
        f_color = texture(u_texture, v_texcoord);
    }
)";
}  // namespace

TextureRenderer::TextureRenderer()
{
    m_program = glCreateProgram();

    GLuint vert_shader = create_shader(GL_VERTEX_SHADER, k_vert_shader_src);
    GLuint frag_shader = create_shader(GL_FRAGMENT_SHADER, k_frag_shader_src);

    glAttachShader(m_program, vert_shader);
    glAttachShader(m_program, frag_shader);

    link_program(m_program);

    glDeleteShader(vert_shader);
    glDeleteShader(frag_shader);

    glGenVertexArrays(1, &m_vao);
}

TextureRenderer::~TextureRenderer()
{
    glDeleteVertexArrays(1, &m_vao);
    glDeleteProgram(m_program);
}

void TextureRenderer::render(GLuint texture)
{
    glDisable(GL_DEPTH_TEST);

    glUseProgram(m_program);

    glBindVertexArray(m_vao);
    glBindTexture(GL_TEXTURE_2D, texture);

    glDrawArrays(GL_TRIANGLES, 0, 6);
}
