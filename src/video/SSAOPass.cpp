#include "SSAOPass.hpp"

#include <random>
#include <vector>

#include <glm/gtc/type_ptr.hpp>

#include "gl_helpers.hpp"
#include "ScreenQuad.hpp"
#include "util/misc.hpp"

using namespace lego_builder;

namespace
{
const char* k_ssao_shader_src = R"(#version 460 core

    const uint k_kernel_size = 64;

    layout(location = 0) in vec2 v_uv;

    // GBuffer
    uniform sampler2D u_position;
    uniform sampler2D u_normal;

    uniform sampler2D u_noise_texture;
    uniform vec3 u_kernel[k_kernel_size];

    uniform mat4 u_projection;

    // Parameters
    uniform vec2 u_noise_scale;
    uniform float u_radius;
    uniform float u_depth_bias;

    layout(location = 0) out float f_occlusion;

    void main()
    {
        vec3 position = texture(u_position, v_uv).rgb;
        vec3 normal = normalize(texture(u_normal, v_uv).rgb);

        vec3 random_vector = normalize(texture(u_noise_texture, v_uv * u_noise_scale).xyz);
        vec3 tangent = normalize(random_vector - normal * dot(random_vector, normal));
        vec3 bitangent = cross(normal, tangent);
        mat3 TBN = mat3(tangent, bitangent, normal);

        float occlusion = 0.0;
        for (int i = 0; i < k_kernel_size; ++i)
        {
            // Find sample position in view space
            vec3 sample_dir = TBN * u_kernel[i];
            vec3 sample_pos = position + sample_dir * u_radius;

            // Project the sample
            vec4 sample_uv = vec4(sample_pos, 1.0);
            sample_uv = u_projection * sample_uv;       // View space to Clip space
            sample_uv /= sample_uv.w;                   // Clip space to Screen space
            sample_uv.xyz = sample_uv.xyz * 0.5 + 0.5;  // Convert to 0.0 - 1.0 range

            float sample_depth = texture(u_position, sample_uv.xy).z;
            occlusion += sample_depth <= sample_pos.z + u_depth_bias ? 1.0 : 0.0;
        }
        occlusion /= float(k_kernel_size);

        f_occlusion = 1.0 - occlusion;
    }
)";

std::default_random_engine g_generator{};
std::uniform_real_distribution<GLfloat> g_random_float(0.0, 1.0);
}

SSAOTarget::SSAOTarget(int width, int height) :
    width(width),
    height(height)
{
    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);

    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_R32F, width, height, 0, GL_RED, GL_FLOAT, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);

    GLenum framebuffer_status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (framebuffer_status != GL_FRAMEBUFFER_COMPLETE)
    {
        printf("[ERROR] [SSAOTarget] Invalid framebuffer status: %d\n", framebuffer_status);
        CHECK_STATE(!(framebuffer_status != GL_FRAMEBUFFER_COMPLETE));
    }
}

SSAOTarget::~SSAOTarget()
{
    glDeleteFramebuffers(1, &framebuffer);
    glDeleteTextures(1, &texture);
}

SSAOPass::SSAOPass()
{
    GLuint fragment_shader = create_shader(GL_FRAGMENT_SHADER, k_ssao_shader_src);

    m_program = glCreateProgram();
    glAttachShader(m_program, ScreenQuad::get().get_vertex_shader());
    glAttachShader(m_program, fragment_shader);
    link_program(m_program);

    init_noise_texture();
    init_kernel();
    init_uniforms();

    // Parameters obtained out of experiments
    SSAOParams params{};
    params.noise_scale = {1920.f / 4.f, 1080.f / 4.f};
    params.radius = 0.5f;
    params.depth_bias = 0.001f;
    set_params(params);
}

SSAOPass::~SSAOPass()
{
    glDeleteProgram(m_program);
}

void SSAOPass::set_params(const SSAOParams& params)
{
    glUseProgram(m_program);
    glUniform1f(get_uniform_location(m_program, "u_radius"), params.radius);
    glUniform1f(get_uniform_location(m_program, "u_depth_bias"), params.depth_bias);
    // TODO kernel size ???
}

void SSAOPass::draw(const GBuffer& gbuffer, const Camera& camera, const SSAOTarget& target)
{
    glBindFramebuffer(GL_FRAMEBUFFER, target.framebuffer);
    glViewport(0, 0, target.width, target.height);

    glClear(GL_COLOR_BUFFER_BIT);

    glDisable(GL_DEPTH_TEST);
    glDisable(GL_BLEND);

    glUseProgram(m_program);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, gbuffer.get_position_texture());
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, gbuffer.get_normal_texture());
    glActiveTexture(GL_TEXTURE2);
    glBindTexture(GL_TEXTURE_2D, m_noise_texture);

    glm::vec2 noise_scale{};
    noise_scale.x = float(target.width) / k_noise_texture_width;
    noise_scale.y = float(target.height) / k_noise_texture_height;
    glUniform2fv(get_uniform_location(m_program, "u_noise_scale"), 1, glm::value_ptr(noise_scale));

    glUniformMatrix4fv(get_uniform_location(m_program, "u_projection"), 1, GL_FALSE, glm::value_ptr(camera.projection()));

    ScreenQuad::get().draw();
}

void SSAOPass::init_noise_texture()
{
    static constexpr int k_noise_texture_size = k_noise_texture_width * k_noise_texture_height;

    std::vector<glm::vec3> noise_data(k_noise_texture_size);
    for (int i = 0; i < k_noise_texture_size; i++)
    {
        noise_data[i].x = g_random_float(g_generator) * 2.f - 1.f;
        noise_data[i].y = g_random_float(g_generator) * 2.f - 1.f;
        noise_data[i].z = 0.f;
    }

    glGenTextures(1, &m_noise_texture);
    glBindTexture(GL_TEXTURE_2D, m_noise_texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, k_noise_texture_width, k_noise_texture_height, 0, GL_RGB, GL_FLOAT, noise_data.data());
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
}

void SSAOPass::init_kernel()
{
    glUseProgram(m_program);

    for (int i = 0; i < k_num_samples; ++i)
    {
        glm::vec3 sample{};
        sample.x = g_random_float(g_generator) * 2.f - 1.f;
        sample.y = g_random_float(g_generator) * 2.f - 1.f;
        sample.z = g_random_float(g_generator);
        sample = glm::normalize(sample);
        sample *= g_random_float(g_generator);
        float scale = float(i) / float(k_num_samples);
        scale = 0.1f + (scale * scale) * 0.9f;
        sample *= scale;
        glUniform3fv(get_uniform_location(m_program, "u_kernel[" + std::to_string(i) + "]"), 1, glm::value_ptr(sample));
    }
}

void SSAOPass::init_uniforms()
{
    glUniform1i(get_uniform_location(m_program, "u_position"), 0);
    glUniform1i(get_uniform_location(m_program, "u_normal"), 1);
    glUniform1i(get_uniform_location(m_program, "u_noise_texture"), 2);
}
