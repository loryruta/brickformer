#pragma once

#include <limits>
#include <string>
#include <vector>

#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

namespace lego_builder
{
    struct Vertex
    {
        glm::vec3 m_position; float p0;
        glm::vec3 m_normal;   float p1;
        glm::vec2 m_texcoord; float p2[2];
        glm::vec4 m_color{1};
    };

    struct Mesh
    {
        std::vector<Vertex> m_vertices;
        std::vector<uint32_t> m_indices;
        glm::mat4 m_transform;

        int m_texture_idx;  ///< Texture index into Model's m_textures array.

        glm::vec3 m_transformed_min;
        glm::vec3 m_transformed_max;
    };

    struct Texture
    {
        std::string m_name;
        int m_width, m_height;
        std::vector<uint8_t> m_image_data;  // RGBA pixels in row-first, top-left to bottom-right fashion
    };

    /// Creates a normalization matrix that fits the given bounding-box between (0,0,0) and (1,1,1).
    inline glm::mat4 create_normalization_matrix(const glm::vec3& bb_min, const glm::vec3& bb_max)
    {
        glm::mat4 m = glm::identity<glm::mat4>();
        glm::vec3 model_size = bb_max - bb_min;
        float max_side = glm::max(model_size.x, glm::max(model_size.y, model_size.z));
        m = glm::scale(m, glm::vec3(1.0f / max_side));
        m = glm::translate(m, -bb_min);
        return m;
    }

    struct Model
    {
        std::vector<Texture> m_textures;

        std::vector<Mesh> m_meshes;

        glm::vec3 m_transformed_min = glm::vec3(INFINITY);
        glm::vec3 m_transformed_max = glm::vec3(-INFINITY);

        [[nodiscard]] inline glm::vec3 transformed_size() const
        {
            return m_transformed_max - m_transformed_min;
        }

        /// Returns a transformation matrix that, if applied to every vertex position, normalizes the model between (0,0,0) and (1,1,1).
        [[nodiscard]] inline glm::mat4 normalization_matrix() const
        {
            return create_normalization_matrix(m_transformed_min, m_transformed_max);
        }
    };
}
