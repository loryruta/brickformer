#pragma once

#include <glm/glm.hpp>

namespace lego_builder
{
    struct Triangle
    {
        glm::vec3 m_a, m_b, m_c;
    };

    struct Box
    {
        glm::vec3 m_min, m_max;
    };

    inline __host__ __device__ void project(const glm::vec3* points, size_t num_points, const glm::vec3& axis, float& out_min, float& out_max)
    {
        float min = INFINITY;
        float max = -INFINITY;
        for (size_t i = 0; i < num_points; i++)
        {
            float val = glm::dot(axis, points[i]);
            if (val < min) min = val;
            if (val > max) max = val;
        }
    }

    inline __host__ __device__ bool intersect_triangle(const Box& box, const Triangle& triangle)
    {
        // Source:
        // https://stackoverflow.com/questions/17458562/efficient-aabb-triangle-intersection-in-c-sharp

        float triangle_min, triangle_max;
        float box_min, box_max;

        const glm::vec3 k_box_normals[]{
                glm::vec3(1, 0, 0),
                glm::vec3(0, 1, 0),
                glm::vec3(0, 0, 1),
        };

        const glm::vec3 k_triangle_edges[]{
                triangle.m_a - triangle.m_b,
                triangle.m_b - triangle.m_c,
                triangle.m_c - triangle.m_a
        };

        const glm::vec3 k_triangle_normal = glm::normalize(glm::cross(k_triangle_edges[0], k_triangle_edges[1]));

        // Test the box normals (x-, y- and z-axes)
        for (size_t i = 0; i < 3; i++)
        {
            project(&triangle.m_a, 3, k_box_normals[i], triangle_min, triangle_max);

            if (triangle_max < box.m_min[i] || triangle_max > box.m_max[i])
            {
                return false;  // No intersection possible
            }
        }

        // Test the triangle normal
        float triangle_offset = glm::dot(k_triangle_normal, triangle.m_a);

        project(&triangle.m_a, 3, k_triangle_normal, box_min, box_max);

        const glm::vec3 k_box_vertices[]{
            box.m_min,
            box.m_max,
            glm::vec3(box.m_max.x, box.m_min.y, box.m_min.z),
            glm::vec3(box.m_min.x, box.m_max.y, box.m_min.z),
            glm::vec3(box.m_min.x, box.m_min.y, box.m_max.z),
            glm::vec3(box.m_max.x, box.m_max.y, box.m_min.z),
            glm::vec3(box.m_min.x, box.m_max.y, box.m_max.z),
            glm::vec3(box.m_max.x, box.m_min.y, box.m_max.z),
        };
        project(&k_box_vertices[0], 8, k_triangle_normal, box_min, box_max);
        if (box_max < triangle_offset || box_min > triangle_offset)
        {
            return false;  // No intersection possible
        }

        // Test the nine edge cross-products
        for (int i = 0; i < 3; i++)
        {
            for (int j = 0; j < 3; j++)
            {
                // The box normals are the same as it's edge tangents
                glm::vec3 axis = glm::cross(k_triangle_edges[i], k_box_normals[j]);
                project(&k_box_vertices[0], 8, axis, box_min, box_max);
                project(&triangle.m_a, 3, axis, triangle_min, triangle_max);
                if (box_max <= triangle_min || box_min >= triangle_max)
                {
                    return false;  // No intersection possible
                }
            }
        }

        return true;  // No separating axis found
    }

    inline __host__ __device__ bool intersect_box(const Box& a, const Box& b)
    {
        // Source:
        // https://gdbooks.gitbooks.io/3dcollisions/content/Chapter2/static_aabb_aabb.html

        return (a.m_min.x <= b.m_max.x && a.m_max.x >= b.m_min.x) &&
               (a.m_min.y <= b.m_max.y && a.m_max.y >= b.m_min.y) &&
               (a.m_min.z <= b.m_max.z && a.m_max.z >= b.m_min.z);
    }
}
