#include "BoxFilter.hpp"

#include "gl_helpers.hpp"

using namespace lego_builder;

namespace
{
const char* k_shader_src = R"(#version 460 core

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;

uniform sampler2D u_input_texture;
layout(r8, binding = 0) uniform writeonly image2D u_output;

uniform int u_kernel_radius;

void main()
{
    ivec2 output_size = imageSize(u_output);
    if (gl_GlobalInvocationID.x >= output_size.x || gl_GlobalInvocationID.y >= output_size.y) return;

    float result = 0;
    for (int x = -u_kernel_radius; x <= u_kernel_radius; ++x)
    {
        for (int y = -u_kernel_radius; y <= u_kernel_radius; ++y)
        {
            ivec2 pos = ivec2(gl_GlobalInvocationID.xy) + ivec2(x, y);
            result += texelFetch(u_input_texture, pos, 0).r;
        }
    }
    int kernel_size = u_kernel_radius * 2 + 1;
    kernel_size *= kernel_size;
    result /= float(kernel_size);
    imageStore(u_output, ivec2(gl_GlobalInvocationID.xy), vec4(result));
}
)";
}

BoxFilter::BoxFilter()
{
    m_program = glCreateProgram();
    GLuint shader = create_shader(GL_COMPUTE_SHADER, k_shader_src);
    glAttachShader(m_program, shader);
    link_program(m_program);

    glDeleteShader(shader);

    glUseProgram(m_program);
    glUniform1i(get_uniform_location(m_program, "u_input_texture"), 0);
}

BoxFilter::~BoxFilter()
{
    glDeleteProgram(m_program);
}

void BoxFilter::run(GLuint input_texture, GLuint output_texture, int kernel_radius)
{
    int output_width, output_height;
    glBindTexture(GL_TEXTURE_2D, output_texture);
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_WIDTH, &output_width);
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_HEIGHT, &output_height);

    glUseProgram(m_program);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, input_texture);

    glBindImageTexture(0 /* binding */, output_texture, 0, false, 0, GL_WRITE_ONLY, GL_R8);

    glUniform1i(get_uniform_location(m_program, "u_kernel_radius"), kernel_radius);

    GLuint num_workgroups_x = output_width >> 5;
    GLuint num_workgroups_y = output_height >> 5;
    glDispatchCompute(num_workgroups_x, num_workgroups_y, 1);

    glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);
}
