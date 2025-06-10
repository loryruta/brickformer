#pragma once

#include <memory>

#include <glad/gl.h>

#include "Camera.hpp"
#include "GBuffer.hpp"
#include "model/Model.hpp"

namespace lego_builder
{
struct BrickRenderer_BakedModel {
    GLuint vao;
    GLuint vbo;
    uint32_t num_vertices;
};

struct BrickRenderer_GBuffer {
    const int width;
    const int height;

    GLuint framebuffer;
    GLuint color_texture;
    GLuint uv_texture;
    GLuint outline_guide_texture;
    GLuint depth_buffer;

    explicit BrickRenderer_GBuffer(int width, int height);
    BrickRenderer_GBuffer(const BrickRenderer_GBuffer&) = delete;
    BrickRenderer_GBuffer(BrickRenderer_GBuffer&&) noexcept = delete; // TODO
    ~BrickRenderer_GBuffer();

    void clear();
};

struct BrickRenderer_RenderParams {
    BrickRenderer_BakedModel* baked_model;
    Camera* camera;
    int kernel_r;
    glm::vec4 border_color;
};

class BrickRenderer
{
private:
    GLuint m_gbuffer_program;
    GLuint m_color_program;
    std::unique_ptr<BrickRenderer_GBuffer> m_gbuffer;

public:
    explicit BrickRenderer();
    ~BrickRenderer();

    void render(const BrickRenderer_RenderParams& params);

    static BrickRenderer_BakedModel bake_model(const Model& model);
};
} // namespace lego_builder
