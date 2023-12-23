#pragma once

#include <glad/gl.h>
#include <GLFW/glfw3.h>
#include <glm/glm.hpp>

namespace lego_builder
{
    class Window
    {
    private:
        GLFWwindow* m_glfw_window;

    public:
        explicit Window(int width, int height, const char* title);
        ~Window();

        [[nodiscard]] glm::ivec2 get_framebuffer_size() const;

        void begin_frame();
        void end_frame();

        [[nodiscard]] bool should_close() const;
    };

}