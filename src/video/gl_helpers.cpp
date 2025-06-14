#include "gl_helpers.hpp"

#include <stb_image.h>

#include "util/misc.hpp"

using namespace lego_builder;

namespace
{
    void GLAPIENTRY
    debug_message_callback( GLenum source,
                     GLenum type,
                     GLuint id,
                     GLenum severity,
                     GLsizei length,
                     const GLchar* message,
                     const void* userParam )
    {
        if (type == GL_DEBUG_TYPE_OTHER) return;

        bool is_error = type == GL_DEBUG_TYPE_ERROR;
        if (is_error) fprintf(stderr, "ERROR: ");

        fprintf(is_error ? stderr : stdout, "GL CALLBACK: type = 0x%x, severity = 0x%x, message = %s\n",
                type, severity, message);

        if (is_error)
        {
            exit(type);
        }
    }
}  // namespace

GLuint lego_builder::create_shader(GLenum type, const std::string& src)
{
    GLuint shader = glCreateShader(type);
    const char* src_ptr = src.c_str();
    glShaderSource(shader, 1, &src_ptr, nullptr);
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

void lego_builder::link_program(GLuint program)
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

GLint lego_builder::get_attrib_location(GLuint program, const char* name, bool require)
{
    GLint loc = glGetAttribLocation(program, name);

    if (require && loc < 0)
    {
        printf("[ERROR] [gl_helpers] Got invalid attrib location for: %s\n", name);
        CHECK_STATE(!(require && loc < 0));
    }
    return loc;
}

GLint lego_builder::get_uniform_location(GLuint program, const char* name, bool require)
{
    GLint loc = glGetUniformLocation(program, name);
    if (require && loc < 0)
    {
        printf("[ERROR] [gl_helpers] Got invalid uniform location for: %s\n", name);
        CHECK_STATE(!(require && loc < 0));
    }
    return loc;
}

void lego_builder::enable_gl_debug_output()
{
    glEnable(GL_DEBUG_OUTPUT);
    glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);  // To ensure errors are thrown in the scope of the function
    glDebugMessageCallback(debug_message_callback, nullptr);
}

GLuint lego_builder::create_gl_texture(uint32_t width, uint32_t height)
{
    GLuint gl_texture;
    glGenTextures(1, &gl_texture);
    glBindTexture(GL_TEXTURE_2D, gl_texture);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, GL_NONE, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);

    glBindTexture(GL_TEXTURE_2D, 0);

    return gl_texture;
}

GLuint lego_builder::load_gl_texture(const std::filesystem::path& filepath)
{
    int width, height, channels;
    const stbi_uc* image_data = stbi_load(filepath.c_str(), &width, &height, &channels, STBI_rgb_alpha);
    CHECK_STATE(image_data, "Failed to load texture: %s", filepath.string());

    GLuint texture;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, GL_NONE, GL_RGBA, GL_UNSIGNED_BYTE, image_data);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

    glBindTexture(GL_TEXTURE_2D, 0);

    return texture;
}
