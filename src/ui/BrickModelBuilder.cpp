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

void BrickModelBuilder::place_1x1(int slice_y, int x, int z, uint8_t subslice_mask, const glm::vec4& color)
{
    auto add_vertices = [&](const std::vector<Vertex>& vertices, const glm::mat4& transform)
    {
        std::vector<Vertex> transformed_vertices = transform_vertices(vertices, transform, color);

        uint32_t start_idx = m_mesh->m_vertices.size();
        m_mesh->m_vertices.insert(m_mesh->m_vertices.end(), transformed_vertices.begin(), transformed_vertices.end());

        std::vector<uint32_t> new_indices(vertices.size());
        std::iota(new_indices.begin(), new_indices.end(), start_idx);
        m_mesh->m_indices.insert(m_mesh->m_indices.end(), new_indices.begin(), new_indices.end());
    };

    glm::mat4 brick_transform{1.0f};
    brick_transform = glm::translate(brick_transform, glm::vec3{x, slice_y * (k_1x1_brick_size.y / k_1x1_brick_size.x), z});  // Translate to voxel
    brick_transform = glm::scale(brick_transform, glm::vec3{1.0f / k_1x1_brick_plate_size.x});  // Normalization

    bool is_full_brick = (subslice_mask & 0x7) == 0x7;
    if (is_full_brick)
    {
        add_vertices(k_1x1_brick_vertices, brick_transform);
    }
    else
    {
        for (int subslice = 0; subslice < 3; subslice++)
        {
            if (subslice_mask & (1 << subslice))
            {
                glm::mat4 plate_transform{1.0f};
                if (subslice > 0)
                {
                    // Move the plate at subslice height
                    float norm_plate_y = k_1x1_brick_plate_size.y / k_1x1_brick_plate_size.x;
                    plate_transform = glm::translate(plate_transform, glm::vec3{0, subslice * norm_plate_y, 0});
                }

                add_vertices(k_1x1_brick_plate_vertices, plate_transform * brick_transform);
            }
        }
    }
}

void BrickModelBuilder::place(int slice_y, int x, int z, int bid, uint8_t subslice_mask, const glm::vec4& color)
{
    CHECK_ARG(subslice_mask != 0);

    auto& brick = k_bricks[bid];
    for (int bz = 0; bz < BRICK_MAX_HEIGHT; bz++)
    {
        for (int bx = 0; bx < BRICK_MAX_WIDTH; bx++)
        {
            if (brick[bz][bx]) place_1x1(slice_y, x + bx, z + bz, subslice_mask, color);
        }
    }
}
