#pragma once

#include "glm/glm.hpp"

namespace lego_builder
{
    struct Triangle
    {
        glm::vec3 m_a, m_b, m_c;

        __host__ __device__
        glm::vec3 min() const { return glm::min(m_a, glm::min(m_b, m_c)); }

        __host__ __device__
        glm::vec3 max() const { return glm::max(m_a, glm::max(m_b, m_c)); }
    };

    struct Box
    {
        glm::vec3 m_min, m_max;

        __host__ __device__
        glm::vec3 centroid() const { return (m_min + m_max) / 2.0f; } // TODO is it called "centroid"?
    };

    __host__ __device__
    inline bool intersect_box(const Box& a, const Box& b)
    {
        // Source:
        // https://gdbooks.gitbooks.io/3dcollisions/content/Chapter2/static_aabb_aabb.html

        return (a.m_min.x <= b.m_max.x && a.m_max.x >= b.m_min.x) &&
               (a.m_min.y <= b.m_max.y && a.m_max.y >= b.m_min.y) &&
               (a.m_min.z <= b.m_max.z && a.m_max.z >= b.m_min.z);
    }

    __host__ __device__
    inline void project(const glm::vec3* points, size_t num_points, const glm::vec3& axis, float& out_min, float& out_max)
    {
        out_min = INFINITY;
        out_max = -INFINITY;
        for (size_t i = 0; i < num_points; i++)
        {
            float val = glm::dot(axis, points[i]);
            if (val < out_min) out_min = val;
            if (val > out_max) out_max = val;
        }
    }

    __host__ __device__
    inline bool intersect_triangle(const Box& box, const Triangle& triangle)
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

        const glm::vec3 k_tri_edges[]{
                triangle.m_b - triangle.m_a,
                triangle.m_c - triangle.m_b,
                triangle.m_a - triangle.m_c
        };

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

        const glm::vec3 k_tri_normal = glm::normalize(glm::cross(k_tri_edges[0], k_tri_edges[1]));

        // Test the box normals (x-, y- and z-axes)
        for (size_t i = 0; i < 3; i++)
        {
            project(&triangle.m_a, 3, k_box_normals[i], triangle_min, triangle_max);

            if (triangle_max < box.m_min[i] || triangle_min > box.m_max[i])
                return false;  // Separating axis exists
        }

        // Test the triangle normal
        project(&triangle.m_a, 3, k_tri_normal, triangle_min, triangle_max);
        project(&k_box_vertices[0], 8, k_tri_normal, box_min, box_max);

        if (box_max < triangle_min || box_min > triangle_max)
            return false;  // Separating axis exists

        // Test the nine edge cross-products
        for (int i = 0; i < 3; i++)
        {
            for (int j = 0; j < 3; j++)
            {
                // The box normals are the same as it's edge tangents
                glm::vec3 axis = glm::cross(k_tri_edges[i], k_box_normals[j]);

                project(&triangle.m_a, 3, axis, triangle_min, triangle_max);
                project(&k_box_vertices[0], 8, axis, box_min, box_max);

                if (box_max < triangle_min || box_min > triangle_max)
                    return false;  // Separating axis exists
            }
        }

        return true;  // No separating axis found, they intersect!
    }

    __host__ __device__
    inline bool intersect_triangle2(const Box& box, const Triangle& tri)
    {
        // Source:
        // https://omnigoat.github.io/2015/03/09/box-triangle-intersection/

        // bounding-box test
        Box tri_box{};
        tri_box.m_min = tri.min();
        tri_box.m_max = tri.max();
        if (!intersect_box(box, tri_box)) return false;

        const glm::vec3 k_tri_edges[]{
            tri.m_b - tri.m_a,
            tri.m_c - tri.m_b,
            tri.m_a - tri.m_c
        };

        const glm::vec3 k_tri_normal = glm::cross(k_tri_edges[0], k_tri_edges[1]);

        // triangle-normal
        auto n = k_tri_normal;

        // p & delta-p
        auto p  = box.m_min;
        auto dp = box.m_max - p;

        // test for triangle-plane/box overlap
        glm::vec3 c = glm::vec3(
            n.x > 0.0f ? dp.x : 0.0f,
            n.y > 0.0f ? dp.z : 0.0f,
            n.z > 0.0f ? dp.z : 0.0f
        );

        auto d1 = glm::dot(n, c - tri.m_a);
        auto d2 = glm::dot(n, dp - c - tri.m_a);

        if ((glm::dot(n, p) + d1) * (glm::dot(n, p) + d2) > 0.0f)
            return false;

        // xy-plane projection-overlap
        auto xym = (n.z < 0.0f ? -1.0f : 1.0f);
        auto ne0xy = glm::vec4{-k_tri_edges[0].y, k_tri_edges[0].x, 0.0f, 0.0f} * xym;
        auto ne1xy = glm::vec4{-k_tri_edges[1].y, k_tri_edges[1].x, 0.0f, 0.0f} * xym;
        auto ne2xy = glm::vec4{-k_tri_edges[2].y, k_tri_edges[2].x, 0.0f, 0.0f} * xym;

        auto v0xy = glm::vec4{tri.m_a.x, tri.m_a.y, 0.0f, 0.0f};
        auto v1xy = glm::vec4{tri.m_b.x, tri.m_b.y, 0.0f, 0.0f};
        auto v2xy = glm::vec4{tri.m_c.x, tri.m_c.y, 0.0f, 0.0f};

        float de0xy = -glm::dot(ne0xy, v0xy) + std::max(0.0f, dp.x * ne0xy.x) + std::max(0.0f, dp.z * ne0xy.z);
        float de1xy = -glm::dot(ne1xy, v1xy) + std::max(0.0f, dp.x * ne1xy.x) + std::max(0.0f, dp.z * ne1xy.z);
        float de2xy = -glm::dot(ne2xy, v2xy) + std::max(0.0f, dp.x * ne2xy.x) + std::max(0.0f, dp.z * ne2xy.z);

        auto pxy = glm::vec4(p.x, p.y, 0.0f, 0.0f);

        if ((glm::dot(ne0xy, pxy) + de0xy) < 0.0f || (glm::dot(ne1xy, pxy) + de1xy) < 0.0f || (glm::dot(ne2xy, pxy) + de2xy) < 0.0f)
            return false;

        // yz-plane projection overlap
        auto yzm = (n.x < 0.0f ? -1.0f : 1.0f);
        auto ne0yz = glm::vec4{-k_tri_edges[0].z, k_tri_edges[0].y, 0.0f, 0.0f} * yzm;
        auto ne1yz = glm::vec4{-k_tri_edges[1].z, k_tri_edges[1].y, 0.0f, 0.0f} * yzm;
        auto ne2yz = glm::vec4{-k_tri_edges[2].z, k_tri_edges[2].y, 0.0f, 0.0f} * yzm;

        auto v0yz = glm::vec4{tri.m_a.y, tri.m_a.z, 0.0f, 0.0f};
        auto v1yz = glm::vec4{tri.m_b.y, tri.m_b.z, 0.0f, 0.0f};
        auto v2yz = glm::vec4{tri.m_c.y, tri.m_c.z, 0.0f, 0.0f};

        float de0yz = -glm::dot(ne0yz, v0yz) + std::max(0.0f, dp.z * ne0yz.x) + std::max(0.0f, dp.z * ne0yz.z);
        float de1yz = -glm::dot(ne1yz, v1yz) + std::max(0.0f, dp.z * ne1yz.x) + std::max(0.0f, dp.z * ne1yz.z);
        float de2yz = -glm::dot(ne2yz, v2yz) + std::max(0.0f, dp.z * ne2yz.x) + std::max(0.0f, dp.z * ne2yz.z);

        auto pyz = glm::vec4(p.y, p.z, 0.0f, 0.0f);

        if ((glm::dot(ne0yz, pyz) + de0yz) < 0.0f || (glm::dot(ne1yz, pyz) + de1yz) < 0.0f || (glm::dot(ne2yz, pyz) + de2yz) < 0.0f)
            return false;

        // zx-plane projection overlap
        auto zxm = (n.y < 0.0f ? -1.0f : 1.0f);
        auto ne0zx = glm::vec4{-k_tri_edges[0].x, k_tri_edges[0].z, 0.0f, 0.0f} * zxm;
        auto ne1zx = glm::vec4{-k_tri_edges[1].x, k_tri_edges[1].z, 0.0f, 0.0f} * zxm;
        auto ne2zx = glm::vec4{-k_tri_edges[2].x, k_tri_edges[2].z, 0.0f, 0.0f} * zxm;

        auto v0zx = glm::vec4{tri.m_a.z, tri.m_a.x, 0.0f, 0.0f};
        auto v1zx = glm::vec4{tri.m_b.z, tri.m_b.x, 0.0f, 0.0f};
        auto v2zx = glm::vec4{tri.m_c.z, tri.m_c.x, 0.0f, 0.0f};

        float de0zx = -glm::dot(ne0zx, v0zx) + std::max(0.0f, dp.z * ne0zx.x) + std::max(0.0f, dp.z * ne0zx.z);
        float de1zx = -glm::dot(ne1zx, v1zx) + std::max(0.0f, dp.z * ne1zx.x) + std::max(0.0f, dp.z * ne1zx.z);
        float de2zx = -glm::dot(ne2zx, v2zx) + std::max(0.0f, dp.z * ne2zx.x) + std::max(0.0f, dp.z * ne2zx.z);

        auto pzx = glm::vec4(p.z, p.x, 0.0f, 0.0f);

        if ((glm::dot(ne0zx, pzx) + de0zx) < 0.0f || (glm::dot(ne1zx, pzx) + de1zx) < 0.0f || (glm::dot(ne2zx, pzx) + de2zx) < 0.0f)
            return false;

        return true;
    }
}
