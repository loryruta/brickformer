#pragma once

#include <functional>

#include <glad/gl.h>
#include <GLFW/glfw3.h>
#include <glm/glm.hpp>

namespace lego_builder
{
    class Window
    {
        using KeyCallbackT = std::function<void(int key, int scancode, int action, int mods)>;

    private:
        GLFWwindow* m_glfw_window;

        KeyCallbackT m_key_callback;

    public:
        explicit Window(int width, int height, const char* title);
        ~Window();

        [[nodiscard]] GLFWwindow* handle() const { return m_glfw_window; };

        [[nodiscard]] glm::ivec2 get_framebuffer_size() const;

        void begin_frame();
        void end_frame();

        void set_key_callback(const KeyCallbackT& key_callback);

        [[nodiscard]] bool should_close() const;
        void set_should_close(bool should_close);

        [[nodiscard]] bool is_key_pressed(int key) const;
    };

}