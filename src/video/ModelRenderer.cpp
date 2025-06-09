#include "ModelRenderer.hpp"

#include <glm/gtc/type_ptr.hpp>
#include <tinyformat.h>

#include "ScreenQuad.hpp"
#include "gl_helpers.hpp"
#include "log.hpp"
#include "util/misc.hpp"

#define ARP_LOG_CONTEXT "ModelRenderer"

using namespace lego_builder;

namespace
{
GLuint bake_texture(const Texture& texture)
{
    GLuint gl_texture;
    glGenTextures(1, &gl_texture);
    glBindTexture(GL_TEXTURE_2D, gl_texture);
    glTexImage2D(GL_TEXTURE_2D,
                 0,
                 GL_RGBA,
                 texture.m_width,
                 texture.m_height,
                 0,
                 GL_RGBA,
                 GL_UNSIGNED_BYTE,
                 texture.m_image_data.data());

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    return gl_texture;
}

const char* k_vertex_shader_src = R"(#version 460 core

    layout(location = 0) in vec3 a_position;
    layout(location = 1) in vec3 a_normal;
    layout(location = 2) in vec2 a_uv;
    layout(location = 3) in vec4 a_color;

    uniform mat4 u_transform;
    uniform mat4 u_view;
    uniform mat4 u_projection;

    out vec4 v_position;
    out vec4 v_normal;
    out vec2 v_uv;
    out vec4 v_color;

    void main()
    {
        mat4 VT = u_view * u_transform;
        vec4 position = VT * vec4(a_position, 1);
        vec4 normal = VT * vec4(a_normal, 0);

        v_position = position;
        v_normal = normal;
        v_uv = a_uv;
        v_color = a_color;

        gl_Position = u_projection * position;
    }
)";

const char* k_fragment_shader_src = R"(#version 460 core

    in vec4 v_position;
    in vec4 v_normal;
    in vec2 v_uv;
    in vec4 v_color;

    uniform vec4 u_mesh_color;
    uniform sampler2D u_texture;
    uniform float u_alpha_test_threshold;

    layout(location = 0) out vec4 f_position;
    layout(location = 1) out vec4 f_normal;
    layout(location = 2) out vec4 f_color;

    void main()
    {
        vec4 color = u_mesh_color * texture(u_texture, v_uv) * v_color;
        if (color.a < u_alpha_test_threshold) discard;

        f_position = vec4(v_position.xyz, 1);
        f_normal = vec4(normalize(v_normal.xyz), 1);
        f_color = color;
    }
)";

const char* k_shading_shader_src = R"(#version 460 core

    layout(location = 0) in vec2 v_uv;

    // GBuffer
    uniform sampler2D u_depth_buffer;
    uniform sampler2D u_albedo_texture;
    uniform sampler2D u_occlusion_texture;

    layout(location = 0) out vec4 f_color;

    void main()
    {
        float depth = texture(u_depth_buffer, v_uv).r;
        vec4 albedo = texture(u_albedo_texture, v_uv);
        float occlusion = texture(u_occlusion_texture, v_uv).r;

        f_color.rgb = albedo.rgb * occlusion;
        f_color.a = albedo.a;
        gl_FragDepth = depth;
    }
)";

} // namespace

BakedMesh::BakedMesh(BakedMesh&& other) noexcept
    : vao(other.vao), vbo(other.vbo), ebo(other.ebo), num_vertices(other.num_vertices),
      num_elements(other.num_elements), color(other.color), texture_idx(other.texture_idx)
{
    other.vao = 0; // Prevent moved element from being deleted
    other.vbo = 0;
    other.ebo = 0;
}

BakedMesh::~BakedMesh()
{
    if (ebo) glDeleteBuffers(1, &ebo);
    if (vbo) glDeleteBuffers(1, &vbo);
    if (vao) glDeleteVertexArrays(1, &vao);
}

BakedModel::~BakedModel()
{
    m_meshes.clear();

    glDeleteTextures(m_textures.size(), m_textures.data());
}

BlurredSSAOTarget::BlurredSSAOTarget(int width, int height) : width(width), height(height)
{
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, width, height, 0, GL_RED, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
}

BlurredSSAOTarget::~BlurredSSAOTarget() { glDeleteTextures(1, &texture); }

ModelRenderer::ModelRenderer()
{
    m_white_texture = create_white_texture(); // Create a white texture, used in case of missing texture

    // Create program
    GLuint vertex_shader = create_shader(GL_VERTEX_SHADER, k_vertex_shader_src);
    GLuint fragment_shader = create_shader(GL_FRAGMENT_SHADER, k_fragment_shader_src);
    GLuint shading_shader = create_shader(GL_FRAGMENT_SHADER, k_shading_shader_src);

    // Create program
    m_program = glCreateProgram();
    glAttachShader(m_program, vertex_shader);
    glAttachShader(m_program, fragment_shader);
    link_program(m_program);

    // Shading program
    m_shading_program = glCreateProgram();
    glAttachShader(m_shading_program, ScreenQuad::get().get_vertex_shader());
    glAttachShader(m_shading_program, shading_shader);
    link_program(m_shading_program);

    glUseProgram(m_shading_program);
    glUniform1i(get_uniform_location(m_shading_program, "u_depth_buffer"), 0);
    glUniform1i(get_uniform_location(m_shading_program, "u_albedo_texture"), 1);
    glUniform1i(get_uniform_location(m_shading_program, "u_occlusion_texture"), 2);

    //
    glDeleteShader(vertex_shader);
    glDeleteShader(fragment_shader);
    glDeleteShader(shading_shader);
}

ModelRenderer::~ModelRenderer()
{
    glDeleteTextures(1, &m_white_texture);

    glDeleteProgram(m_shading_program);
    glDeleteProgram(m_program);
}

GLuint ModelRenderer::create_white_texture()
{
    GLuint texture;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);

    uint8_t image_data[]{255, 255, 255, 255};
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, image_data);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    return texture;
}

void ModelRenderer::store_geometry(const BakedModel& model, const Camera& camera, const glm::mat4& transform)
{
    // NOTE: the currently bound framebuffer must be g-buffer's framebuffer

    CHECK_STATE(m_gbuffer);

    glUseProgram(m_program);

    glEnable(GL_DEPTH_TEST);
    glDisable(GL_BLEND);

    glUniform1f(get_uniform_location(m_program, "u_alpha_test_threshold"), m_alpha_test_threshold);

    for (const BakedMesh& baked_mesh : model.m_meshes) {
        glUniformMatrix4fv(get_uniform_location(m_program, "u_transform"), 1, GL_FALSE, glm::value_ptr(transform));

        glUniformMatrix4fv(get_uniform_location(m_program, "u_view"), 1, GL_FALSE, glm::value_ptr(camera.view()));
        glUniformMatrix4fv(
            get_uniform_location(m_program, "u_projection"), 1, GL_FALSE, glm::value_ptr(camera.projection()));

        glUniform4fv(get_uniform_location(m_program, "u_mesh_color"), 1, glm::value_ptr(baked_mesh.color));

        glActiveTexture(GL_TEXTURE0);
        GLuint texture = baked_mesh.texture_idx >= 0 ? model.m_textures[baked_mesh.texture_idx] : m_white_texture;
        glBindTexture(GL_TEXTURE_2D, texture);

        glBindVertexArray(baked_mesh.vao);
        if (baked_mesh.ebo) {
            glDrawElements(GL_TRIANGLES, baked_mesh.num_elements, GL_UNSIGNED_INT, nullptr);
        } else {
            glDrawArrays(GL_TRIANGLES, 0, baked_mesh.num_vertices);
        }
    }
}

void ModelRenderer::render(const BakedModel& model, const Camera& camera, const glm::mat4& transform)
{
    GLint parent_framebuffer;
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &parent_framebuffer);
    GLint viewport[4];
    glGetIntegerv(GL_VIEWPORT, viewport);

    int width = viewport[2];
    int height = viewport[3];

    /* Store geometry */
    if (!m_gbuffer || m_gbuffer->get_width() != width || m_gbuffer->get_height() != height)
        m_gbuffer = std::make_unique<GBuffer>(width, height);

    glBindFramebuffer(GL_FRAMEBUFFER, m_gbuffer->get_framebuffer());
    glViewport(0, 0, width, height);

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    m_gbuffer->clear();

    store_geometry(model, camera, transform);

    /* SSAO */
    if (!m_ssao_target || m_ssao_target->width != width || m_ssao_target->height != height) {
        m_ssao_target = std::make_unique<SSAOTarget>(width, height);
        m_blurred_ssao_target = std::make_unique<BlurredSSAOTarget>(width, height);
    }

    if (m_ssao) {
        m_ssao_pass.draw(*m_gbuffer, camera, *m_ssao_target);
        m_box_filter.run(m_ssao_target->texture, m_blurred_ssao_target->texture, 3);
    } else {
        // If SSAO is disabled, set occlusion to 1.0 (none)
        const float value = 1.f;
        glClearTexImage(m_blurred_ssao_target->texture, 0, GL_RED, GL_FLOAT, &value);
    }

    /* Final shading */
    glBindFramebuffer(GL_FRAMEBUFFER, parent_framebuffer);
    glViewport(viewport[0], viewport[1], viewport[2], viewport[3]);

    glEnable(GL_DEPTH_TEST);
    glEnable(GL_BLEND);

    glUseProgram(m_shading_program);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, m_gbuffer->get_depth_buffer());
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, m_gbuffer->get_albedo_texture());
    glActiveTexture(GL_TEXTURE2);
    glBindTexture(GL_TEXTURE_2D, m_blurred_ssao_target->texture);

    ScreenQuad::get().draw();
}

bool ModelRenderer::bake_mesh(const Mesh& mesh, BakedMesh& out_baked_mesh)
{
    if (mesh.vertices.empty()) {
        ARP_WARN("Empty mesh; won't be baked");
        return false;
    }
    if (mesh.indices.empty()) {
        CHECK_ARG(mesh.vertices.size() % 3 == 0, "Only triangular meshes are supported");
    } else {
        CHECK_ARG(mesh.indices.size() % 3 == 0, "Only triangular meshes are supported");
    }

    glGenVertexArrays(1, &out_baked_mesh.vao);
    glBindVertexArray(out_baked_mesh.vao);

    // Upload vertices
    glGenBuffers(1, &out_baked_mesh.vbo);
    glBindBuffer(GL_ARRAY_BUFFER, out_baked_mesh.vbo);
    glBufferData(GL_ARRAY_BUFFER, mesh.vertices.size() * sizeof(Vertex), mesh.vertices.data(), GL_STATIC_DRAW);
    ARP_DEBUG("VBO created with %zu vertices", mesh.vertices.size());
    out_baked_mesh.num_vertices = mesh.vertices.size();

    // Upload indices (elements)
    if (!mesh.indices.empty()) {
        glGenBuffers(1, &out_baked_mesh.ebo);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, out_baked_mesh.ebo);
        glBufferData(
            GL_ELEMENT_ARRAY_BUFFER, mesh.indices.size() * sizeof(uint32_t), mesh.indices.data(), GL_STATIC_DRAW);
        ARP_DEBUG("EBO created with %zu indices", mesh.indices.size());
    }
    out_baked_mesh.num_elements = mesh.indices.size();

    glEnableVertexAttribArray(0); // Position
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*) offsetof(Vertex, position));
    glEnableVertexAttribArray(1); // Normal
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*) offsetof(Vertex, normal));
    glEnableVertexAttribArray(2); // Texcoord
    glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*) offsetof(Vertex, texcoord));
    glEnableVertexAttribArray(3); // Color
    glVertexAttribPointer(3, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*) offsetof(Vertex, color));
    ARP_DEBUG("VAO created");

    //
    glBindVertexArray(0);
    glBindBuffer(GL_ARRAY_BUFFER, out_baked_mesh.vbo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, out_baked_mesh.ebo);

    out_baked_mesh.color = mesh.m_color;
    out_baked_mesh.texture_idx = mesh.m_texture_idx;

    return true;
}

BakedModel ModelRenderer::bake_model(const Model& model)
{
    BakedModel baked_model{};
    // printf("[ModelRenderer] Baking %zu textures...\n", model.m_textures.size());
    for (const Texture& texture : model.m_textures) {
        baked_model.m_textures.emplace_back(bake_texture(texture));
    }
    // printf("[ModelRenderer] Baking %zu meshes...\n", model.m_meshes.size());
    for (const Mesh& mesh : model.m_meshes) {
        BakedMesh baked_mesh{};
        if (bake_mesh(mesh, baked_mesh)) {
            baked_model.m_meshes.emplace_back(std::move(baked_mesh));
        }
    }
    // printf("[ModelRenderer] Model baked\n");
    return baked_model;
}
