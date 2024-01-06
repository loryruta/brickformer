#include "ModelRenderer.hpp"

#include "glm/gtc/type_ptr.hpp"

#include "gl_helpers.hpp"

using namespace lego_builder;

namespace
{
GLuint bake_texture(const Texture& texture)
{
    GLuint gl_texture;
    glGenTextures(1, &gl_texture);
    glBindTexture(GL_TEXTURE_2D, gl_texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, texture.m_width, texture.m_height, 0, GL_RGBA, GL_UNSIGNED_BYTE, texture.m_image_data.data());

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    return gl_texture;
}

const char* k_vert_shader_src = R"(#version 460 core

    layout(location = 0) in vec3 a_position;
    layout(location = 1) in vec3 a_normal;
    layout(location = 2) in vec2 a_texcoord;
    layout(location = 3) in vec4 a_color;

    uniform mat4 u_transform;
    uniform mat4 u_camera;

    out vec3 v_position;
    out vec3 v_normal;
    out vec2 v_texcoord;
    out vec4 v_color;

    void main()
    {
        vec4 position = u_transform * vec4(a_position, 1.0);
        vec4 normal = u_transform * vec4(a_normal, 0.0);

        gl_Position = u_camera * position;

        v_position = position.xyz;
        v_normal = normal.xyz;
        v_texcoord = a_texcoord;
        v_color = a_color;
    }
)";

const char* k_frag_shader_src = R"(#version 460 core

    in vec3 v_position;
    in vec3 v_normal;
    in vec2 v_texcoord;
    in vec4 v_color;

    uniform sampler2D u_texture;

    layout(location = 0) out vec4 f_color;

    void main()
    {
        f_color = texture(u_texture, v_texcoord) * v_color;
    }
)";
}  // namespace

BakedMesh::BakedMesh(BakedMesh&& other) noexcept :
    m_vao(other.m_vao),
    m_vbo(other.m_vbo),
    m_ebo(other.m_ebo),
    m_num_elements(other.m_num_elements),
    m_texture_idx(other.m_texture_idx)
{
    other.m_vao = 0;  // Prevent moved element from being deleted
    other.m_vbo = 0;
    other.m_ebo = 0;
}

BakedMesh::~BakedMesh()
{
    if (m_ebo) glDeleteBuffers(1, &m_ebo);
    if (m_vbo) glDeleteBuffers(1, &m_vbo);
    if (m_vao) glDeleteVertexArrays(1, &m_vao);
}

BakedModel::~BakedModel()
{
    m_meshes.clear();

    glDeleteTextures(m_textures.size(), m_textures.data());
}

ModelRenderer::ModelRenderer()
{
    m_white_texture = create_white_texture();  // Create a white texture, used in case of missing texture

    // Create program
    GLuint vert_shader = create_shader(GL_VERTEX_SHADER, k_vert_shader_src);
    GLuint frag_shader = create_shader(GL_FRAGMENT_SHADER, k_frag_shader_src);

    m_program = glCreateProgram();

    glAttachShader(m_program, vert_shader);
    glAttachShader(m_program, frag_shader);

    link_program(m_program);

    glDeleteShader(vert_shader);
    glDeleteShader(frag_shader);
}

ModelRenderer::~ModelRenderer()
{
    glDeleteTextures(1, &m_white_texture);

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

void ModelRenderer::render(const BakedModel& baked_model, const Camera& camera, const glm::mat4& transform)
{
    glUseProgram(m_program);

    glEnable(GL_DEPTH_TEST);

    for (const BakedMesh& baked_mesh : baked_model.m_meshes)
    {
        if (baked_mesh.m_num_elements == 0) continue;

        glUniformMatrix4fv(get_uniform_location(m_program, "u_transform"), 1, GL_FALSE, glm::value_ptr(transform));

        glm::mat4 camera_mat = camera.matrix();
        glUniformMatrix4fv(get_uniform_location(m_program, "u_camera"), 1, GL_FALSE, glm::value_ptr(camera_mat));

        GLuint texture = baked_mesh.m_texture_idx >= 0 ? baked_model.m_textures[baked_mesh.m_texture_idx] : m_white_texture;
        glBindTexture(GL_TEXTURE_2D, texture);

        glBindVertexArray(baked_mesh.m_vao);

        glDrawElements(GL_TRIANGLES, baked_mesh.m_num_elements, GL_UNSIGNED_INT, nullptr);
    }
}

BakedMesh ModelRenderer::bake_mesh(const Mesh& mesh)
{
    assert(mesh.m_indices.size() % 3 == 0);  // TODO no assert

    BakedMesh baked_mesh{};

    glGenVertexArrays(1, &baked_mesh.m_vao);
    glBindVertexArray(baked_mesh.m_vao);

    glGenBuffers(1, &baked_mesh.m_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, baked_mesh.m_vbo);
    glBufferData(GL_ARRAY_BUFFER, mesh.m_vertices.size() * sizeof(Vertex), mesh.m_vertices.data(), GL_STATIC_DRAW);

    glGenBuffers(1, &baked_mesh.m_ebo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, baked_mesh.m_ebo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, mesh.m_indices.size() * sizeof(uint32_t), mesh.m_indices.data(), GL_STATIC_DRAW);
    baked_mesh.m_num_elements = mesh.m_indices.size();

    GLint attrib_loc;

    attrib_loc = get_attrib_location(m_program, "a_position");
    if (attrib_loc >= 0)
    {
        glEnableVertexAttribArray(attrib_loc);
        glVertexAttribPointer(attrib_loc, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*) offsetof(Vertex, m_position));
    }

    attrib_loc = get_attrib_location(m_program, "a_normal", false);
    if (attrib_loc >= 0)
    {
        glEnableVertexAttribArray(attrib_loc);
        glVertexAttribPointer(attrib_loc, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*) offsetof(Vertex, m_normal));
    }

    attrib_loc = get_attrib_location(m_program, "a_texcoord", true);
    if (attrib_loc >= 0)
    {
        glEnableVertexAttribArray(attrib_loc);
        glVertexAttribPointer(attrib_loc, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*) offsetof(Vertex, m_texcoord));
    }

    attrib_loc = get_attrib_location(m_program, "a_color", true);
    if (attrib_loc >= 0)
    {
        glEnableVertexAttribArray(attrib_loc);
        glVertexAttribPointer(attrib_loc, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*) offsetof(Vertex, m_color));
    }

    glBindVertexArray(0);

    baked_mesh.m_texture_idx = mesh.m_texture_idx;

    return baked_mesh;
}

BakedModel ModelRenderer::bake_model(const Model& model)
{
    BakedModel baked_model{};

    printf("[ModelRenderer] Baking %zu textures...\n", model.m_textures.size());
    for (const Texture& texture : model.m_textures)
    {
        baked_model.m_textures.emplace_back(bake_texture(texture));
    }

    printf("[ModelRenderer] Baking %zu meshes...\n", model.m_meshes.size());
    for (const Mesh& mesh : model.m_meshes)
    {
        BakedMesh baked_mesh = bake_mesh(mesh);
        baked_model.m_meshes.emplace_back(std::move(baked_mesh));
    }

    printf("[ModelRenderer] Model baked\n");

    return baked_model;
}
