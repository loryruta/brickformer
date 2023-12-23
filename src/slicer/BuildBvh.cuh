#pragma once

#include "Model.hpp"
#include "intersections.cuh"
#include "../misc.cuh"

#define BVH_LEAF_NODE    (UINT32_MAX - 1)
#define BVH_PADDING_NODE UINT32_MAX

namespace lego_builder
{
    struct Node
    {
        uint32_t m_morton_code;
        uint32_t m_mesh_idx;
        uint32_t m_triangle_idx;

        glm::vec3 m_min = glm::vec3(std::numeric_limits<float>::infinity());
        glm::vec3 m_max = glm::vec3(-std::numeric_limits<float>::infinity());

        ///< If neither BVH_LEAF_NODE nor BVH_PADDING_NODE, then it's a parent node and m_type = index to children level.
        union
        {
            uint32_t m_type;
            uint32_t m_children_idx;
        };
    };

    struct Bvh
    {
        size_t m_root_idx;
        const Node* m_nodes;
    };

    class BuildBvh
    {
    public:
        explicit BuildBvh() = default;
        ~BuildBvh() = default;

        const Bvh* build(const Model& model);
    };

    template<typename CALLBACK>
    __device__ void traverse_bvh(const Box& in_box, const Bvh* bvh, glm::mat4 transform, CALLBACK callback)
    {
        // TODO no transform here

        uint32_t warp_idx = (blockIdx.x * 1024 + threadIdx.x) / 32;
        uint32_t lane_idx = threadIdx.x % 32;

        uint32_t visit_mask = 0;

        uint32_t nodes_base_idx = bvh->m_root_idx;

        struct StackEntry
        {
            uint32_t m_visit_mask;  // A bit mask whose i-th bit is set if the node was not visited
            uint32_t m_base_idx;    // The index to the first node in the hierarchy level
        } stack[8];
        uint32_t stack_idx = 0;

        bool should_print = glm::abs(in_box.m_min.y - 9.0f) <= 0.001f && warp_idx == 30798 && lane_idx == 0;
        uint32_t num_iterations = 0;

        while (true)
        {
            /*
            ++num_iterations;
            if (num_iterations > 1000000)  // TODO it's doing too many iterations right now!
            {
                if (should_print) printf("FORCE EXIT; Warp: %d, Num iters: %d\n", warp_idx, num_iterations);
                break;
            }*/

            // If the visit mask isn't initialized, initialize it
            if (visit_mask == 0)
            {
                // CALC INTERSECTIONS
                const Node* node = &bvh->m_nodes[nodes_base_idx + lane_idx];

                Box node_box{};
                node_box.m_min = transform * glm::vec4(node->m_min, 1.0f);  // Min/max is already transformed with mesh transform
                node_box.m_max = transform * glm::vec4(node->m_max, 1.0f);

                bool should_visit = node->m_type != BVH_PADDING_NODE;
                if (should_visit) should_visit = intersect_box(in_box, node_box);

                if (should_print) printf("CALC INTERSECTIONS; L: %d, Stack idx: %d, Base node idx: %d, Visit mask: %d, Should visit: %d\n", lane_idx, stack_idx, nodes_base_idx, visit_mask, should_visit);

                visit_mask = __ballot_sync(FULL_MASK, should_visit);
            }

            if (visit_mask == 0)
            {
                while (visit_mask == 0)
                {
                    // POP
                    if (should_print) printf("POP; W: %d, L: %d, Stack idx: %d, Base node idx: %d, Visit mask: %d\n", warp_idx, lane_idx, stack_idx, nodes_base_idx, visit_mask);

                    if (stack_idx == 0) goto end;  // Traversal ended

                    --stack_idx;
                    visit_mask = stack[stack_idx].m_visit_mask;
                    nodes_base_idx = stack[stack_idx].m_base_idx;

                    //++num_iterations;
                    //if (num_iterations > 1024) break;
                }
            }
            else
            {
                uint32_t visit_idx = __ffs(visit_mask) - 1;  // Visit the first eligible node in the current hierarchy
                visit_mask &= ~(1 << visit_idx);  // So we won't visit it again

                const Node* node = &bvh->m_nodes[nodes_base_idx + visit_idx];
                assert(node->m_type != BVH_PADDING_NODE);

                if (node->m_type == BVH_LEAF_NODE)
                {
                    // ADVANCE
                    if (should_print) printf("ADVANCE; L: %d, Stack idx: %d, Base node idx: %d, Visit idx: %d, Node idx: %d, Visit mask: %d\n", lane_idx, stack_idx, nodes_base_idx, visit_idx, nodes_base_idx + visit_idx, visit_mask);

                    assert(node);
                    callback(*node);  // callback(const Node& node);
                }
                else
                {
                    // PUSH
                    if (should_print) printf("PUSH; L: %d, Stack idx: %d, Base node idx: %d, Visit idx: %d, Node idx: %d, Visit mask: %d\n", lane_idx, stack_idx, nodes_base_idx, visit_idx, nodes_base_idx + visit_idx, visit_mask);

                    assert(stack_idx < 8);

                    StackEntry stack_entry{};
                    stack_entry.m_visit_mask = visit_mask;
                    stack_entry.m_base_idx = nodes_base_idx;
                    stack[stack_idx] = stack_entry;
                    ++stack_idx;

                    visit_mask = 0;
                    nodes_base_idx = node->m_children_idx;
                }
            }
        }

    end:
    }
}
