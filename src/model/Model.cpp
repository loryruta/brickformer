#include "Model.hpp"

using namespace lego_builder;

size_t Mesh::bytesize() const
{
    size_t bytesize = vertices.capacity() * sizeof(Vertex);
    bytesize += indices.capacity() * sizeof(uint32_t);
    bytesize += sizeof(Mesh);
    return bytesize;
}

void Mesh::apply_transform(const glm::mat4& transform)
{
    for (Vertex& vertex : vertices) {
        vertex.position = transform * glm::vec4(vertex.position, 1.0f);
    }
}

void Mesh::update_min_max()
{
    m_min = glm::vec3(INFINITY);
    m_max = glm::vec3(-INFINITY);

    for (const Vertex& vertex : vertices) {
        m_min = glm::min(m_min, vertex.position);
        m_max = glm::max(m_max, vertex.position);
    }
}

size_t Model::bytesize() const
{
    size_t bytesize = m_textures.capacity() * sizeof(Texture);
    for (const Mesh& mesh : m_meshes) bytesize += mesh.bytesize();
    bytesize += sizeof(Model);
    return bytesize;
}

void Model::apply_transform(const glm::mat4& transform)
{
    for (Mesh& mesh : m_meshes) mesh.apply_transform(transform);
}

void Model::update_min_max(bool update_mesh_minmax)
{
    m_min = glm::vec3(INFINITY);
    m_max = glm::vec3(-INFINITY);

    for (Mesh& mesh : m_meshes) {
        if (update_mesh_minmax) mesh.update_min_max();

        m_min = glm::min(m_min, mesh.m_min);
        m_max = glm::max(m_max, mesh.m_max);
    }
}

void Model::apply_flip(bool flip_x, bool flip_y, bool flip_z, glm::mat4& transform) const
{
    if (!flip_x && !flip_y && !flip_z) return;

    glm::vec3 scale{};
    scale.x = flip_x ? -1.f : 1.f;
    scale.y = flip_y ? -1.f : 1.f;
    scale.z = flip_z ? -1.f : 1.f;

    glm::vec3 translate{};
    translate.x = flip_x ? m_min.x + m_max.x : 0.f;
    translate.y = flip_y ? m_min.y + m_max.y : 0.f;
    translate.z = flip_z ? m_min.z + m_max.z : 0.f;

    transform = glm::translate(transform, translate);
    transform = glm::scale(transform, scale);
}
