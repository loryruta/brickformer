#include "VoxelModelBuilder.hpp"
#include <numeric>

using namespace lego_builder;



VoxelModelBuilder::VoxelModelBuilder()
{
    m_mesh = &m_model.m_meshes.emplace_back();
}


void VoxelModelBuilder::set_voxel(int x, int y, int z, const glm::vec4& color)
{
    glm::vec3 p{x, y, z};

    std::vector<Vertex> vertices{  // TODO no texcoords!
        // Bottom
        Vertex{ .m_position = {p.x, p.y, p.z}, .m_normal = {0, -1, 0}, .m_texcoord = {}, .m_color = color},
        Vertex{ .m_position = {p.x, p.y, p.z + 1}, .m_normal = {0, -1, 0}, .m_texcoord = {}, .m_color = color},
        Vertex{ .m_position = {p.x + 1, p.y, p.z + 1}, .m_normal = {0, -1, 0}, .m_texcoord = {}, .m_color = color},
        Vertex{ .m_position = {p.x + 1, p.y, p.z}, .m_normal = {0, -1, 0}, .m_texcoord = {}, .m_color = color},

        // Top
        Vertex{ .m_position = {p.x, p.y + 1, p.z}, .m_normal = {0, 1, 0}, .m_texcoord = {}, .m_color = color},
        Vertex{ .m_position = {p.x, p.y + 1, p.z + 1}, .m_normal = {0, 1, 0}, .m_texcoord = {}, .m_color = color},
        Vertex{ .m_position = {p.x + 1, p.y + 1, p.z + 1}, .m_normal = {0, 1, 0}, .m_texcoord = {}, .m_color = color},
        Vertex{ .m_position = {p.x + 1, p.y + 1, p.z}, .m_normal = {0, 1, 0}, .m_texcoord = {}, .m_color = color},

        // Left
        Vertex{ .m_position = {p.x, p.y, p.z}, .m_normal = {-1, 0, 0}, .m_texcoord = {}, .m_color = color},
        Vertex{ .m_position = {p.x, p.y, p.z + 1}, .m_normal = {-1, 0, 0}, .m_texcoord = {}, .m_color = color},
        Vertex{ .m_position = {p.x, p.y + 1, p.z + 1}, .m_normal = {-1, 0, 0}, .m_texcoord = {}, .m_color = color},
        Vertex{ .m_position = {p.x, p.y + 1, p.z}, .m_normal = {-1, 0, 0}, .m_texcoord = {}, .m_color = color},

        // Right
        Vertex{ .m_position = {p.x + 1, p.y, p.z}, .m_normal = {1, 0, 0}, .m_texcoord = {}, .m_color = color},
        Vertex{ .m_position = {p.x + 1, p.y, p.z + 1}, .m_normal = {1, 0, 0}, .m_texcoord = {}, .m_color = color},
        Vertex{ .m_position = {p.x + 1, p.y + 1, p.z + 1}, .m_normal = {1, 0, 0}, .m_texcoord = {}, .m_color = color},
        Vertex{ .m_position = {p.x + 1, p.y + 1, p.z}, .m_normal = {1, 0, 0}, .m_texcoord = {}, .m_color = color},

        // Front
        Vertex{ .m_position = {p.x, p.y, p.z}, .m_normal = {0, 0, -1}, .m_texcoord = {0, 1}, .m_color = color},
        Vertex{ .m_position = {p.x, p.y + 1, p.z}, .m_normal = {0, 0, -1}, .m_texcoord = {0 ,0}, .m_color = color},
        Vertex{ .m_position = {p.x + 1, p.y + 1, p.z}, .m_normal = {0, 0, -1}, .m_texcoord = {1, 0}, .m_color = color},
        Vertex{ .m_position = {p.x + 1, p.y, p.z}, .m_normal = {0, 0, -1}, .m_texcoord = {1, 1}, .m_color = color},

        // Back
        Vertex{ .m_position = {p.x, p.y, p.z + 1}, .m_normal = {0, 0, 1}, .m_texcoord = {}, .m_color = color},
        Vertex{ .m_position = {p.x, p.y + 1, p.z + 1}, .m_normal = {0, 0, 1}, .m_texcoord = {}, .m_color = color},
        Vertex{ .m_position = {p.x + 1, p.y + 1, p.z + 1}, .m_normal = {0, 0, 1}, .m_texcoord = {}, .m_color = color},
        Vertex{ .m_position = {p.x + 1, p.y, p.z + 1}, .m_normal = {0, 0, 1}, .m_texcoord = {}, .m_color = color},
    };

    std::vector<uint32_t> indices{
        0, 1, 2, 0, 2, 3,        // Bottom
        4, 5, 6, 4, 6, 7,        // Top
        8, 9, 10, 8, 10, 11,     // Left
        12, 13, 14, 12, 14, 15,  // Right
        16, 17, 18, 16, 18, 19,  // Front
        20, 21, 22, 20, 22, 23,  // Back
    };

    size_t index_offset = m_mesh->m_vertices.size();
    assert(index_offset % 24 == 0);
    for (uint32_t& i : indices) i += index_offset;

    m_mesh->m_vertices.insert(m_mesh->m_vertices.end(), vertices.begin(), vertices.end());
    m_mesh->m_indices.insert(m_mesh->m_indices.end(), indices.begin(), indices.end());
}
