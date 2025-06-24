#pragma once

#include <cassert>
#include <filesystem>
#include <string>

#include "glad/gl.h"

namespace bf
{
GLuint create_shader(GLenum type, const std::string& src);

void link_program(GLuint program);

GLint get_attrib_location(GLuint program, const char* name, bool require = true);

GLint get_uniform_location(GLuint program, const char* name, bool require = true);

inline GLint get_uniform_location(GLuint program, const std::string& name, bool require = true)
{
    return get_uniform_location(program, name.c_str(), require);
}

void enable_gl_debug_output();

GLuint create_gl_texture(uint32_t width, uint32_t height);

GLuint load_gl_texture(const std::filesystem::path& filepath);

} // namespace bf
