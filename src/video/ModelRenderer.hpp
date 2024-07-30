#pragma once

#include <memory>
#include <unordered_map>

#include "glad/gl.h"

#include "Camera.hpp"
#include "model/Model.hpp"

namespace lego_builder
{
    struct BakedMesh
    {
        GLuint m_vao, m_vbo, m_ebo;
        size_t m_num_elements;

        glm::vec4 m_color{1.f};

        /// A non-owned reference to the baked texture, stored in BakedModel.
        /// If negative, a white texture is used.
        int m_texture_idx = -1;

        BakedMesh() = default;
        BakedMesh(const BakedMesh& other) = delete;
        BakedMesh(BakedMesh&& other) noexcept;

        ~BakedMesh();
    };

    struct BakedModel
    {
        std::vector<GLuint> m_textures;
        std::vector<BakedMesh> m_meshes;

        BakedModel() = default;
        BakedModel(const BakedModel& other) = delete;
        BakedModel(BakedModel&& other) = default;

        ~BakedModel();
    };

    class ModelRenderer
    {
    public:
        struct DirectionalLight { glm::vec3 m_direction; glm::vec3 m_color; };

    private:
        GLuint m_white_texture;
        GLuint m_program;
        GLuint m_program_no_shading;

        std::vector<DirectionalLight> m_directional_lights;

    public:
        bool m_shading = true;

        explicit ModelRenderer();
        ~ModelRenderer();

        void clear_directional_lights() { m_directional_lights.clear(); };
        void add_directional_light(DirectionalLight directional_light);

        void render(const BakedModel& model, const Camera& camera, const glm::mat4& transform);

        BakedModel bake_model(const Model& model);

    private:
        GLuint create_white_texture();

        BakedMesh bake_mesh(const Mesh& mesh);
    };
}
