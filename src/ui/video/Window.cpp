#include "Window.hpp"

#include <cassert>

using namespace lego_builder;

Window::Window(int width, int height, const char* title)
{
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 6);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    m_glfw_window = glfwCreateWindow(width, height, title, nullptr, nullptr);
    assert(m_glfw_window);  // TODO no assert

    glfwMakeContextCurrent(m_glfw_window);

    glfwSetWindowUserPointer(m_glfw_window, this);

    glfwSetKeyCallback(m_glfw_window, [](GLFWwindow* window, int key, int scancode, int action, int mods)
    {
        Window* self = (Window*) glfwGetWindowUserPointer(window);
        if (self->m_key_callback) self->m_key_callback(key, scancode, action, mods);
    });
}

Window::~Window()
{
    glfwDestroyWindow(m_glfw_window);
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

    if (is_key_pressed(GLFW_KEY_ESCAPE))
        glfwSetWindowShouldClose(m_glfw_window, GLFW_TRUE);
}

void Window::end_frame()
{
    glfwSwapBuffers(m_glfw_window);
}

void Window::set_key_callback(const KeyCallbackT& key_callback)
{
    m_key_callback = key_callback;
}

bool Window::should_close() const
{
    return glfwWindowShouldClose(m_glfw_window);
}

void Window::set_should_close(bool should_close)
{
    glfwSetWindowShouldClose(m_glfw_window, should_close);
}

bool Window::is_key_pressed(int key) const
{
    return glfwGetKey(m_glfw_window, key) == GLFW_PRESS;
}
