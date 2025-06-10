#include "BrickModelBuilder.h"

#include <cstring>

#include "brick_colors.hpp"
#include "brick_models.hpp"
#include "bricks.hpp"
#include "util/misc.hpp"

using namespace lego_builder;

namespace
{

void set_outline_guide(uint32_t pid, uint8_t part, uint8_t subslice_mask, Vertex& out_vertex)
{
    uint32_t p2_1 = (part << 8) | (subslice_mask & 0xFF);
    std::memcpy(&out_vertex.p2[0], &pid, sizeof(float));
    std::memcpy(&out_vertex.p2[1], &p2_1, sizeof(float));
}

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
void add_y_cylinder(const glm::vec3& p,
                    float h,
                    float r,
                    int subdivisions,
                    uint32_t pid,
                    uint8_t subslice_mask,
                    Vertex template_,
                    std::vector<Vertex>& out_vertices)
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
            set_outline_guide(pid, 2, subslice_mask, template_);
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
            set_outline_guide(pid, 3, subslice_mask, template_);
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

BrickModelBuilder::BrickModelBuilder() { m_mesh = &m_model.m_meshes.emplace_back(); }

void BrickModelBuilder::add_placement(
    float y, int subslice, uint32_t pid, const Placement& placement, std::vector<Vertex>& out_vertices)
{
    glm::vec4 color = k_brick_colors[placement.cid].color_u8();
    color /= 255.0f;

    const auto& brick = k_bricks[placement.bid];

    Vertex template_{};
    template_.color = color;

    // Height of the stud in normalized coordinates (i.e. if the 1x1 brick is 1x1 units)
    const float k_stud_h = 0.177083333f;
    const float k_stud_r = 0.25f;
    const int k_stud_subdivisions = 4;
    const float k_brick_height = 1.23076923f;
    const float k_brick_slice_height = k_brick_height / 3.0f;

    float h = subslice == -1 ? k_brick_height : k_brick_slice_height;

    for (int bz = 0; bz < BRICK_MAX_EXTENT_Z; ++bz) {
        for (int bx = 0; bx < BRICK_MAX_EXTENT_X; ++bx) {
            if (brick[bz][bx]) {
                int x = placement.x + bx;
                int z = placement.z + bz;

                // Bottom quad
                template_.normal = glm::vec3(0, -1, 0);
                set_outline_guide(pid, 0, subslice, template_);
                add_quad(
                    {glm::vec3(x, y, z), glm::vec3(x + 1, y, z), glm::vec3(x + 1, y, z + 1), glm::vec3(x, y, z + 1)},
                    template_,
                    out_vertices);
                // Top quad
                template_.normal = glm::vec3(0, 1, 0);
                set_outline_guide(pid, 1, subslice, template_);
                add_quad({glm::vec3(x, y + h, z),
                          glm::vec3(x + 1, y + h, z),
                          glm::vec3(x + 1, y + h, z + 1),
                          glm::vec3(x, y + h, z + 1)},
                         template_,
                         out_vertices);
                // Stud
                add_y_cylinder(glm::vec3(x + 0.5f, y + h, z + 0.5f),
                               k_stud_h,
                               k_stud_r,
                               k_stud_subdivisions,
                               pid,
                               subslice,
                               template_,
                               out_vertices);
                // -Z edge
                set_outline_guide(pid, 4, subslice, template_);
                if (bz == 0 || !brick[bz - 1][bx]) {
                    template_.normal = glm::vec3(0, 0, -1);
                    add_quad({glm::vec3(x, y, z),
                              glm::vec3(x, y + h, z),
                              glm::vec3(x + 1, y + h, z),
                              glm::vec3(x + 1, y, z)},
                             template_,
                             out_vertices);
                }
                // +Z edge
                set_outline_guide(pid, 5, subslice, template_);
                if (bz == BRICK_MAX_EXTENT_Z - 1 || !brick[bz + 1][bx]) {
                    template_.normal = glm::vec3(0, 0, 1);
                    add_quad({glm::vec3(x, y, z + 1),
                              glm::vec3(x, y + h, z + 1),
                              glm::vec3(x + 1, y + h, z + 1),
                              glm::vec3(x + 1, y, z + 1)},
                             template_,
                             out_vertices);
                }
                // -X edge
                set_outline_guide(pid, 6, subslice, template_);
                if (bx == 0 || !brick[bz][bx - 1]) {
                    template_.normal = glm::vec3(-1, 0, 0);
                    add_quad({glm::vec3(x, y, z),
                              glm::vec3(x, y + h, z),
                              glm::vec3(x, y + h, z + 1),
                              glm::vec3(x, y, z + 1)},
                             template_,
                             out_vertices);
                }
                // +X edge
                set_outline_guide(pid, 7, subslice, template_);
                if (bx == BRICK_MAX_EXTENT_X - 1 || !brick[bz][bx + 1]) {
                    template_.normal = glm::vec3(1, 0, 0);
                    add_quad({glm::vec3(x + 1, y, z + 1),
                              glm::vec3(x + 1, y + h, z + 1),
                              glm::vec3(x + 1, y + h, z),
                              glm::vec3(x + 1, y, z)},
                             template_,
                             out_vertices);
                }
            }
        }
    }
}

void BrickModelBuilder::add_placement(int slice_y, uint32_t pid, const Placement& placement)
{
    std::vector<Vertex> vertices{};
    vertices.reserve(1 << 20 /* 1MB */);

    const float k_brick_height = 1.23076923f;
    const float k_brick_slice_height = k_brick_height / 3.0f;

    float y = slice_y * k_brick_height;

    if (placement.subslice_mask == 0x7) {
        add_placement(y, -1 /* Complete brick */, pid, placement, vertices);
    } else {
        for (int subslice = 0; subslice < 3; ++subslice) {
            if ((placement.subslice_mask >> subslice) & 1) add_placement(y, subslice, pid, placement, vertices);
            y += k_brick_slice_height;
        }
    }

    m_mesh->vertices.insert(m_mesh->vertices.end(), vertices.begin(), vertices.end());
    // No indices

    m_mesh->update_min_max();
}
