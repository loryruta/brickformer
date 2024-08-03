#pragma once

#include <glad/gl.h>

namespace lego_builder
{
class BoxFilter
{
private:
    GLuint m_program;

public:
    explicit BoxFilter();
    ~BoxFilter();

    void run(GLuint input_texture, GLuint output_texture, int kernel_size = 2);
};
}