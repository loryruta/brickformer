#pragma once

#include <glad/gl.h>

#include "Camera.hpp"
#include "GBuffer.hpp"

namespace lego_builder
{
struct SSAOTarget
{
    int width;
    int height;
    GLuint framebuffer;
    GLuint texture;

    explicit SSAOTarget(int width, int height);
    SSAOTarget(const SSAOTarget&) = delete;
    SSAOTarget(const SSAOTarget&& other) = delete; // TODO
    ~SSAOTarget();
};

struct SSAOParams
{
    glm::vec2 noise_scale;
    float radius;
    float depth_bias;
};

class SSAOPass
{
private:
    GLuint m_program;
    GLuint m_noise_texture;

public:
    static constexpr int k_noise_texture_width = 4;
    static constexpr int k_noise_texture_height = 4;
    static constexpr int k_num_samples = 64;

    explicit SSAOPass();
    SSAOPass(const SSAOPass&) = delete;
    SSAOPass(const SSAOPass&&) = delete;
    ~SSAOPass();

    void set_params(const SSAOParams& params);

    void draw(
        const GBuffer& gbuffer,
        const Camera& camera,
        const SSAOTarget& target
        );

private:
    void init_noise_texture();
    void init_kernel();
    void init_uniforms();
};
}
