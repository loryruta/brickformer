#include "BrickModelBuilder.hpp"

#include <algorithm>
#include <numeric>

#include "brick_models.hpp"
#include "bricks.hpp"
#include "util/misc.hpp"

using namespace lego_builder;


std::vector<Vertex> transform_vertices(
    const std::vector<Vertex>& vertices,
    const glm::mat4& transform,
    const glm::vec4& color
    )
{
    std::vector<Vertex> result(vertices.size());
    std::transform(vertices.begin(), vertices.end(), result.begin(), [&](const Vertex& v) {
        Vertex tv = v;
        tv.m_position = transform * glm::vec4(tv.m_position, 1.0f);
        tv.m_color = color;
        return tv;
    });
    return result;
}


BrickModelBuilder::BrickModelBuilder()
{
    m_mesh = &m_model.m_meshes.emplace_back();
}

void BrickModelBuilder::place(int slice_y, int x, int z, int bid, uint8_t subslice_mask, const glm::vec4& color)
{
    CHECK_ARG(subslice_mask != 0);

    bool is_full_brick = (subslice_mask & 0x7) == 0x7;

    auto& brick = k_bricks[bid];
    for (int bz = 0; bz < BRICK_MAX_HEIGHT; bz++)
    {
        for (int bx = 0; bx < BRICK_MAX_WIDTH; bx++)
        {
            if (brick[bz][bx])
            {
                glm::mat4 transform{1.0f};
                transform = glm::translate(transform, glm::vec3{x + bx, slice_y * (k_1x1_brick_size.y / k_1x1_brick_size.x), z + bz});  // Translate to voxel

                if (!is_full_brick)
                {
                    int by = 0;
                    while ((subslice_mask & (1 << by)) == 0) by++;  // Can't be infinite because subslice_mask != 0

                    float norm_plate_y = k_1x1_brick_plate_size.y / k_1x1_brick_plate_size.x;
                    transform = glm::translate(transform, glm::vec3{0, by * norm_plate_y, 0});  // Move the plate up
                }

                transform = glm::scale(transform, glm::vec3{1.0f / k_1x1_brick_plate_size.x});  // Normalization

                const std::vector<Vertex>& vertices = is_full_brick ? k_1x1_brick_vertices : k_1x1_brick_plate_vertices;
                std::vector<Vertex> transformed_vertices = transform_vertices(vertices, transform, color);

                uint32_t start_idx = m_mesh->m_vertices.size();
                m_mesh->m_vertices.insert(m_mesh->m_vertices.end(), transformed_vertices.begin(), transformed_vertices.end());

                std::vector<uint32_t> new_indices(vertices.size());
                std::iota(new_indices.begin(), new_indices.end(), start_idx);
                m_mesh->m_indices.insert(m_mesh->m_indices.end(), new_indices.begin(), new_indices.end());
            }
        }
    }
}
