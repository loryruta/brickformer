#include "BrickModel.h"

#include <algorithm>
#include <cstring>
#include <execution> // For std::execution::par
#include <utility>

#include "bricks.h"
#include "lego_dataset.h"
#include "util/misc.h"
#include "video/BrickRenderer.h"

using namespace bf;

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

BrickModel::BrickModel() { m_mesh = &m_model.m_meshes.emplace_back(); }

BrickModel::BrickModel(std::string name) : BrickModel() { m_name = std::move(name); }

BrickModel::BrickModel(BrickModel&& other) noexcept
{
    m_name = std::move(other.m_name);
    m_model = std::move(other.m_model);
    m_mesh = other.m_mesh;
    m_subslice_ranges = std::move(other.m_subslice_ranges);
    m_brick_quantities = std::move(other.m_brick_quantities);
}

size_t BrickModel::bytesize() const
{
    size_t bytesize = sizeof(BrickModel);
    bytesize += m_name.capacity() * sizeof(char);
    bytesize += m_model.bytesize();
    bytesize += m_subslice_ranges.capacity() * sizeof(m_subslice_ranges[0]);
    // Approximate unordered_map bytesize
    bytesize += m_brick_quantities.size() * sizeof(decltype(m_brick_quantities)::key_type) +
                sizeof(decltype(m_brick_quantities)::mapped_type);
    return bytesize;
}

void BrickModel::add_placement(
    int slice_y, int subslice, uint32_t pid, const Placement& placement, std::vector<Vertex>& out_vertices)
{
    glm::vec3 color = k_brick_colors_rgb[placement.cid] / 255.0f;
    const auto& brick = k_bricks[placement.bid];

    Vertex template_{};
    template_.color = glm::vec4(color, 1.0f);

    // Height of the stud in normalized coordinates (i.e. if the 1x1 brick is 1x1 units)
    const float k_stud_h = 0.2125f;
    const float k_stud_r = 0.3f;
    const int k_stud_subdivisions = 8;
    const float k_brick_height = 1.2f;
    const float k_brick_slice_height = k_brick_height / 3.0f;

    float h = subslice == -1 ? k_brick_height : k_brick_slice_height;

    for (int bz = 0; bz < BRICK_MAX_EXTENT_Z; ++bz) {
        for (int bx = 0; bx < BRICK_MAX_EXTENT_X; ++bx) {
            if (brick[bz][bx]) {
                int x = placement.x + bx;
                int z = placement.z + bz;
                float y = slice_y * k_brick_height + (subslice == -1 ? 0 : subslice * k_brick_slice_height);
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

void BrickModel::add_placement(int slice_y, const Placement& placement, std::vector<Vertex>& out_vertices)
{
    uint32_t pid = m_next_pid++;

    const float k_brick_height = 1.23076923f;
    const float k_brick_slice_height = k_brick_height / 3.0f;

    if (placement.subslice_mask == 0x7) {
        add_placement(slice_y, -1 /* Complete brick */, pid, placement, out_vertices);
    } else {
        for (int subslice = 0; subslice < 3; ++subslice) {
            if ((placement.subslice_mask >> subslice) & 1) {
                add_placement(slice_y, subslice, pid, placement, out_vertices);
            }
        }
    }
}

void BrickModel::add_slice(int slice_y, const std::vector<Placement>& placements)
{
    std::vector<Vertex> subslice0_vertices; // Will also include complete placements
    std::vector<Vertex> subslice1_vertices;
    std::vector<Vertex> subslice2_vertices;
    std::mutex mutex;
    std::for_each(std::execution::par, placements.begin(), placements.end(), [&](const Placement& placement) {
        std::vector<Vertex> vertices;
        vertices.reserve(1 << 20 /* 1MB */);
        add_placement(slice_y, placement, vertices);
        {
            std::lock_guard<std::mutex> lock(mutex);
            if (placement.subslice_mask == 0x7 || placement.subslice_mask == 1) {
                subslice0_vertices.insert(subslice0_vertices.end(), vertices.begin(), vertices.end());
            } else if (placement.subslice_mask == 2) {
                subslice1_vertices.insert(subslice1_vertices.end(), vertices.begin(), vertices.end());
            } else if (placement.subslice_mask == 4) {
                subslice2_vertices.insert(subslice2_vertices.end(), vertices.begin(), vertices.end());
            }
        }
    });

    // Add subslice 0 vertices
    size_t subslice0_start = m_mesh->vertices.size();
    m_mesh->vertices.insert(m_mesh->vertices.end(), subslice0_vertices.begin(), subslice0_vertices.end());
    size_t subslice1_start = m_mesh->vertices.size();
    if (subslice0_start != subslice1_start) { // Remember [start, end] range
        m_subslice_ranges.emplace_back(subslice0_start, subslice1_start);
    }
    // Add subslice 1 vertices
    m_mesh->vertices.insert(m_mesh->vertices.end(), subslice1_vertices.begin(), subslice1_vertices.end());
    size_t subslice2_start = m_mesh->vertices.size();
    if (subslice1_start != subslice2_start) { // Remember [start, end] range
        m_subslice_ranges.emplace_back(subslice1_start, subslice2_start);
    }
    // Add subslice 2 vertices
    m_mesh->vertices.insert(m_mesh->vertices.end(), subslice2_vertices.begin(), subslice2_vertices.end());
    size_t subslice2_end = m_mesh->vertices.size();
    if (subslice2_start != subslice2_end) { // Remember [start, end] range
        m_subslice_ranges.emplace_back(subslice2_start, subslice2_end);
    }
    m_mesh->update_min_max();

    // Update brick quantities (to export cart)
    // TODO subslices not supported
    for (const Placement& placement : placements) {
        CHECK_STATE(placement.subslice_mask == 0x7, "Subslices are not supported");
        uint32_t key = ((placement.bid & 0xFFFF) << 16) | (placement.cid & 0xFFFF);
        auto [iterator, inserted] = m_brick_quantities.emplace(key, 1);
        if (!inserted) ++iterator->second;
        ++m_total_brick_count;
    }
}
