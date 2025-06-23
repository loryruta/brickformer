#include "BrickRenderer.h"

#include <glm/gtc/type_ptr.hpp>

#include "ScreenQuad.hpp"
#include "gl_helpers.hpp"
#include "log.hpp"
#include "util/misc.hpp"

#define ARP_LOG_CONTEXT "BrickRenderer"

using namespace lego_builder;

namespace
{
const char* k_gbuffer_vshader_src = R"(#version 460 core

    layout(location = 0) in vec3 a_position;
    layout(location = 1) in vec3 a_normal;
    layout(location = 2) in vec2 a_uv;
    layout(location = 3) in vec4 a_color;
    layout(location = 4) in uvec2 a_outline_guide;

    layout(location = 0) uniform mat4 u_transform;
    layout(location = 1) uniform mat4 u_view;
    layout(location = 2) uniform mat4 u_projection;

    out vec4 v_color;
    out vec2 v_uv;
    out flat uvec2 v_outline_guide;

    void main()
    {
        mat4 VT = u_view * u_transform;
        vec4 normal = VT * vec4(a_normal, 0);

        v_color = a_color;
        v_uv = a_uv;
        v_outline_guide = a_outline_guide;

        gl_Position = u_projection * VT * vec4(a_position, 1);
    }
)";

const char* k_gbuffer_fshader_src = R"(#version 460 core

    in vec4 v_color;
    in vec2 v_uv;
    in flat uvec2 v_outline_guide;

    layout(location = 0) out vec4 f_color;
    layout(location = 1) out vec2 f_uv;
    layout(location = 2) out uvec2 f_outline_guide;

    void main()
    {
        f_color = v_color;
        f_uv = v_uv;
        f_outline_guide = v_outline_guide;
    }
)";

const char* k_color_fshader_src = R"(#version 460 core

    layout(location = 0) in vec2 v_uv;

    // GBuffer
    layout(binding = 0, rgba8) uniform image2D u_color;
    layout(binding = 1, rg8) uniform image2D u_uv;
    layout(binding = 2, rg32ui) uniform uimage2D u_outline_guide;
    uniform sampler2D u_depth_buffer;

    layout(location = 0) uniform int u_kernel_r;
    layout(location = 1) uniform vec4 u_border_color;

    layout(location = 0) out vec4 f_color;

    void main()
    {
        ivec2 resolution = imageSize(u_color);
        ivec2 coord = ivec2(v_uv * resolution);
        vec2 uv = imageLoad(u_uv, coord).rg;
        uvec2 outline_guide = imageLoad(u_outline_guide, coord).rg;
        float depth = texture(u_depth_buffer, v_uv).r; // Can't use imageLoad
        if (outline_guide.r /* pid */ == 0) {
            discard;
            return;
        }
        gl_FragDepth = depth;
        for (int x = -u_kernel_r; x <= u_kernel_r; ++x) {
            for (int y = -u_kernel_r; y <= u_kernel_r; ++y) {
                ivec2 neighbor_coord = coord + ivec2(x, y);
                uvec2 neighbor_outline_guide = imageLoad(u_outline_guide, neighbor_coord).rg;
                if (outline_guide != neighbor_outline_guide) {
                    f_color = u_border_color;
                    return;
                }
            }
        }
        vec4 color = imageLoad(u_color, coord);
        f_color = color;
    }
)";
} // namespace

BrickRenderer_BakedModel::BrickRenderer_BakedModel(BrickRenderer_BakedModel&& other) noexcept
    : vao(other.vao), vbo(other.vbo), num_vertices(other.num_vertices)
{
    other.vao = 0;
    other.vbo = 0;
}

BrickRenderer_BakedModel::~BrickRenderer_BakedModel()
{
    if (vao) glDeleteVertexArrays(1, &vao);
    if (vbo) glDeleteBuffers(1, &vbo);
}

BrickRenderer_BakedModel& BrickRenderer_BakedModel::operator=(BrickRenderer_BakedModel&& other) noexcept
{
    vao = other.vao;
    vbo = other.vbo;
    num_vertices = other.num_vertices;
    other.vao = 0;
    other.vbo = 0;
    return *this;
}

BrickRenderer_GBuffer::BrickRenderer_GBuffer(int width, int height) : width(width), height(height)
{
    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);

    // Color attachment
    glGenTextures(1, &color_texture);
    glBindTexture(GL_TEXTURE_2D, color_texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, color_texture, 0);
    ARP_DEBUG("Color attachment created");

    // UV attachment
    glGenTextures(1, &uv_texture);
    glBindTexture(GL_TEXTURE_2D, uv_texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RG8, width, height, 0, GL_RG, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT1, GL_TEXTURE_2D, uv_texture, 0);
    ARP_DEBUG("UV attachment created");

    // Outline guide attachment
    glGenTextures(1, &outline_guide_texture);
    glBindTexture(GL_TEXTURE_2D, outline_guide_texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RG32UI, width, height, 0, GL_RG_INTEGER, GL_UNSIGNED_INT, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT2, GL_TEXTURE_2D, outline_guide_texture, 0);
    ARP_DEBUG("Outline guide attachment created");

    GLenum attachments[]{GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1, GL_COLOR_ATTACHMENT2};
    glDrawBuffers(std::size(attachments), attachments);

    // Depthbuffer
    glGenTextures(1, &depth_buffer);
    glBindTexture(GL_TEXTURE_2D, depth_buffer);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT32F, width, height, 0, GL_DEPTH_COMPONENT, GL_FLOAT, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, depth_buffer, 0);
    ARP_DEBUG("Depthbuffer created");

    GLenum framebuffer_status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    CHECK_STATE(framebuffer_status == GL_FRAMEBUFFER_COMPLETE, "Framebuffer not complete: %d", framebuffer_status);

    ARP_DEBUG("Framebuffer created; Resolution: (%d, %d)", width, height);

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

BrickRenderer_GBuffer::~BrickRenderer_GBuffer()
{
    glDeleteTextures(1, &color_texture);
    glDeleteTextures(1, &uv_texture);
    glDeleteTextures(1, &outline_guide_texture);
    glDeleteTextures(1, &depth_buffer);
    glDeleteFramebuffers(1, &framebuffer);
}

void BrickRenderer_GBuffer::clear()
{
    glClearTexImage(color_texture, 0, GL_RGBA, GL_FLOAT, nullptr);
    glClearTexImage(uv_texture, 0, GL_RG, GL_FLOAT, nullptr);
    glClearTexImage(outline_guide_texture, 0, GL_RG_INTEGER, GL_UNSIGNED_INT, nullptr);
}

BrickRenderer::BrickRenderer()
{
    /* GBuffer program */
    {
        m_gbuffer_program = glCreateProgram();
        GLuint gbuffer_vshader = create_shader(GL_VERTEX_SHADER, k_gbuffer_vshader_src);
        GLuint gbuffer_fshader = create_shader(GL_FRAGMENT_SHADER, k_gbuffer_fshader_src);
        glAttachShader(m_gbuffer_program, gbuffer_vshader);
        glAttachShader(m_gbuffer_program, gbuffer_fshader);
        link_program(m_gbuffer_program);
        glDeleteShader(gbuffer_vshader);
        glDeleteShader(gbuffer_fshader);
    }
    ARP_DEBUG("GBuffer program created");
    /* Color program */
    {
        m_color_program = glCreateProgram();
        GLuint screenquad_vshader = ScreenQuad::get().get_vertex_shader();
        GLuint color_fshader = create_shader(GL_FRAGMENT_SHADER, k_color_fshader_src);
        glAttachShader(m_color_program, screenquad_vshader);
        glAttachShader(m_color_program, color_fshader);
        link_program(m_color_program);
        glDeleteShader(color_fshader);
    }
    ARP_DEBUG("Color program created");
}

BrickRenderer::~BrickRenderer()
{
    glDeleteProgram(m_gbuffer_program);
    glDeleteProgram(m_color_program);
}

void BrickRenderer::render(const BrickRenderer_RenderParams& params)
{
    const BrickRenderer_BakedModel& baked_model = *params.baked_model;
    const Camera& camera = *params.camera;

    if (baked_model.num_vertices == 0) return;

    GLint parent_framebuffer;
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &parent_framebuffer);
    GLint viewport[4];
    glGetIntegerv(GL_VIEWPORT, viewport);
    int width = viewport[2];
    int height = viewport[3];
    if (!m_gbuffer || m_gbuffer->width != width || m_gbuffer->height != height) {
        m_gbuffer = std::make_unique<BrickRenderer_GBuffer>(width, height);
    }

    /* GBuffer program */
    glUseProgram(m_gbuffer_program);
    glBindFramebuffer(GL_FRAMEBUFFER, m_gbuffer->framebuffer);

    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LESS);
    glDisable(GL_BLEND);

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    m_gbuffer->clear();

    glUniformMatrix4fv(0 /* u_transform */, 1, GL_FALSE, glm::value_ptr(params.transform));
    glUniformMatrix4fv(1 /* u_view */, 1, GL_FALSE, glm::value_ptr(camera.view()));
    glUniformMatrix4fv(2 /* u_projection */, 1, GL_FALSE, glm::value_ptr(camera.projection()));

    glBindVertexArray(baked_model.vao);
    glBindBuffer(GL_ARRAY_BUFFER, baked_model.vbo);

    if (params.start_vertex != UINT32_MAX && params.end_vertex != UINT32_MAX) {
        glDrawArrays(GL_TRIANGLES, params.start_vertex, params.end_vertex - params.start_vertex);
    } else {
        glDrawArrays(GL_TRIANGLES, 0, baked_model.num_vertices);
    }

    /* Color program */
    glUseProgram(m_color_program);
    glBindFramebuffer(GL_FRAMEBUFFER, parent_framebuffer);

    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LESS);
    glDisable(GL_BLEND);

    glBindImageTexture(0 /* u_color */, m_gbuffer->color_texture, 0, GL_FALSE, 0, GL_READ_ONLY, GL_RGBA8);
    glBindImageTexture(1 /* u_uv */, m_gbuffer->uv_texture, 0, GL_FALSE, 0, GL_READ_ONLY, GL_RG8);
    glBindImageTexture(
        2 /* u_outline_guide */, m_gbuffer->outline_guide_texture, 0, GL_FALSE, 0, GL_READ_ONLY, GL_RG32UI);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, m_gbuffer->depth_buffer);

    glUniform1i(0 /* u_kernel_r */, params.kernel_r);
    glUniform4fv(1 /* u_border_color */, 1, glm::value_ptr(params.border_color));

    ScreenQuad::get().draw();
}

BrickRenderer_BakedModel BrickRenderer::bake_model(const Model& model)
{
    BrickRenderer_BakedModel baked_model{};
    glCreateVertexArrays(1, &baked_model.vao);
    glBindVertexArray(baked_model.vao);

    const Mesh& mesh = model.m_meshes.at(0);
    glGenBuffers(1, &baked_model.vbo);
    glBindBuffer(GL_ARRAY_BUFFER, baked_model.vbo);
    glBufferData(GL_ARRAY_BUFFER, mesh.vertices.size() * sizeof(Vertex), mesh.vertices.data(), GL_STATIC_DRAW);
    baked_model.num_vertices = mesh.vertices.size();
    ARP_DEBUG("Uploaded brick model with %zu vertices", baked_model.num_vertices);

    glEnableVertexAttribArray(0 /* a_position */);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*) offsetof(Vertex, position));
    glEnableVertexAttribArray(1 /* a_normal */);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*) offsetof(Vertex, normal));
    glEnableVertexAttribArray(2 /* a_uv */);
    glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*) offsetof(Vertex, texcoord));
    glEnableVertexAttribArray(3 /* a_color */);
    glVertexAttribPointer(3, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*) offsetof(Vertex, color));
    glEnableVertexAttribArray(4 /* a_outline_guide */);
    glVertexAttribIPointer(4, 2, GL_UNSIGNED_INT, sizeof(Vertex), (void*) offsetof(Vertex, p2));

    return baked_model;
}
