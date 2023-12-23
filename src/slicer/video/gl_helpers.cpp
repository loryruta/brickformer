#include "gl_helpers.hpp"

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

void lego_builder::enable_gl_debug_output()
{
    glEnable(GL_DEBUG_OUTPUT);
    glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);  // To ensure errors are thrown in the scope of the function
    glDebugMessageCallback(debug_message_callback, nullptr);
}
