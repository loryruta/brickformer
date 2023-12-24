#pragma once

#include <cassert>
#include <string>

#include <glad/gl.h>

namespace lego_builder
{
    inline GLuint create_shader(GLenum type, const char* src)
    {
        GLuint shader = glCreateShader(type);
        glShaderSource(shader, 1, &src, nullptr);
        glCompileShader(shader);

        GLint compile_status = 0;
        glGetShaderiv(shader, GL_COMPILE_STATUS, &compile_status);
        if (!compile_status)
        {
            GLint max_log_length;
            glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &max_log_length);

            std::string log_str;
            log_str.resize(max_log_length);
            glGetShaderInfoLog(shader, max_log_length, &max_log_length, log_str.data());

            glDeleteShader(shader);

            printf("ERROR: Shader failed to compile: %s\n", log_str.c_str());
            exit(1);
        }

        return shader;
    }

    inline void link_program(GLuint program)
    {
        glLinkProgram(program);

        GLint link_status = 0;
        glGetProgramiv(program, GL_LINK_STATUS, &link_status);
        if (!link_status)
        {
            GLint max_log_length;
            glGetProgramiv(program, GL_INFO_LOG_LENGTH, &max_log_length);

            std::string log_str;
            log_str.resize(max_log_length);
            glGetProgramInfoLog(program, max_log_length, &max_log_length, &log_str[0]);

            glDeleteProgram(program);

            printf("ERROR: Shader failed to compile: %s\n", log_str.c_str());
            exit(1);
        }
    }

    inline GLint get_attrib_location(GLuint program, const char* name, bool require = true)
    {
        GLint loc = glGetAttribLocation(program, name);
        assert(!require || loc >= 0);  // TODO no assert
        return loc;
    }

    inline GLint get_uniform_location(GLuint program, const char* name, bool require = true)
    {
        GLint loc = glGetUniformLocation(program, name);
        assert(!require || loc >= 0); // TODO no assert
        return loc;
    }

    void enable_gl_debug_output();
}
