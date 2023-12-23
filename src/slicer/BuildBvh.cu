#include "BuildBvh.cuh"

#include "../misc.cuh"
#include "../primitives.cuh"
#include "../StopWatch.hpp"

#include <glm/gtc/integer.hpp>
#include <thrust/device_ptr.h>
#include <thrust/device_vector.h>
#include <thrust/sort.h>

using namespace lego_builder;


/// Rounds n up to a multiple of m.
template<typename T>
T round_up(T n, T m)  // TODO put in utilities file
{
    if (m == 0) return n;

    T rem = n % m;
    if (rem == 0) return n;
    return n + m - rem;
}

template<>
std::string lego_builder::to_string(const Node& element) // Just to debug the BVH
{
    if (element.m_type == BVH_PADDING_NODE) return "P";
    else if (element.m_type == BVH_LEAF_NODE) return "L";
    else
    {
        return std::to_string(element.m_children_idx);
    }
}

__global__ void calc_morton_code(Node* nodes, glm::mat4 norm_matrix)
{
    size_t node_idx = blockIdx.x * 1024 + threadIdx.x;

    Node& node = nodes[node_idx];
    if (node.m_type != BVH_PADDING_NODE)
    {
        glm::vec3 grid_size = glm::vec3(1 << 10);
        glm::vec3 norm_pos = norm_matrix * glm::vec4((node.m_min + node.m_max) / 2.0f, 1.0f);
        glm::ivec3 grid_idx = norm_pos * grid_size;

        // 32 bits morton code, 10 bits per component
        uint32_t morton_code = 0;
        while (grid_idx != glm::ivec3(0))
        {
            morton_code <<= 3;

            morton_code |= (grid_idx.x & 1);
            morton_code |= (grid_idx.y & 1) << 1;
            morton_code |= (grid_idx.z & 1) << 2;

            grid_idx >>= 1;
        }
        node.m_morton_code = morton_code;
    }
}


struct NodeMortonCodeComparator
{
    __device__ bool operator()(const Node& lhs, const Node& rhs) const
    {
        return lhs.m_morton_code < rhs.m_morton_code;
    }
};

void sort_by_morton_code(Node* d_nodes, size_t num_nodes)
{
    thrust::device_ptr<Node> d_ptr = thrust::device_ptr<Node>(d_nodes);
    thrust::sort(thrust::device, d_ptr, d_ptr + num_nodes, NodeMortonCodeComparator{});
}

__global__ void reduce_bvh_level(Node* nodes, size_t level_base_idx, size_t num_level_nodes)
{
    uint32_t i = blockIdx.x * 1024 + threadIdx.x;
    uint32_t warp_idx = i >> 5;

    uint32_t node_idx = level_base_idx + i;
    uint32_t parent_node_idx = level_base_idx + num_level_nodes + warp_idx;

    Node& node = nodes[node_idx];
    Node& parent_node = nodes[parent_node_idx];

    bool valid_parent = __any_sync(FULL_MASK, node.m_type != BVH_PADDING_NODE);
    if (valid_parent)
    {
        if (node.m_type == BVH_PADDING_NODE)
        {
            node.m_min = glm::vec3(-INFINITY);
            node.m_max = glm::vec3(INFINITY);
        }

        parent_node.m_min.x = warp_min(node.m_min.x);
        parent_node.m_min.y = warp_min(node.m_min.y);
        parent_node.m_min.z = warp_min(node.m_min.z);

        parent_node.m_max.x = warp_max(node.m_max.x);
        parent_node.m_max.y = warp_max(node.m_max.y);
        parent_node.m_max.z = warp_max(node.m_max.z);

        parent_node.m_children_idx = level_base_idx;
    }
    else if ((node_idx & 0x1F) == 0)
    {
        // If children nodes are all invalid (padding nodes), also parent node is invalid
        parent_node.m_type = BVH_PADDING_NODE;
    }
}

const Bvh* BuildBvh::build(const Model& model)
{
    std::vector<Node> leaf_nodes;
    leaf_nodes.reserve(model.m_meshes.size() * 1024);

    // Initialize BVH first level as a flatten list of Model's triangles (no meshes)
    for (size_t mi = 0; mi < model.m_meshes.size(); mi++)
    {
        const Mesh& mesh = model.m_meshes.at(mi);

        size_t base_idx = leaf_nodes.size();

        assert(mesh.m_indices.size() % 3 == 0);  // Should be already checked
        size_t num_triangles = mesh.m_indices.size() / 3;
        leaf_nodes.resize(leaf_nodes.size() + num_triangles);

        for (size_t ti = 0; ti < num_triangles; ti++)
        {
            const Vertex& v0 = mesh.m_vertices.at(mesh.m_indices.at(ti * 3 + 0));
            const Vertex& v1 = mesh.m_vertices.at(mesh.m_indices.at(ti * 3 + 1));
            const Vertex& v2 = mesh.m_vertices.at(mesh.m_indices.at(ti * 3 + 2));

            glm::vec3 p0 = mesh.m_transform * glm::vec4(v0.m_position, 1.0f);
            glm::vec3 p1 = mesh.m_transform * glm::vec4(v1.m_position, 1.0f);
            glm::vec3 p2 = mesh.m_transform * glm::vec4(v2.m_position, 1.0f);

            Node& node = leaf_nodes[base_idx + ti];
            node.m_type = BVH_LEAF_NODE;
            node.m_min = glm::min(glm::min(glm::min(node.m_min, p0), p1), p2);
            node.m_max = glm::max(glm::max(glm::max(node.m_max, p0), p1), p2);
            node.m_triangle_idx = ti;
            node.m_mesh_idx = mi;
        }
    }

    //
    size_t cur_level_nodes;
    size_t num_blocks;

    // Calculate the total BVH size by rounding each level to a multiple of 1024 (ease dispatch)
    size_t num_bvh_nodes = 0;
    cur_level_nodes = leaf_nodes.size();
    while (true)
    {
        num_bvh_nodes += round_up<size_t>(cur_level_nodes, 1024);
        if (cur_level_nodes <= 32) break;
        cur_level_nodes = div_round_up<size_t>(cur_level_nodes, 32);
    }

    printf("[BuildBvh] Bvh size: %zu nodes\n", num_bvh_nodes);

    // Allocate the complete BVH in device memory, initialize first level
    Node* d_nodes;
    CHECK_CU(cudaMalloc(&d_nodes, num_bvh_nodes * sizeof(Node)));

    CHECK_CU(cudaMemset(d_nodes, BVH_PADDING_NODE, num_bvh_nodes * sizeof(Node)));
    CHECK_CU(cudaDeviceSynchronize());

    CHECK_CU(cudaMemcpy(d_nodes, leaf_nodes.data(), leaf_nodes.size() * sizeof(Node), cudaMemcpyHostToDevice));

    // Calculate the morton codes of leaf nodes
    num_blocks = div_round_up<size_t>(leaf_nodes.size(), 1024);
    calc_morton_code<<<num_blocks, 1024>>>(d_nodes, model.normalization_matrix());
    CHECK_CU(cudaDeviceSynchronize());

    // Sort leaf nodes by morton code
    sort_by_morton_code(d_nodes, leaf_nodes.size());

    // Reduce every pair of adjacent levels
    size_t cur_level_base_idx = 0;
    cur_level_nodes = leaf_nodes.size();
    size_t level_idx = 0;  // Just for logging
    while (true)
    {
        if (cur_level_nodes <= 32) break;

        size_t rounded_level_nodes = round_up<size_t>(cur_level_nodes, 1024);
        num_blocks = rounded_level_nodes >> 10;

        size_t next_level_nodes = div_round_up<size_t>(cur_level_nodes, 32);

        printf("[BuildBvh] Level: %zu; Base index: %zu, Level nodes: %zu, Rounded nodes: %zu, Next level nodes: %zu, Num blocks: %zu",
               level_idx,
               cur_level_base_idx,
               cur_level_nodes, rounded_level_nodes,
               next_level_nodes,
               num_blocks
               );

        StopWatch stop_watch{};

        reduce_bvh_level<<<num_blocks, 1024>>>(d_nodes, cur_level_base_idx, rounded_level_nodes);
        CHECK_CU(cudaDeviceSynchronize());

        printf(", Elapsed time: %s\n", stop_watch.elapsed_time_str().c_str());

        cur_level_base_idx += rounded_level_nodes;
        cur_level_nodes = next_level_nodes;

        ++level_idx;
    }

    printf("[BuildBvh] BVH construction finished; Size: %zu nodes, Root idx: %zu\n", num_bvh_nodes, cur_level_base_idx);

    //dump_device_buffer(d_nodes, num_bvh_nodes);

    Bvh bvh{};
    bvh.m_root_idx = cur_level_base_idx;
    bvh.m_nodes = d_nodes;
    return to_device(bvh);
}
