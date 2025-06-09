#include <cstdio>
#include <optional>
#include <algorithm>

#include "video/ModelRenderer.hpp"
#include "video/Window.hpp"

using namespace lego_builder;

struct Box { glm::vec3 m_min, m_max; };

struct Triangle
{
    glm::vec3 m_a, m_b, m_c;

    [[nodiscard]] glm::vec3 normal() const { return glm::normalize(glm::cross(m_b - m_a, m_c - m_a)); };

    void translate(const glm::vec3& d)
    {
        m_a += d;
        m_b += d;
        m_c += d;
    }
};

/*
/// Given the plane's origin and normal, clips input polygon with respect to it.
void clip_polygon_with_aa_plane(
    const glm::vec3& po,
    const glm::vec3& pn,
    const std::vector<glm::vec3>& in_polygon,
    std::vector<glm::vec3>& out_polygon
    )
{
    for (int i = 0; i < in_polygon.size(); i++)
    {
        const glm::vec3& cur_p = in_polygon[i];
        const glm::vec3& prv_p = in_polygon[(i - 1) % in_polygon.size()];

        // a(x - x0) + b(y - y0) + c(z - z0)
        float cur_p_eq = glm::dot(pn, cur_p - po);
        float prv_p_eq = glm::dot(pn, prv_p - po);

        glm::vec3 int_p = plane_line_intersection(prv_p, cur_p - prv_p, po, pn);

        // If previous point is on one side, the other is on the other side (or vice versa), find the intersection
        if (cur_p_eq < 0)
        {
            if (prv_p_eq > 0) out_polygon.push_back(int_p);
            out_polygon.push_back(cur_p);
        }
        else if (prv_p_eq < 0)
            out_polygon.push_back(int_p);
    }
}

/// Clip the triangle with respect to the given AABB. Outputs the polygon in the intersection.
/// Note: this function can also be used as an intersection test (i.e. output polygon is empty).
void clip_triangle_with_aabb(  // TODO not only triangles actually...
    const glm::vec3& bmin, const glm::vec3& bmax,
    const glm::vec3& ta, const glm::vec3& tb, const glm::vec3& tc,
    std::vector<glm::vec3>& out_polygon
    )
{
    std::vector<glm::vec3> in_polygon{ta, tb, tc};

    // bmin.x
    clip_polygon_with_aa_plane(bmin, {-1, 0, 0}, in_polygon, out_polygon);

    // bmin.y
    in_polygon = out_polygon;
    out_polygon.clear();
    clip_polygon_with_aa_plane(bmin, {0, -1, 0}, in_polygon, out_polygon);

    // bmin.z
    in_polygon = out_polygon;
    out_polygon.clear();
    clip_polygon_with_aa_plane(bmin, {0, 0, -1}, in_polygon, out_polygon);

    // bmax.x
    in_polygon = out_polygon;
    out_polygon.clear();
    clip_polygon_with_aa_plane(bmax, {1, 0, 0}, in_polygon, out_polygon);

    // bmax.y
    in_polygon = out_polygon;
    out_polygon.clear();
    clip_polygon_with_aa_plane(bmax, {0, 1, 0}, in_polygon, out_polygon);

    // bmax.z
    in_polygon = out_polygon;
    out_polygon.clear();
    clip_polygon_with_aa_plane(bmax, {0, 0, 1}, in_polygon, out_polygon);
}
*/

int pmod(int i, int n)  // TODO already defined in misc.cuh
{
    return (i % n + n) % n;
}

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

void add_if_not_duplicated(std::vector<glm::vec3>& face, const glm::vec3& to_add_v, float threshold)
{
    bool duplicated = false;
    for (const glm::vec3& v : face)
    {
        glm::vec3 diff = v - to_add_v;
        if (glm::dot(diff, diff) < glm::dot(threshold, threshold))
        {
            duplicated = true;
            break;
        }
    }
    if (!duplicated) face.push_back(to_add_v);
}

void clip_face_by_plane(
    const std::vector<glm::vec3>& face,
    const glm::vec3& po, const glm::vec3& pn,
    std::vector<glm::vec3>& out_face
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

void clip_face_by_aabb(
    const std::vector<glm::vec3>& face,
    const glm::vec3& bmin, const glm::vec3& bmax,
    std::vector<glm::vec3>& out_face
    )
{
    std::vector<glm::vec3> in_face = face;

    // bmin.x
    clip_face_by_plane(in_face, bmin, {-1, 0, 0}, out_face);

    // bmin.y
    in_face = out_face;
    out_face.clear();
    clip_face_by_plane(in_face, bmin, {0, -1, 0}, out_face);

    // bmin.z
    in_face = out_face;
    out_face.clear();
    clip_face_by_plane(in_face, bmin, {0, 0, -1}, out_face);

    // bmax.x
    in_face = out_face;
    out_face.clear();
    clip_face_by_plane(in_face, bmax, {1, 0, 0}, out_face);

    // bmax.y
    in_face = out_face;
    out_face.clear();
    clip_face_by_plane(in_face, bmax, {0, 1, 0}, out_face);

    // bmax.z
    in_face = out_face;
    out_face.clear();
    clip_face_by_plane(in_face, bmax, {0, 0, 1}, out_face);
}

float calc_convex_face_area(
    const glm::vec3& pd1,
    const glm::vec3& pd2,
    const std::vector<glm::vec3>& face
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

        float triangle_area = 0.5f * glm::abs(pv0.x * (pv1.y - pv2.y) + pv1.x * (pv2.y - pv0.y) + pv2.x * (pv0.y - pv1.y));
        area += triangle_area;
    }
    return area;
}

Model create_model_from_box(const Box& box, float a)
{
    const glm::vec3& m = box.m_min;
    const glm::vec3& M = box.m_max;

    Model model;
    Mesh& mesh = model.m_meshes.emplace_back();

    mesh.vertices = {
        // Bottom
        Vertex{ .position{m.x, m.y, m.z}, .normal{0, -1, 0}, .texcoord{}, .color{0,1,0,a}},
        Vertex{ .position{m.x, m.y, M.z}, .normal{0, -1, 0}, .texcoord{}, .color{0,1,0,a}},
        Vertex{ .position{M.x, m.y, M.z}, .normal{0, -1, 0}, .texcoord{}, .color{0,1,0,a}},
        Vertex{ .position{M.x, m.y, m.z}, .normal{0, -1, 0}, .texcoord{}, .color{0,1,0,a}},

        // Top
        Vertex{ .position{m.x, M.y, m.z}, .normal{0, 1, 0}, .texcoord{}, .color{0,1,0,a}},
        Vertex{ .position{m.x, M.y, M.z}, .normal{0, 1, 0}, .texcoord{}, .color{0,1,0,a}},
        Vertex{ .position{M.x, M.y, M.z}, .normal{0, 1, 0}, .texcoord{}, .color{0,1,0,a}},
        Vertex{ .position{M.x, M.y, m.z}, .normal{0, 1, 0}, .texcoord{}, .color{0,1,0,a}},

        // Left
        Vertex{ .position{m.x, m.y, m.z}, .normal{-1, 0, 0}, .texcoord{}, .color{1,0,0,a}},
        Vertex{ .position{m.x, m.y, M.z}, .normal{-1, 0, 0}, .texcoord{}, .color{1,0,0,a}},
        Vertex{ .position{m.x, M.y, M.z}, .normal{-1, 0, 0}, .texcoord{}, .color{1,0,0,a}},
        Vertex{ .position{m.x, M.y, m.z}, .normal{-1, 0, 0}, .texcoord{}, .color{1,0,0,a}},

        // Right
        Vertex{ .position{M.x, m.y, m.z}, .normal{1, 0, 0}, .texcoord{}, .color{1,0,0,a}},
        Vertex{ .position{M.x, m.y, M.z}, .normal{1, 0, 0}, .texcoord{}, .color{1,0,0,a}},
        Vertex{ .position{M.x, M.y, M.z}, .normal{1, 0, 0}, .texcoord{}, .color{1,0,0,a}},
        Vertex{ .position{M.x, M.y, m.z}, .normal{1, 0, 0}, .texcoord{}, .color{1,0,0,a}},

        // Front
        Vertex{ .position{m.x, m.y, m.z}, .normal{0, 0, -1}, .texcoord{0, 1}, .color{0,0,1,a}},
        Vertex{ .position{m.x, M.y, m.z}, .normal{0, 0, -1}, .texcoord{0 ,0}, .color{0,0,1,a}},
        Vertex{ .position{M.x, M.y, m.z}, .normal{0, 0, -1}, .texcoord{1, 0}, .color{0,0,1,a}},
        Vertex{ .position{M.x, m.y, m.z}, .normal{0, 0, -1}, .texcoord{1, 1}, .color{0,0,1,a}},

        // Back
        Vertex{ .position{m.x, m.y, M.z}, .normal{0, 0, 1}, .texcoord{}, .color{0,0,1,a}},
        Vertex{ .position{m.x, M.y, M.z}, .normal{0, 0, 1}, .texcoord{}, .color{0,0,1,a}},
        Vertex{ .position{M.x, M.y, M.z}, .normal{0, 0, 1}, .texcoord{}, .color{0,0,1,a}},
        Vertex{ .position{M.x, m.y, M.z}, .normal{0, 0, 1}, .texcoord{}, .color{0,0,1,a}},
    };

    mesh.indices = {
        0, 1, 2, 0, 2, 3,        // Bottom
        4, 5, 6, 4, 6, 7,        // Top
        8, 9, 10, 8, 10, 11,     // Left
        12, 13, 14, 12, 14, 15,  // Right
        16, 17, 18, 16, 18, 19,  // Front
        20, 21, 22, 20, 22, 23,  // Back
    };

    return model;
}

Model create_model_from_triangle(const Triangle& triangle, const glm::vec4& color)
{
    Model model{};
    Mesh& mesh = model.m_meshes.emplace_back();
    mesh.vertices = {
        Vertex{ .position{triangle.m_a}, .normal{}, .texcoord{}, .color{1,0,0,1} },
        Vertex{ .position{triangle.m_b}, .normal{}, .texcoord{}, .color{0,1,0,1} },
        Vertex{ .position{triangle.m_c}, .normal{}, .texcoord{}, .color{0,0,1,1} },
    };
    mesh.indices = {0, 1, 2};
    return model;
}

Model create_model_from_polygon(std::vector<glm::vec3> polygon, const glm::vec4& color)
{
    assert(polygon.size() >= 3);

    Model model;
    Mesh& mesh = model.m_meshes.emplace_back();

    for (const glm::vec3& v : polygon)
    {
        mesh.vertices.emplace_back(Vertex{.position{v}, .normal{}, .texcoord{}, .color{color}});
    }

    for (int i = 1; i < polygon.size() - 1; i++)
    {
        mesh.indices.emplace_back(0);
        mesh.indices.emplace_back(i);
        mesh.indices.emplace_back((i + 1) % polygon.size());
    }

    return model;
}

int main(int argc, char* argv[])
{
    // Init GLFW
    if (!glfwInit())
    {
        fprintf(stderr, "Couldn't initialize GLFW\n");
        exit(1);
    }

    Window window(500, 500, "Triangle-AABB clipping");

    // Init GL
    int version = gladLoadGL(glfwGetProcAddress);
    if (version <= 0)
    {
        fprintf(stderr, "Couldn't initialize GL\n");
        exit(1);
    }

    //
    ModelRenderer model_renderer;
    model_renderer.m_shading = false;

    Box box{};
    box.m_min = {0, 0, 0};
    box.m_max = {1, 1, 1};

    Triangle triangle{};
    triangle.m_a = {-0.903f + 1.473f, 0.6724f + 1.6523f, 0.2088f + 1.075f};
    triangle.m_b = {0.1417f + 1.473f, 0.1361f + 1.6523f, -1.156f + 1.075f};
    triangle.m_c = {0.7619f + 1.473f, -0.8084f + 1.6523f, 0.9467f + 1.075f};

    BakedModel baked_box = model_renderer.bake_model(create_model_from_box(box, 0.3f));

    std::optional<BakedModel> baked_triangle;
    std::optional<BakedModel> baked_polygon;

    Camera camera{};
    camera.m_position = {4, 5, 4};
    camera.look_at(glm::vec3{0.5f});

    //triangle.translate(triangle.normal() * 1.2f);

    float triangle_speed = 0.003f;

    window.set_key_callback([&](int key, int scancode, int action, int mods)
    {
        if (key == GLFW_KEY_SPACE && action == GLFW_PRESS) triangle_speed = glm::abs(triangle_speed) > 0.0f ? 0.0f : 0.003f;
        if (key == GLFW_KEY_ENTER && action == GLFW_PRESS) triangle_speed = -triangle_speed;
    });

    int step = 0;

    glm::vec3 td1 = glm::normalize(triangle.m_b - triangle.m_a);
    glm::vec3 td2 = glm::normalize(triangle.m_c - triangle.m_a);

    while (!window.should_close())
    {
        // Perform clipping
        std::vector<glm::vec3> clipped_polygon{};
        clip_face_by_aabb({triangle.m_a, triangle.m_b, triangle.m_c}, box.m_min, box.m_max, clipped_polygon);

        if (clipped_polygon.size() >= 3)
        {
            float area = calc_convex_face_area(td1, td2, clipped_polygon);
            printf("%d : Clipped polygon: %zu vertices; Area: %f\n", step, clipped_polygon.size(), area);
        }

        // Baking
        baked_triangle.emplace(model_renderer.bake_model(create_model_from_triangle(triangle, {1.0f, 0, 0, 0.3f})));

        if (clipped_polygon.size() < 3) baked_polygon.reset();
        else
        {
            baked_polygon.emplace(model_renderer.bake_model(create_model_from_polygon(clipped_polygon, {1,1,0,1})));
        }

        // Render
        window.begin_frame();

        glClearColor(0.8f, 0.8f, 1.0f, 0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        if (baked_polygon) model_renderer.render(baked_polygon.value(), camera, glm::mat4{1.0f});
        model_renderer.render(baked_triangle.value(), camera, glm::mat4{1.0f});
        model_renderer.render(baked_box, camera, glm::mat4{1.0f});

        window.end_frame();

        // Update
        camera.m_position += camera.right() * 0.07f;
        camera.look_at(glm::vec3{0.5f});

        triangle.translate(triangle.normal() * triangle_speed);

        //
        ++step;
    }

    return 0;
}
