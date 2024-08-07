#include "Slicer.cuh"

#include <thrust/copy.h>

#include "util/StaticVector.cuh"
#include "util/intersections.cuh"

#define MAX_POLYGON_SIZE 8  ///< The maximum number of vertices that are allowed (after e.g. triangle clipping)
#define SET_VOXEL_SPREAD 0  ///< The radius of the area where the voxel is set (0 = only set position)

using namespace lego_builder;

Slicer::Slicer(const Model& model, int resolution, float alpha_test_threshold) :
    m_resolution(resolution),
    m_alpha_test_threshold(alpha_test_threshold)
{
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

    for (int nx = x - SET_VOXEL_SPREAD; nx <= x + SET_VOXEL_SPREAD; nx++)
    {
        for (int nz = z - SET_VOXEL_SPREAD; nz <= z + SET_VOXEL_SPREAD; nz++)
        {
            if (!out_slice->is_valid_pixel(x, z)) continue;
            glm::vec<4, uint8_t> u8_color = glm::clamp(color * 255.f, 0.f, 255.f);
            out_slice->write_pixel(nx, nz, u8_color);
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
    float w0 = ((pv1.y - pv2.y) * (pp.x - pv2.x) + (pv2.x - pv1.x) * (pp.y - pv2.y)) / dn;
    float w1 = ((pv2.y - pv0.y) * (pp.x - pv2.x) + (pv0.x - pv2.x) * (pp.y - pv2.y)) / dn;
    float w2 = 1.0f - w0 - w1;

    const DeviceMesh& mesh = model.m_meshes[tri_ref.m_mesh_idx];

    const Vertex& v0a = mesh.m_vertices[mesh.m_indices[tri_ref.m_triangle_idx * 3 + 0]];
    const Vertex& v1a = mesh.m_vertices[mesh.m_indices[tri_ref.m_triangle_idx * 3 + 1]];
    const Vertex& v2a = mesh.m_vertices[mesh.m_indices[tri_ref.m_triangle_idx * 3 + 2]];

    glm::vec2 texcoord = v0a.m_texcoord * w0 + v1a.m_texcoord * w1 + v2a.m_texcoord * w2;
    //glm::vec4 color = v0a.m_color * w0 + v1a.m_color * w1 + v2a.m_color * w2; TODO apply vertex color (remember it's [0, 1])

    glm::vec4 out_color = mesh.m_color;

    if (mesh.m_texture_idx >= 0)
    {
        cudaTextureObject_t texture = model.m_textures[mesh.m_texture_idx];
        out_color *= to_fvec4(tex2D<float4>(texture, texcoord.x, texcoord.y));
    }

    return out_color;
}

__device__
int8_t eval_cut_centrality(
    glm::vec3 bm, glm::vec3 bM,
    const glm::vec3& ta, const glm::vec3& tb, const glm::vec3& tc
    )
{
    const glm::vec3& p0 = ta;
    glm::vec3 d1 = glm::normalize(tb - ta);
    glm::vec3 d2 = glm::normalize(tc - ta);

    glm::vec3 abc = glm::cross(d1, d2);
    bm -= p0, bM -= p0;

    int8_t result = 0;
    result += abc.x * bm.x + abc.y * bm.y + abc.z * bm.z > 0 ? 1 : -1;  // 000
    result += abc.x * bm.x + abc.y * bm.y + abc.z * bM.z > 0 ? 1 : -1;  // 001
    result += abc.x * bm.x + abc.y * bM.y + abc.z * bm.z > 0 ? 1 : -1;  // 010
    result += abc.x * bm.x + abc.y * bM.y + abc.z * bM.z > 0 ? 1 : -1;  // 011
    result += abc.x * bM.x + abc.y * bm.y + abc.z * bm.z > 0 ? 1 : -1;  // 100
    result += abc.x * bM.x + abc.y * bm.y + abc.z * bM.z > 0 ? 1 : -1;  // 101
    result += abc.x * bM.x + abc.y * bM.y + abc.z * bm.z > 0 ? 1 : -1;  // 110
    result += abc.x * bM.x + abc.y * bM.y + abc.z * bM.z > 0 ? 1 : -1;  // 111
    if (result < 0) result = -result;
    return result;
}

__device__
glm::vec3 plane_line_intersection(
    const glm::vec3& l1,
    const glm::vec3& l2,
    const glm::vec3& po,
    const glm::vec3& pn
    )
{
    glm::vec3 ld = l2 - l1;
    float t = glm::dot(po - l1, pn) / glm::dot(ld, pn);
    return l1 + ld * t;
}

__device__
void clip_face_with_plane(
    const StaticVector<glm::vec3, MAX_POLYGON_SIZE>& face,
    const glm::vec3& po, const glm::vec3& pn,
    StaticVector<glm::vec3, MAX_POLYGON_SIZE>& out_face
    )
{
    const float k_epsilon = 0.001f;

    for (int i = 0; i < face.size(); i++)
    {
        const glm::vec3& v0 = face[i];
        const glm::vec3& v1 = face[pmod(i + 1, face.size())];

        bool v0i = glm::dot(v0 - po, pn) < k_epsilon;  // v0 inside
        bool v1i = glm::dot(v1 - po, pn) < k_epsilon;  // v1 inside

        if (v0i) out_face.push_back(v0);

        if ((!v0i && v1i) || (v0i && !v1i))
        {
            glm::vec3 iv = plane_line_intersection(v0, v1, po, pn);
            out_face.push_back(iv);
        }
    }
}

__device__
void clip_face_with_aabb(
    StaticVector<glm::vec3, MAX_POLYGON_SIZE>& face,  // Input & output
    const glm::vec3& bmin, const glm::vec3& bmax
    )
{
    StaticVector<glm::vec3, MAX_POLYGON_SIZE> face2;

    // bmin.x
    clip_face_with_plane(face, bmin, {-1, 0, 0}, face2);

    // bmin.y
    face.clear();
    clip_face_with_plane(face2, bmin, {0, -1, 0}, face);

    // bmin.z
    face2.clear();
    clip_face_with_plane(face, bmin, {0, 0, -1}, face2);

    // bmax.x
    face.clear();
    clip_face_with_plane(face2, bmax, {1, 0, 0}, face);

    // bmax.y
    face2.clear();
    clip_face_with_plane(face, bmax, {0, 1, 0}, face2);

    // bmax.z
    face.clear();
    clip_face_with_plane(face2, bmax, {0, 0, 1}, face);
}

__device__
float calc_triangle_area(const glm::vec2& v0, const glm::vec2& v1, const glm::vec2& v2)
{
    return 0.5f * glm::abs(v0.x * (v1.y - v2.y) + v1.x * (v2.y - v0.y) + v2.x * (v0.y - v1.y));
}

__device__
float calc_convex_face_area(
    const StaticVector<glm::vec3, MAX_POLYGON_SIZE>& face,
    const glm::vec3& pd1,
    const glm::vec3& pd2
)
{
    if (face.size() < 3) return 0.0f;

    const glm::vec3& v0 = face[0];

    glm::vec2 pv0{0, 0};

    float area = 0.0f;
    for (int i = 1; i < face.size() - 1; i++)
    {
        const glm::vec3& v1 = face[i];
        const glm::vec3& v2 = face[i + 1];

        glm::vec2 pv1{glm::dot(v1 - v0, pd1), glm::dot(v1 - v0, pd2)};
        glm::vec2 pv2{glm::dot(v2 - v0, pd1), glm::dot(v2 - v0, pd2)};

        area += calc_triangle_area(pv0, pv1, pv2);
    }
    return area;
}

__device__
void voxelize_triangle_to_slice(const TriRef& tri_ref,
                                const DeviceModel& model,
                                uint32_t slice_y,
                                float alpha_test_threshold,
                                SliceT* out_slice,
                                size_t& out_num_iterations,
                                size_t& out_num_intersections
                                )
{
    const glm::vec3& a = tri_ref.m_vertices[0];
    const glm::vec3& b = tri_ref.m_vertices[1];
    const glm::vec3& c = tri_ref.m_vertices[2];

    glm::ivec3 tri_min = glm::floor(glm::min(a, glm::min(b, c)));
    glm::ivec3 tri_max = glm::floor(glm::max(a, glm::max(b, c)));

    size_t num_iterations = 0;
    size_t num_intersections = 0;

    for (int x = glm::max(tri_min.x, 0); x <= glm::min<int>(tri_max.x, out_slice->m_width); x++)
    {
        for (int z = glm::max(tri_min.z, 0); z <= glm::min<int>(tri_max.z, out_slice->m_height); z++)
        {
            ++num_iterations;

            glm::vec3 bmin{x, slice_y, z};

            StaticVector<glm::vec3, MAX_POLYGON_SIZE> face{};
            face.push_back(a);
            face.push_back(b);
            face.push_back(c);
            clip_face_with_aabb(face, bmin, bmin + 1.0f);

            if (face.size() == 0) continue;  // Not intersecting

            //float area = calc_convex_face_area(face, d1, d2);

            /*
            bool check = area < tarea + 0.01f;
            if (!check)
            {
                printf("(%f, %f, %f)\n", a.x, a.y, a.z);
                printf("(%f, %f, %f)\n", b.x, b.y, b.z);
                printf("(%f, %f, %f)\n", c.x, c.y, c.z);

                printf("\n");


                for (int i = 0; i < face.size(); i++)
                {
                    const glm::vec3& v = face[i];
                    printf("%d : (%f, %f, %f)\n", i, v.x, v.y, v.z);
                }

                printf("area: %f, tarea: %f\n", area, tarea);
            }
            assert(check);
            */

            //area = glm::max(area / tarea, area);  // 2nd is / 1.0f (max area within cube)
            //if (area < 0.2f) continue;
            //printf("Voxel (%d, %d, %d) ; Face: %d, Area: %f\n", x, slice_y, z, int(face.size()), area);
            //if (area < 0.2f) continue;  // Intersection not central enough

            glm::vec4 color = interp_triangle_color(bmin + 0.5f, tri_ref, model);
            if (color.a < alpha_test_threshold) continue;

            //glm::vec4 color = {255,0,0,255};

//            glm::vec4 color;
//            color.r = glm::fract(sin(x) * 1e4) * 255.0f;
//            color.g = glm::fract(cos(slice_y * 124.0f) * 43758.0f) * 255.0f;
//            color.b = glm::fract(cos(z * 758.0f) * 43758.0f) * 255.0f;
//            color.a = 255.0f;

            set_voxel(x, z, color, out_slice);
            //printf("Set voxel: (%f,%f,%f,%f)\n", color.r, color.g, color.b, color.a);
            ++num_intersections;
        }
    }

    out_num_iterations = num_iterations;
    out_num_intersections = num_intersections;
}

void Slicer::slice(uint32_t slice_y, SliceT& out_slice)
{
    assert(out_slice.m_width >= m_resolution && out_slice.m_height >= m_resolution);

    out_slice.fill(0);

    int32_t* max_iterations_d = to_device(INT32_MIN);
    int32_t* min_iterations_d = to_device(INT32_MAX);

    int32_t* tot_intersections_d = to_device(0);
    int32_t* max_intersections_d = to_device(INT32_MIN);
    int32_t* min_intersections_d = to_device(INT32_MAX);

    const DeviceModel* model_d = m_model_d;
    float alpha_test_threshold = m_alpha_test_threshold;
    SliceT* out_slice_d = to_device(out_slice);  // TODO input already on device image (move to host for debug-only)

    thrust::for_each(m_triangles_d.begin(), m_triangles_d.end(), [=] __device__ (const TriRef& tri) {
        size_t num_iterations;
        size_t num_intersections;
        voxelize_triangle_to_slice(tri, *model_d, slice_y, alpha_test_threshold, out_slice_d, num_iterations, num_intersections);

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
