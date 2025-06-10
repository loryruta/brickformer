#include "GridRenderer.hpp"

#include <bit>

#include <glm/gtc/type_ptr.hpp>

using namespace lego_builder;

// TODO: Vertices not good with backface culling!

const float k_cube_vertices[]{
    // Front
    0, 0, 0, 0, 1, std::bit_cast<float>(int(2)),
    0, 1, 0, 0, 0, std::bit_cast<float>(int(2)),
    1, 1, 0, 1, 0, std::bit_cast<float>(int(2)),
    0, 0, 0, 0, 1, std::bit_cast<float>(int(2)),
    1, 1, 0, 1, 0, std::bit_cast<float>(int(2)),
    1, 0, 0, 1, 1, std::bit_cast<float>(int(2)),
    // Back
    0, 0, 1, 0, 1, std::bit_cast<float>(int(2)),
    0, 1, 1, 0, 0, std::bit_cast<float>(int(2)),
    1, 1, 1, 1, 0, std::bit_cast<float>(int(2)),
    0, 0, 1, 0, 1, std::bit_cast<float>(int(2)),
    1, 1, 1, 1, 0, std::bit_cast<float>(int(2)),
    1, 0, 1, 1, 1, std::bit_cast<float>(int(2)),
    // Top
    0, 1, 0, 0, 1, std::bit_cast<float>(int(1)),
    0, 1, 1, 0, 0, std::bit_cast<float>(int(1)),
    1, 1, 1, 1, 0, std::bit_cast<float>(int(1)),
    0, 1, 0, 0, 1, std::bit_cast<float>(int(1)),
    1, 1, 1, 1, 0, std::bit_cast<float>(int(1)),
    1, 1, 0, 1, 1, std::bit_cast<float>(int(1)),
    // Bottom
    0, 0, 0, 0, 1, std::bit_cast<float>(int(1)),
    0, 0, 1, 0, 0, std::bit_cast<float>(int(1)),
    1, 0, 1, 1, 0, std::bit_cast<float>(int(1)),
    0, 0, 0, 0, 1, std::bit_cast<float>(int(1)),
    1, 0, 1, 1, 0, std::bit_cast<float>(int(1)),
    1, 0, 0, 1, 1, std::bit_cast<float>(int(1)),
    // Right
    1, 0, 0, 0, 1, std::bit_cast<float>(int(0)),
    1, 1, 0, 0, 0, std::bit_cast<float>(int(0)),
    1, 1, 1, 1, 0, std::bit_cast<float>(int(0)),
    1, 0, 0, 0, 1, std::bit_cast<float>(int(0)),
    1, 1, 1, 1, 0, std::bit_cast<float>(int(0)),
    1, 0, 1, 1, 1, std::bit_cast<float>(int(0)),
    // Left
    0, 0, 0, 0, 1, std::bit_cast<float>(int(0)),
    0, 1, 0, 0, 0, std::bit_cast<float>(int(0)),
    0, 1, 1, 1, 0, std::bit_cast<float>(int(0)),
    0, 0, 0, 0, 1, std::bit_cast<float>(int(0)),
    0, 1, 1, 1, 0, std::bit_cast<float>(int(0)),
    0, 0, 1, 1, 1, std::bit_cast<float>(int(0))
};

const char* k_gbuffer_vshader_src = R"(#version 460 core

    layout(location = 0) in vec3 a_position;
    layout(location = 1) in vec2 a_uv;
    layout(location = 2) in int a_axis;

    uniform vec3 u_grid_min;
    uniform vec3 u_grid_max;
    uniform mat4 u_camera;

    out vec2 v_uv;
    flat out int v_axis;

    void main()
    {
        vec3 p = a_position;

        // Transform
        p *= u_grid_max - u_grid_min;
        p += u_grid_min;

        gl_Position = u_camera * vec4(p, 1);
        v_uv = a_uv;
        v_axis = a_axis;
    }
)";

const char* k_gbuffer_fshader_src = R"(#version 460 core

    in vec2 v_uv;
    flat in int v_axis;

    uniform ivec3 u_grid_div;
    uniform float u_half_border_size;
    uniform vec3 u_color;

    layout(location = 0) out vec4 f_color;

    bool is_cell_border(float v)
    {
        return v <= u_half_border_size || v >= 1.0 - u_half_border_size;
    }

    void main()
    {
        vec3 voxel_size = 1.0 / u_grid_div;

        if (v_axis == 0)
        {
            if (is_cell_border(mod(v_uv.x, voxel_size.z) / voxel_size.z) ||
                is_cell_border(mod(v_uv.y, voxel_size.y) / voxel_size.y))
            {
                f_color = vec4(1, 0, 0, 1);
                return;
            }
        }
        else if (v_axis == 1)
        {
            if (is_cell_border(mod(v_uv.x, voxel_size.x) / voxel_size.x) ||
                is_cell_border(mod(v_uv.y, voxel_size.z) / voxel_size.z))
            {
                f_color = vec4(0, 1, 0, 1);
                return;
            }
        }
        else if (v_axis == 2)
        {
            if (is_cell_border(mod(v_uv.x, voxel_size.x) / voxel_size.x) ||
                is_cell_border(mod(v_uv.y, voxel_size.y) / voxel_size.y))
            {
                f_color = vec4(0, 0, 1, 1);
                return;
            }
        }

        discard;
    }
)";

GridRenderer::GridRenderer()
{
    m_program = glCreateProgram();

    GLuint vertex_shader = create_shader(GL_VERTEX_SHADER, k_gbuffer_vshader_src);
    glAttachShader(m_program, vertex_shader);

    GLuint fragment_shader = create_shader(GL_FRAGMENT_SHADER, k_gbuffer_fshader_src);
    glAttachShader(m_program, fragment_shader);

    link_program(m_program);

    glDeleteShader(vertex_shader);
    glDeleteShader(fragment_shader);

    create_gl_objects();

    printf("[INFO ] [GridRenderer] Ready\n");
}

GridRenderer::~GridRenderer()
{
    glDeleteProgram(m_program);

    glDeleteVertexArrays(1, &m_vao);
    glDeleteBuffers(1, &m_vbo);
}

void GridRenderer::create_gl_objects()
{
    glGenVertexArrays(1, &m_vao);
    glBindVertexArray(m_vao);

    glGenBuffers(1, &m_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, m_vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(k_cube_vertices), k_cube_vertices, GL_STATIC_DRAW);

    const size_t k_vertex_size = (3 + 2 + 1) * sizeof(float);

    int location;

    // Position
    location = get_attrib_location(m_program, "a_position");
    glEnableVertexAttribArray(location);
    glVertexAttribPointer(location, 3, GL_FLOAT, GL_FALSE, k_vertex_size, (void*) 0);

    // UV
    location = get_attrib_location(m_program, "a_uv");
    glEnableVertexAttribArray(location);
    glVertexAttribPointer(location, 2, GL_FLOAT, GL_FALSE, k_vertex_size, (void*) (3 * sizeof(float)));

    // Axis
    location = get_attrib_location(m_program, "a_axis");
    glEnableVertexAttribArray(location);
    glVertexAttribIPointer(location, 1, GL_INT, k_vertex_size, (void*) ((3 + 2) * sizeof(float)));
}

void GridRenderer::render(const RenderParams& params) const
{
    glUseProgram(m_program);

    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LESS);
    glDisable(GL_BLEND);
    glDisable(GL_CULL_FACE);

    glUniformMatrix4fv(get_uniform_location(m_program, "u_camera"), 1, GL_FALSE, glm::value_ptr(params.camera.matrix()));
    glUniform3fv(get_uniform_location(m_program, "u_grid_min"), 1, glm::value_ptr(params.min));
    glUniform3fv(get_uniform_location(m_program, "u_grid_max"), 1, glm::value_ptr(params.max));
    glUniform3iv(get_uniform_location(m_program, "u_grid_div"), 1, glm::value_ptr(params.divisions));
    glUniform1f(get_uniform_location(m_program, "u_half_border_size"), params.half_border_size);
//    glUniform3fv(get_uniform_location(m_program, "u_color"), 1, glm::value_ptr(params.color));

    glBindVertexArray(m_vao);
    glBindBuffer(GL_ARRAY_BUFFER, m_vbo);

    glDrawArrays(GL_TRIANGLES, 0, 36);
}
