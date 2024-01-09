#include "ModelRenderer.hpp"

#include "glm/gtc/type_ptr.hpp"

#include "gl_helpers.hpp"
#include "util/misc.hpp"

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

const char* k_vert_shader_src = R"(
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

const char* k_frag_shader_src = R"(
    in vec3 v_position;
    in vec3 v_normal;
    in vec2 v_texcoord;
    in vec4 v_color;

    uniform sampler2D u_texture;

    uniform vec3 u_camera_position;

    struct DirectionalLight { vec3 direction; vec3 color; };

    uniform DirectionalLight u_directional_lights[8];
    uniform uint u_num_directional_lights;

    layout(location = 0) out vec4 f_color;

    vec3 eval_phong_shading(vec3 light_dir, vec3 light_color)
    {
        vec3 ambient = 0.3 * light_color;
        vec3 diffuse = max(dot(v_normal, light_dir), 0.0) * light_color;

        vec3 view_dir = normalize(v_position - u_camera_position);
        vec3 reflect_dir = reflect(-light_dir, v_normal);
        vec3 specular = 0.5 * pow(max(dot(view_dir, reflect_dir), 0.0), 32) * light_color;

        return ambient + diffuse + specular;
    }

    void main()
    {
        vec3 color = (texture(u_texture, v_texcoord) * v_color).xyz;

#ifndef NO_SHADING
        vec3 shading;
        for (int i = 0; i < u_num_directional_lights; i++)
        {
            shading = max(
                shading,
                eval_phong_shading(u_directional_lights[i].direction, u_directional_lights[i].color)
                );
        }
        color *= shading;
#endif

        f_color = vec4(color, 1.0);
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

    std::string version_str = "#version 460 core\n";

    // Create program
    GLuint vert_shader = create_shader(GL_VERTEX_SHADER, version_str + k_vert_shader_src);
    GLuint frag_shader = create_shader(GL_FRAGMENT_SHADER, version_str + k_frag_shader_src);

    std::string frag_shader_src = version_str + "#define NO_SHADING\n" + k_frag_shader_src;
    GLuint frag_shader_no_shading = create_shader(GL_FRAGMENT_SHADER, frag_shader_src);

    // Create program
    m_program = glCreateProgram();

    glAttachShader(m_program, vert_shader);
    glAttachShader(m_program, frag_shader);

    link_program(m_program);

    // Create program, no shading
    m_program_no_shading = glCreateProgram();

    glAttachShader(m_program_no_shading, vert_shader);
    glAttachShader(m_program_no_shading, frag_shader_no_shading);

    link_program(m_program_no_shading);

    //
    glDeleteShader(vert_shader);
    glDeleteShader(frag_shader);
    glDeleteShader(frag_shader_no_shading);
}

ModelRenderer::~ModelRenderer()
{
    glDeleteTextures(1, &m_white_texture);

    glDeleteProgram(m_program);
    glDeleteProgram(m_program_no_shading);
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

void ModelRenderer::add_directional_light(DirectionalLight directional_light)
{
    CHECK_STATE_MSG(m_directional_lights.size() < 8, "Reached max number of directional lights");
    m_directional_lights.emplace_back(std::move(directional_light));
}

void ModelRenderer::render(const BakedModel& baked_model, const Camera& camera, const glm::mat4& transform)
{
    GLuint program = m_shading ? m_program : m_program_no_shading;
    glUseProgram(program);

    glEnable(GL_DEPTH_TEST);

    for (const BakedMesh& baked_mesh : baked_model.m_meshes)
    {
        if (baked_mesh.m_num_elements == 0) continue;

        // Transform
        glUniformMatrix4fv(get_uniform_location(program, "u_transform"), 1, GL_FALSE, glm::value_ptr(transform));

        // Camera
        glm::mat4 camera_mat = camera.matrix();
        glUniformMatrix4fv(get_uniform_location(program, "u_camera"), 1, GL_FALSE, glm::value_ptr(camera_mat));

        // Texture
        GLuint texture = baked_mesh.m_texture_idx >= 0 ? baked_model.m_textures[baked_mesh.m_texture_idx] : m_white_texture;
        glBindTexture(GL_TEXTURE_2D, texture);

        if (m_shading)
        {
            // Camera position
            glUniform3fv(get_uniform_location(program, "u_camera_position", false), 1, glm::value_ptr(camera.m_position));

            // Directional lights
            glUniform1ui(get_uniform_location(program, "u_num_directional_lights"), m_directional_lights.size());
            for (int i = 0; i < m_directional_lights.size(); i++)
            {
                std::string uniform_name = "u_directional_lights[" + std::to_string(i) + "]";
                glUniform3fv(get_uniform_location(program, uniform_name + ".direction"), 1, glm::value_ptr(m_directional_lights[i].m_direction));
                glUniform3fv(get_uniform_location(program, uniform_name + ".color"), 1, glm::value_ptr(m_directional_lights[i].m_color));
            }
        }

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

    // Position
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*) offsetof(Vertex, m_position));

    // Normal
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*) offsetof(Vertex, m_normal));

    // Texcoord
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*) offsetof(Vertex, m_texcoord));

    // Color
    glEnableVertexAttribArray(3);
    glVertexAttribPointer(3, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*) offsetof(Vertex, m_color));

    //
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
