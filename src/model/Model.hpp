#pragma once

#include <limits>
#include <string>
#include <vector>

#include "glm/glm.hpp"
#include "glm/gtc/matrix_transform.hpp"

namespace lego_builder
{
struct Vertex {
    glm::vec3 position;
    float p0;
    glm::vec3 normal;
    float p1;
    glm::vec2 texcoord;
    float p2[2];
    glm::vec4 color{1.0f}; ///< The vertex color (multiplied to the texture); ranged in [0, 1]
};

struct Mesh {
    std::vector<Vertex> vertices;  ///< The vertices describing the mesh geometry.
    std::vector<uint32_t> indices; ///< If not empty, indices used to assemble the vertices.
    glm::vec4 m_color{1.f};
    int m_texture_idx = -1; ///< Texture index into Model's m_textures array.

    glm::vec3 m_min;
    glm::vec3 m_max;

    void apply_transform(const glm::mat4& transform);

    void update_min_max();
};

struct Texture {
    std::string m_name;
    int m_width, m_height;
    std::vector<uint8_t> m_image_data; // RGBA pixels in row-first, top-left to bottom-right fashion
};

struct Model {
    std::vector<Texture> m_textures;

    std::vector<Mesh> m_meshes;

    glm::vec3 m_min;
    glm::vec3 m_max;

    [[nodiscard]] inline glm::vec3 size() const { return m_max - m_min; }

    /// Applies the transform to all meshes' vertices.
    void apply_transform(const glm::mat4& transform);

    void update_min_max(bool update_mesh_minmax = true);

    /// Applies a transform that flips the specified axes of the input model while keeping the same bounding box (scale
    /// and translate).
    void apply_flip(bool flip_x, bool flip_y, bool flip_z, glm::mat4& transform) const;
};

inline int calc_num_slices(const Model& model, int resolution) // TODO find a better place
{
    glm::vec3 size = model.size();
    float max_side = glm::max(size.x, size.z);
    return (int) glm::ceil(float(resolution) / max_side * size.y);
}
} // namespace lego_builder
