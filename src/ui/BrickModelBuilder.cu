#include "BrickModelBuilder.h"

#include <algorithm>
#include <numeric>

#include "brick_colors.hpp"
#include "brick_models.hpp"
#include "bricks.hpp"
#include "util/misc.hpp"

using namespace lego_builder;

namespace
{
/// Given a list of quad vertices in clock-wise order, triangulate and add them into the output vector.
void add_quad(const std::vector<Vertex>& quad_vertices, std::vector<Vertex>& out_vertices)
{
    CHECK_ARG(quad_vertices.size() == 4);
    out_vertices.emplace_back(quad_vertices.at(0));
    out_vertices.emplace_back(quad_vertices.at(1));
    out_vertices.emplace_back(quad_vertices.at(2));
    out_vertices.emplace_back(quad_vertices.at(0));
    out_vertices.emplace_back(quad_vertices.at(2));
    out_vertices.emplace_back(quad_vertices.at(3));
}

void add_quad(const std::vector<glm::vec3>& quad_corners, Vertex template_, std::vector<Vertex>& out_vertices)
{
    CHECK_ARG(quad_corners.size() == 4);
    std::vector<Vertex> quad_vertices(4, template_);
    quad_vertices[0].position = quad_corners[0];
    quad_vertices[1].position = quad_corners[1];
    quad_vertices[2].position = quad_corners[2];
    quad_vertices[3].position = quad_corners[3];
    add_quad(quad_vertices, out_vertices);
}

/// \param p Position of the cylinder (center of bottom basis)
/// \param h Y height of the cylinder
/// \param r Radius of the cylinder
void add_y_cylinder(
    const glm::vec3& p, float h, float r, int subdivisions, Vertex template_, std::vector<Vertex>& out_vertices)
{
    float delta = (glm::pi<float>() * 2.f) / subdivisions;
    float a = 0.;
    for (int i = 0; i < subdivisions; ++i) {
        float b = a + delta;
        glm::vec3 ca = glm::vec3(glm::cos(a) * r, 0, glm::sin(a) * r);
        glm::vec3 cb = glm::vec3(glm::cos(b) * r, 0, glm::sin(b) * r);
        // Side face
        {
            template_.normal = glm::vec3(cb.z - ca.z, 0, ca.x - cb.x);
            template_.normal = glm::normalize(template_.normal);
            Vertex v0 = template_;
            v0.position.x = p.x + ca.x;
            v0.position.y = p.y;
            v0.position.z = p.z + ca.z;
            Vertex v1 = template_;
            v1.position.x = p.x + ca.x;
            v1.position.y = p.y + h;
            v1.position.z = p.z + ca.z;
            Vertex v2 = template_;
            v2.position.x = p.x + cb.x;
            v2.position.y = p.y + h;
            v2.position.z = p.z + cb.z;
            Vertex v3 = template_;
            v3.position.x = p.x + cb.x;
            v3.position.y = p.y;
            v3.position.z = p.z + cb.z;
            add_quad({v0, v1, v2, v3}, out_vertices);
        }
        // Top slice
        {
            template_.normal = glm::vec3(0, 1, 0);
            Vertex v0 = template_;
            v0.position.x = p.x;
            v0.position.y = p.y + h;
            v0.position.z = p.z;
            Vertex v1 = template_;
            v1.position.x = p.x + cb.x;
            v1.position.y = p.y + h;
            v1.position.z = p.z + cb.z;
            Vertex v2 = template_;
            v2.position.x = p.x + ca.x;
            v2.position.y = p.y + h;
            v2.position.z = p.z + ca.z;
            // Add triangle
            out_vertices.emplace_back(v0);
            out_vertices.emplace_back(v1);
            out_vertices.emplace_back(v2);
        }
        a = b;
    }
    // No bottom face
}
} // namespace

std::vector<Vertex>
transform_vertices(const std::vector<Vertex>& vertices, const glm::mat4& transform, const glm::vec4& color)
{
    std::vector<Vertex> result(vertices.size());
    std::transform(vertices.begin(), vertices.end(), result.begin(), [&](const Vertex& v) {
        Vertex tv = v;
        tv.position = transform * glm::vec4(tv.position, 1.0f);
        tv.color = color;
        return tv;
    });
    return result;
}

BrickModelBuilder::BrickModelBuilder() { m_mesh = &m_model.m_meshes.emplace_back(); }

// void BrickModelBuilder::place_1x1(int slice_y, int x, int z, uint8_t subslice_mask, const glm::vec4& color)
//{
//     auto add_vertices = [&](const std::vector<Vertex>& vertices, const glm::mat4& transform) {
//         std::vector<Vertex> transformed_vertices = transform_vertices(vertices, transform, color);
//
//         uint32_t start_idx = m_mesh->m_vertices.size();
//         m_mesh->m_vertices.insert(m_mesh->m_vertices.end(), transformed_vertices.begin(),
//         transformed_vertices.end());
//
//         std::vector<uint32_t> new_indices(vertices.size());
//         std::iota(new_indices.begin(), new_indices.end(), start_idx);
//         m_mesh->m_indices.insert(m_mesh->m_indices.end(), new_indices.begin(), new_indices.end());
//     };
//
//     glm::mat4 brick_transform{1.0f};
//     brick_transform = glm::translate(
//         brick_transform, glm::vec3{x, slice_y * (k_1x1_brick_size.y / k_1x1_brick_size.x), z}); // Translate to voxel
//     brick_transform = glm::scale(brick_transform, glm::vec3{1.0f / k_1x1_brick_plate_size.x});  // Normalization
//
//     bool is_full_brick = (subslice_mask & 0x7) == 0x7;
//     if (is_full_brick) {
//         add_vertices(k_1x1_brick_vertices, brick_transform);
//     } else {
//         for (int subslice = 0; subslice < 3; subslice++) {
//             if (subslice_mask & (1 << subslice)) {
//                 glm::mat4 plate_transform{1.0f};
//                 if (subslice > 0) {
//                     // Move the plate at subslice height
//                     float norm_plate_y = k_1x1_brick_plate_size.y / k_1x1_brick_plate_size.x;
//                     plate_transform = glm::translate(plate_transform, glm::vec3{0, subslice * norm_plate_y, 0});
//                 }
//
//                 add_vertices(k_1x1_brick_plate_vertices, plate_transform * brick_transform);
//             }
//         }
//     }
// }

void BrickModelBuilder::add_placement(int slice_y, uint32_t pid, const Placement& placement)
{
    glm::vec4 color = k_brick_colors[placement.cid].color_u8();
    color /= 255.0f; // Bring to [0, 1] range

    const auto& brick = k_bricks[placement.bid];

    Vertex template_;
    std::vector<Vertex> vertices;
    /* Bottom quads */
    for (int bz = 0; bz < BRICK_MAX_EXTENT_Z; ++bz) {
        for (int bx = 0; bx < BRICK_MAX_EXTENT_X; ++bx) {
            if (brick[bz][bx]) {
                int x = placement.x + bx;
                int z = placement.z + bz;
                template_.normal = glm::vec3(0, -1, 0);
                template_.color = color;
                add_quad({glm::vec3(x, slice_y, z),
                          glm::vec3(x + 1, slice_y, z),
                          glm::vec3(x + 1, slice_y, z + 1),
                          glm::vec3(x, slice_y, z + 1)},
                         template_,
                         vertices);
            }
        }
    }
    /* Top quads */
    for (int bz = 0; bz < BRICK_MAX_EXTENT_Z; ++bz) {
        for (int bx = 0; bx < BRICK_MAX_EXTENT_X; ++bx) {
            if (brick[bz][bx]) {
                int x = placement.x + bx;
                int z = placement.z + bz;
                template_.normal = glm::vec3(0, 1, 0);
                template_.color = color;
                add_quad({glm::vec3(x, slice_y + 1, z),
                          glm::vec3(x + 1, slice_y + 1, z),
                          glm::vec3(x + 1, slice_y + 1, z + 1),
                          glm::vec3(x, slice_y + 1, z + 1)},
                         template_,
                         vertices);
            }
        }
    }
    /* Top studs */
    // Height of the stud in normalized coordinates (i.e. if the 1x1 brick is 1x1 units)
    const float k_stud_h = 0.177083333f;
    const float k_stud_r = 0.25f;
    for (int bz = 0; bz < BRICK_MAX_EXTENT_Z; ++bz) {
        for (int bx = 0; bx < BRICK_MAX_EXTENT_X; ++bx) {
            if (brick[bz][bx]) {
                int x = placement.x + bx;
                int z = placement.z + bz;
                template_.color = color;
                add_y_cylinder(glm::vec3(x + 0.5f, slice_y + 1, z + 0.5f), k_stud_h, k_stud_r, 8, template_, vertices);
            }
        }
    }
    /* Sides */
    for (int bz = 0; bz < BRICK_MAX_EXTENT_Z; ++bz) {
        for (int bx = 0; bx < BRICK_MAX_EXTENT_X; ++bx) {
            if (brick[bz][bx]) {
                int x = placement.x + bx;
                int z = placement.z + bz;
                // -Z edge
                if (bz == 0 || !brick[bz - 1][bx]) {
                    template_.normal = glm::vec3(0, 0, -1);
                    add_quad({glm::vec3(x, slice_y, z),
                              glm::vec3(x, slice_y + 1, z),
                              glm::vec3(x + 1, slice_y + 1, z),
                              glm::vec3(x + 1, slice_y, z)},
                             template_,
                             vertices);
                }
                // +Z edge
                if (bz == BRICK_MAX_EXTENT_Z - 1 || !brick[bz + 1][bx]) {
                    template_.normal = glm::vec3(0, 0, 1);
                    add_quad({glm::vec3(x, slice_y, z + 1),
                              glm::vec3(x, slice_y + 1, z + 1),
                              glm::vec3(x + 1, slice_y + 1, z + 1),
                              glm::vec3(x + 1, slice_y, z + 1)},
                             template_,
                             vertices);
                }
                // -X edge
                if (bx == 0 || !brick[bz][bx - 1]) {
                    template_.normal = glm::vec3(-1, 0, 0);
                    add_quad({glm::vec3(x, slice_y, z),
                              glm::vec3(x, slice_y + 1, z),
                              glm::vec3(x, slice_y + 1, z + 1),
                              glm::vec3(x, slice_y, z + 1)},
                             template_,
                             vertices);
                }
                // +X edge
                if (bx == BRICK_MAX_EXTENT_X - 1 || !brick[bz][bx + 1]) {
                    template_.normal = glm::vec3(1, 0, 0);
                    add_quad({glm::vec3(x + 1, slice_y, z + 1),
                              glm::vec3(x + 1, slice_y + 1, z + 1),
                              glm::vec3(x + 1, slice_y + 1, z),
                              glm::vec3(x + 1, slice_y, z)},
                             template_,
                             vertices);
                }
            }
        }
    }

    m_mesh->vertices.insert(m_mesh->vertices.end(), vertices.begin(), vertices.end());
    // No indices

    m_mesh->update_min_max();
}
