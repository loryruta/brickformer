#include "Slicer.cuh"

#include <thrust/copy.h>

#include "intersections.cuh"

using namespace lego_builder;

Slicer::Slicer(const Model& model, uint32_t slice_side)
{
    m_slice_side = slice_side;

    m_model_d = upload_model(model);

    linearize_triangles(model);
}

void Slicer::linearize_triangles(const Model& model)
{
    std::vector<TriRef> triangles{};
    triangles.reserve(model.m_meshes.size() * 1024);

    for (uint32_t mi = 0; mi < model.m_meshes.size(); mi++)
    {
        const Mesh& mesh = model.m_meshes.at(mi);

        assert(mesh.m_indices.size() % 3 == 0);

        for (uint32_t ti = 0; ti < mesh.m_indices.size() / 3; ti++)
        {
            TriRef tri{};
            tri.m_vertices[0] = mesh.m_vertices[mesh.m_indices[ti * 3 + 0]].m_position;
            tri.m_vertices[1] = mesh.m_vertices[mesh.m_indices[ti * 3 + 1]].m_position;
            tri.m_vertices[2] = mesh.m_vertices[mesh.m_indices[ti * 3 + 2]].m_position;
            tri.m_triangle_idx = ti;
            tri.m_mesh_idx = mi;
            triangles.push_back(tri);
        }
    }

    printf("[Slicer] Model triangles linearized to %zu triangles\n", triangles.size());

    m_triangles_d.resize(triangles.size());
    thrust::copy(triangles.begin(), triangles.end(), m_triangles_d.begin());
}

__device__
void set_voxel(int x, int z, const glm::vec4& color, SliceT* out_slice)
{
    assert(x >= 0 && x <= out_slice->m_width);
    assert(z >= 0 && z <= out_slice->m_height);

    const size_t k_spread = 1;

    for (int nx = x - k_spread; nx <= x + k_spread; nx++)
    {
        for (int nz = z - k_spread; nz <= z + k_spread; nz++)
        {
            if (!out_slice->is_valid_pixel(x, z)) continue;

            out_slice->write_pixel(nx, nz, color);
        }
    }
}

__device__
glm::vec4 interp_triangle_color(const glm::vec3& p, const TriRef& tri_ref, const DeviceModel& model)
{
    glm::vec3 d0 = tri_ref.m_vertices[1] - tri_ref.m_vertices[0];
    glm::vec3 d1 = tri_ref.m_vertices[2] - tri_ref.m_vertices[1];

    const glm::vec3& v0 = tri_ref.m_vertices[0];
    const glm::vec3& v1 = tri_ref.m_vertices[1];
    const glm::vec3& v2 = tri_ref.m_vertices[2];

    glm::vec2 pv0, pv1, pv2, pp;

    pv0.x = glm::dot(v0, d0);
    pv0.y = glm::dot(v0, d1);
    pv1.x = glm::dot(v1, d0);
    pv1.y = glm::dot(v1, d1);
    pv2.x = glm::dot(v2, d0);
    pv2.y = glm::dot(v2, d1);

    pp.x = glm::dot(p, d0);
    pp.y = glm::dot(p, d1);

    // Barycentric Coordinates; reference:
    // https://codeplea.com/triangular-interpolation

    float dn = (pv1.y - pv2.y) * (pv0.x - pv2.x) + (pv2.x - pv1.x) * (pv0.y - pv2.y);
    float w0 = ((pv1.y - pv2.y) * (p.x - pv2.x) + (pv2.x - pv1.x) * (p.y - pv2.y)) / dn;
    float w1 = ((pv2.y - pv0.y) * (p.x - pv2.x) + (pv0.x - pv2.x) * (p.y - pv2.y)) / dn;
    float w2 = 1.0f - w0 - w1;

    const DeviceMesh& mesh = model.m_meshes[tri_ref.m_mesh_idx];

    const Vertex& v0a = mesh.m_vertices[mesh.m_indices[tri_ref.m_triangle_idx * 3 + 0]];
    const Vertex& v1a = mesh.m_vertices[mesh.m_indices[tri_ref.m_triangle_idx * 3 + 1]];
    const Vertex& v2a = mesh.m_vertices[mesh.m_indices[tri_ref.m_triangle_idx * 3 + 2]];

    glm::vec2 texcoord = v0a.m_texcoord * w0 + v1a.m_texcoord * w1 + v2a.m_texcoord * w2;
    //glm::vec4 color = v0a.m_color * w0 + v1a.m_color * w1 + v2a.m_color * w2; TODO apply color (remember it's [0, 1])

    glm::vec4 out_color{};

    if (mesh.m_texture_idx >= 0)
    {
        cudaTextureObject_t texture = model.m_textures[mesh.m_texture_idx];

        out_color = to_fvec4(tex2D<uchar4>(texture, texcoord.x, texcoord.y));
    }

    return out_color;
}

__device__
void voxelize_triangle_to_slice(const TriRef& tri_ref,
                                const DeviceModel& model,
                                uint32_t slice_y, SliceT* out_slice,
                                size_t& out_num_iterations,
                                size_t& out_num_intersections
                                )
{
    glm::ivec3 tri_min = glm::min(tri_ref.m_vertices[0], glm::min(tri_ref.m_vertices[1], tri_ref.m_vertices[2]));
    glm::ivec3 tri_max = glm::max(tri_ref.m_vertices[0], glm::max(tri_ref.m_vertices[1], tri_ref.m_vertices[2]));

    size_t num_iterations = 0;
    size_t num_intersections = 0;

    for (int x = glm::max(tri_min.x, 0); x < glm::min<int>(tri_max.x, out_slice->m_width); x++)
    {
        for (int z = glm::max(tri_min.z, 0); z < glm::min<int>(tri_max.z, out_slice->m_height); z++)
        {
            Box int_box{};
            int_box.m_min = glm::vec3(x, slice_y, z);
            int_box.m_max = int_box.m_min + 1.0f;

            Triangle int_tri{};
            int_tri.m_a = tri_ref.m_vertices[0];
            int_tri.m_b = tri_ref.m_vertices[1];
            int_tri.m_c = tri_ref.m_vertices[2];

            if (intersect_triangle(int_box, int_tri))
            {
                glm::vec4 color = interp_triangle_color(int_box.centroid(), tri_ref, model);

                set_voxel(x, z, color, out_slice);
                num_intersections++;
            }

            num_iterations++;
        }
    }

    out_num_iterations = num_iterations;
    out_num_intersections = num_intersections;
}

void Slicer::slice(uint32_t slice_y, SliceT& out_slice)
{
    assert(out_slice.m_width >= m_slice_side && out_slice.m_height >= m_slice_side);

    out_slice.fill(0);

    int32_t* max_iterations_d = to_device(INT32_MIN);
    int32_t* min_iterations_d = to_device(INT32_MAX);

    int32_t* tot_intersections_d = to_device(0);
    int32_t* max_intersections_d = to_device(INT32_MIN);
    int32_t* min_intersections_d = to_device(INT32_MAX);

    const DeviceModel* model_d = m_model_d;
    SliceT* out_slice_d = to_device(out_slice);  // TODO input already on device image (move to host for debug-only)

    thrust::for_each(m_triangles_d.begin(), m_triangles_d.end(), [=] __device__ (const TriRef &tri) {
        size_t num_iterations;
        size_t num_intersections;
        voxelize_triangle_to_slice(tri, *model_d, slice_y, out_slice_d, num_iterations, num_intersections);

        atomicMax(max_iterations_d, num_iterations);
        atomicMin(min_iterations_d, num_iterations);

        atomicAdd(tot_intersections_d, num_intersections);
        atomicMax(max_intersections_d, num_intersections);
        atomicMin(min_intersections_d, num_intersections);
     });

    CHECK_CU(cudaDeviceSynchronize());

    // TODO (idea): a single thread could take too many iterations (because triangle AABB is too large), and it could be
    //  a BOTTLENECK.
    //  Solution: consider splitting large triangles before voxelization

    printf("[Slicer] Slice Y: %d; Min iters: %d, Max iters: %d, Tot intersections: %d, Min intersections: %d, Max intersections: %d\n",
        slice_y,
        to_host(min_iterations_d),
        to_host(max_iterations_d),
        to_host(tot_intersections_d),
        to_host(min_intersections_d),
        to_host(max_intersections_d)
        );
}
