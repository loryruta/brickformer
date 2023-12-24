#pragma once

#include <unordered_map>

#include <glad/gl.h>

#include "Model.hpp"
#include "Camera.hpp"

namespace lego_builder
{
    struct BakedMesh
    {
        GLuint m_vao, m_vbo, m_ebo;
        size_t m_num_elements;

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
    private:
        GLuint m_white_texture;
        GLuint m_program;

    public:
        explicit ModelRenderer();
        ~ModelRenderer();

        void render(const BakedModel& model, const Camera& camera, const glm::mat4& transform);

        BakedModel bake_model(const Model& model);

    private:
        GLuint create_white_texture();

        BakedMesh bake_mesh(const Mesh& mesh);
    };
}
