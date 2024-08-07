#pragma once

#include <memory>
#include <unordered_map>

#include <glad/gl.h>

#include "BoxFilter.hpp"
#include "Camera.hpp"
#include "GBuffer.hpp"
#include "model/Model.hpp"
#include "SSAOPass.hpp"

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

    struct BlurredSSAOTarget
    {
        int width, height;
        GLuint texture;

        explicit BlurredSSAOTarget(int width, int height);
        BlurredSSAOTarget(const BlurredSSAOTarget&) = delete;
        BlurredSSAOTarget(const BlurredSSAOTarget&&) = delete;
        ~BlurredSSAOTarget();
    };

    class ModelRenderer
    {
    private:
        GLuint m_white_texture;
        GLuint m_program;
        GLuint m_shading_program;

        std::unique_ptr<SSAOTarget> m_ssao_target;
        std::unique_ptr<BlurredSSAOTarget> m_blurred_ssao_target;

        std::unique_ptr<GBuffer> m_gbuffer;

    public:
        SSAOPass m_ssao_pass;
        BoxFilter m_box_filter;

        /* Params */
        float m_alpha_test_threshold = 0.7f;
        bool m_ssao = true;

        explicit ModelRenderer();
        ~ModelRenderer();

        void render(const BakedModel& model, const Camera& camera, const glm::mat4& transform);

        static BakedModel bake_model(const Model& model);

    private:
        void store_geometry(const BakedModel& model, const Camera& camera, const glm::mat4& transform);

        GLuint create_white_texture();

        static BakedMesh bake_mesh(const Mesh& mesh);
    };
}
