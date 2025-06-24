#pragma once

#include "Camera.hpp"
#include "gl_helpers.hpp"

#include <glm/glm.hpp>

namespace bf
{
class GridRenderer
{
private:
    GLuint m_vao;
    GLuint m_vbo;
    GLuint m_program;

public:
    explicit GridRenderer();
    ~GridRenderer();

    struct RenderParams {
        Camera camera;
        glm::vec3 min;
        glm::vec3 max;
        glm::ivec3 divisions;
        float half_border_size = 0.1f;
        glm::vec3 color = glm::vec3(0, 1, 0);
    };

    void render(const RenderParams& params) const;

private:
    void create_gl_objects();
};
}
