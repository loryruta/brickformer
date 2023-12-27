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

        int m_texture_idx;  ///< Texture index into Model's m_textures array.

        glm::vec3 m_min;
        glm::vec3 m_max;

        void apply_transform(const glm::mat4& transform);

        void update_min_max();
    };

    struct Texture
    {
        std::string m_name;
        int m_width, m_height;
        std::vector<uint8_t> m_image_data;  // RGBA pixels in row-first, top-left to bottom-right fashion
    };

    struct Model
    {
        std::vector<Texture> m_textures;

        std::vector<Mesh> m_meshes;

        glm::vec3 m_min;
        glm::vec3 m_max;

        [[nodiscard]] inline glm::vec3 size() const { return m_max - m_min; }

        /// Applies the transform to all meshes.
        void apply_transform(const glm::mat4& transform);

        void update_min_max(bool update_mesh_minmax = true);
    };
}
