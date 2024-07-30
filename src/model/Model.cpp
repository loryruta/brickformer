#include "Model.hpp"

using namespace lego_builder;

void Mesh::apply_transform(const glm::mat4& transform)
{
    for (Vertex& vertex : m_vertices)
    {
        vertex.m_position = transform * glm::vec4(vertex.m_position, 1.0f);
    }
}

void Mesh::update_min_max()
{
    m_min = glm::vec3(INFINITY);
    m_max = glm::vec3(-INFINITY);

    for (const Vertex& vertex : m_vertices)
    {
        m_min = glm::min(m_min, vertex.m_position);
        m_max = glm::max(m_max, vertex.m_position);
    }
}

void Model::apply_transform(const glm::mat4& transform)
{
    for (Mesh& mesh : m_meshes) mesh.apply_transform(transform);
}

void Model::update_min_max(bool update_mesh_minmax)
{
    m_min = glm::vec3(INFINITY);
    m_max = glm::vec3(-INFINITY);

    for (Mesh& mesh : m_meshes)
    {
        if (update_mesh_minmax) mesh.update_min_max();

        m_min = glm::min(m_min, mesh.m_min);
        m_max = glm::max(m_max, mesh.m_max);
    }
}

