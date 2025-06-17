#include "BrickPlaneRenderer.h"

#include <vector>

#include <glm/gtc/type_ptr.hpp>

#include "ScreenQuad.hpp"
#include "gl_helpers.hpp"
#include "log.hpp"

#define ARP_LOG_CONTEXT "BrickPlaneRenderer"

using namespace lego_builder;

namespace
{
const char* k_fshader_src = R"(#version 460 core

    in vec2 v_uv;

    layout(location = 0) uniform mat4 u_inv_V;
    layout(location = 1) uniform mat4 u_projection;
    layout(location = 2) uniform vec2 u_screen_size;
    layout(location = 3) uniform float u_border_size;

    uniform sampler2D u_texture;

    out vec4 f_color;

    void main()
    {
        vec2 ndc_xy = (gl_FragCoord.xy / u_screen_size) * 2 - 1;
        float p00 = u_projection[0][0];
        float p11 = u_projection[1][1];
        float p22 = u_projection[2][2];
        float p32 = u_projection[3][2];
        vec3 view_pix;
        view_pix.z = 1;
        view_pix.x = ndc_xy.x / p00 * view_pix.z;
        view_pix.y = ndc_xy.y / p11 * view_pix.z;
        vec3 ro = u_inv_V[3].xyz;
        vec3 rd = (u_inv_V * vec4(view_pix, 0)).xyz;
        rd = normalize(rd);
        float t = -ro.y / rd.y; // Ray XZ-plane intersection (zero origin)
        if (t < 0) { discard; }
        vec3 p = ro + rd * t; // World-space intersection point
        float t_01 = p22 + p32 / t;
        gl_FragDepth = t_01 * 0.5 + 0.5; // [-1, 1]
        vec2 uv = p.xz;
        float border = texture(u_texture, uv).r;
        float c = 1.0 - border;
        f_color = vec4(c, c, c, border);
    }
)";
} // namespace

BrickPlaneRenderer::BrickPlaneRenderer()
{
    m_program = glCreateProgram();
    GLuint vshader = ScreenQuad::get().get_vertex_shader();
    GLuint fshader = create_shader(GL_FRAGMENT_SHADER, k_fshader_src);
    glAttachShader(m_program, vshader);
    glAttachShader(m_program, fshader);
    link_program(m_program);
    glDeleteShader(fshader);

    create_brick_texture();
}

BrickPlaneRenderer::~BrickPlaneRenderer() { glDeleteProgram(m_program); }

void BrickPlaneRenderer::render(float y, const Camera& camera, float border_r)
{
    GLint viewport[4];
    glGetIntegerv(GL_VIEWPORT, viewport);
    int width = viewport[2];
    int height = viewport[3];

    /* Program */
    glUseProgram(m_program);

    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LESS);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glm::mat4 inv_V = glm::inverse(camera.view());
    glUniformMatrix4fv(0 /* u_inv_V */, 1, GL_FALSE, glm::value_ptr(inv_V));
    glUniformMatrix4fv(1 /* u_projection */, 1, GL_FALSE, glm::value_ptr(camera.projection()));
    glUniform2f(2 /* u_screen_size */, width, height);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, m_brick_texture);

    ScreenQuad::get().draw();
}

void BrickPlaneRenderer::create_brick_texture()
{
    constexpr int k_resolution = 64;
    constexpr int k_border_r = 3;
    constexpr float k_stud_r = 0.3f;

    // Procedurally generate the brick texture
    std::vector<uint8_t> image_data(k_resolution * k_resolution, 0);
    for (int y = 0; y < k_resolution; ++y) {
        for (int x = 0; x < k_resolution; ++x) {
            bool is_border = x < k_border_r || x >= k_resolution - k_border_r;
            is_border |= y < k_border_r || y >= k_resolution - k_border_r;
            glm::vec2 d = glm::vec2(x, y) - glm::vec2(k_resolution, k_resolution) * 0.5f;
            float r = glm::length(d);
            is_border |=
                r >= (k_stud_r * k_resolution - k_border_r) && r <= (k_stud_r * k_resolution + k_border_r);
            if (is_border) {
                image_data[y * k_resolution + x] = 255;
            }
        }
    }

    glGenTextures(1, &m_brick_texture);
    glBindTexture(GL_TEXTURE_2D, m_brick_texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, k_resolution, k_resolution, 0, GL_RED, GL_UNSIGNED_BYTE, image_data.data());
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glGenerateMipmap(GL_TEXTURE_2D);

    glBindTexture(GL_TEXTURE_2D, 0);
}
