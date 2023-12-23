#include "Slicer.cuh"

#include "intersections.cuh"

using namespace lego_builder;

Slicer::Slicer(const Bvh* d_bvh,
               const DeviceModel* d_model,
               const glm::vec3& model_min,
               const glm::vec3& model_max,
               uint32_t slice_side
               )
{
    m_slice_side = slice_side;

    m_device_bvh = d_bvh;
    m_device_model = d_model;

    glm::vec3 model_size = model_max - model_min;
    float max_side = glm::max(model_size.x, model_size.z);

    m_num_slices = glm::ceil(model_size.y / max_side * m_slice_side);

    m_transform = glm::identity<glm::mat4>();
    m_transform = glm::scale(m_transform, glm::vec3((1.0f / max_side) * slice_side));
    m_transform = glm::translate(m_transform, -model_min);
}

__global__ void voxelize_slice(
        uint32_t slice_y,
        uint32_t slice_side,
        const DeviceModel* model,
        const Bvh* bvh,
        glm::mat4 model_transform,  // Only translation/scale (otherwise AABB would invalidate)
        DeviceImage<4, uint8_t>* out_slice
        )
{
    size_t i = blockIdx.x * 1024 + threadIdx.x;

    uint32_t warp_idx = i / 32;
    uint32_t lane_idx = i % 32;

    glm::ivec3 slice_idx;
    slice_idx.x = warp_idx % slice_side;
    slice_idx.y = slice_y;
    slice_idx.z = warp_idx / slice_side;

    if (slice_idx.z >= slice_side) return;  // Cube out of bounds; discard warp

    // The model is supposed to fit the slicing grid (using model_transform, externally supplied).
    // The cube is therefore a grid's cell of length 1 on every axis
    Box box{};
    box.m_min = slice_idx;
    box.m_max = slice_idx + 1;

    traverse_bvh(box, bvh, model_transform, [&](const Node& node)
    {
        // Retrieve the triangle geometry from the model
        const DeviceMesh& mesh = model->m_meshes[node.m_mesh_idx];

        const Vertex& v0 = mesh.m_vertices[mesh.m_indices[node.m_triangle_idx * 3 + 0]];
        const Vertex& v1 = mesh.m_vertices[mesh.m_indices[node.m_triangle_idx * 3 + 1]];
        const Vertex& v2 = mesh.m_vertices[mesh.m_indices[node.m_triangle_idx * 3 + 2]];

        Triangle tri{};
        tri.m_a = model_transform * mesh.m_transform * glm::vec4(v0.m_position, 1.0f);
        tri.m_b = model_transform * mesh.m_transform * glm::vec4(v1.m_position, 1.0f);
        tri.m_c = model_transform * mesh.m_transform * glm::vec4(v2.m_position, 1.0f);

        if (intersect_triangle(box, tri))
        {
            // TODO (MUST) get the color

            if (lane_idx == 0)
            {
                out_slice->write_pixel(slice_idx.x, slice_idx.z, {255, 255, 0, 255});
                //printf("Slice %d; Set pixel at (%d, %d)\n", slice_idx.y, slice_idx.x, slice_idx.z);
            }
        }

        // TODO use the warp to check intersection in a neighborhood of the cube (not just for the central cube itself)
        //   If any of these intersects, then set the cell
    });
}

void Slicer::slice(uint32_t slice_y, DeviceImage<4, uint8_t>* out_d_slice)
{
    assert(slice_y < m_num_slices);  // TODO no assert

#ifndef NDEBUG
    DeviceImage<4, uint8_t> host_slice = to_host(out_d_slice);  // Inefficient; debug only
    assert(host_slice.m_width >= m_slice_side && host_slice.m_height >= m_slice_side);  // TODO no assert
#endif

    size_t num_blocks = div_round_up<size_t>(m_slice_side * m_slice_side, 32);  // One warp (32 threads) per slice cell
    voxelize_slice<<<num_blocks, 32 * 32>>>(slice_y, m_slice_side, m_device_model, m_device_bvh, m_transform, out_d_slice);
    CHECK_CU(cudaDeviceSynchronize());
}
