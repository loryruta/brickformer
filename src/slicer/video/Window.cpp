#include "Window.hpp"

#include <cassert>

using namespace lego_builder;

Window::Window(int width, int height, const char* title)
{
    assert(glfwInit());  // TODO no assert

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 6);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    m_glfw_window = glfwCreateWindow(width, height, title, nullptr, nullptr);
    assert(m_glfw_window);  // TODO no assert

    glfwMakeContextCurrent(m_glfw_window);
}

Window::~Window()
{
    glfwDestroyWindow(m_glfw_window);

    glfwTerminate();
}

glm::ivec2 Window::get_framebuffer_size() const
{
    glm::ivec2 framebuffer_size;
    glfwGetFramebufferSize(m_glfw_window, &framebuffer_size.x, &framebuffer_size.y);
    return framebuffer_size;
}

void Window::begin_frame()
{
    glfwPollEvents();
}

void Window::end_frame()
{
    glfwSwapBuffers(m_glfw_window);
}

bool Window::should_close() const
{
    return glfwWindowShouldClose(m_glfw_window);
}
