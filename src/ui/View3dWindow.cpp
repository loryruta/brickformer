#include "View3dWindow.h"

#include <imgui.h>
#include "imgui_internal.h"

#include "UIStyle.h"

using namespace lego_builder::ui;

View3dWindow::View3dWindow(Window& window, RenderFuncT render_func, ViewUpdateFuncT view_update_func)
    : m_window(window), m_render_func(std::move(render_func)), m_view_update_func(std::move(view_update_func))
{
}

void View3dWindow::ui()
{
    if (ui_window("View###PreviewWindow", nullptr, ImGuiDockNodeFlags_HiddenTabBar)) {
        ImVec2 image_size = ImGui::GetContentRegionAvail();
        if (!m_framebuffer || m_framebuffer->width() != image_size.x || m_framebuffer->height() != image_size.y) {
            m_framebuffer = std::make_unique<CustomFramebuffer>(image_size.x, image_size.y);
        }
        m_framebuffer->render([&]() {
            if (m_render_func) m_render_func();
        });
        ImGui::Image((ImTextureID) m_framebuffer->get_texture(), image_size, ImVec2(0, 1), ImVec2(1, 0));

        if (ImGui::IsItemHovered() && ImGui::IsMouseDown(ImGuiMouseButton_Left) && !m_cursor_captured) {
            m_cursor_captured = true;
            ImGui::GetIO().ConfigWindowsMoveFromTitleBarOnly = true;
            glfwSetInputMode(m_window.handle(), GLFW_CURSOR, GLFW_CURSOR_DISABLED);
        }

        if (!ImGui::IsMouseDown(ImGuiMouseButton_Left) && m_cursor_captured) {
            m_cursor_captured = false;
            m_last_cursor_pos.reset();
            ImGui::GetIO().ConfigWindowsMoveFromTitleBarOnly = false;
            glfwSetInputMode(m_window.handle(), GLFW_CURSOR, GLFW_CURSOR_NORMAL);
        }

        if (m_cursor_captured) {
            glm::vec3 dposition{};
            float dyaw = 0.f;
            float dpitch = 0.f;

            if (m_window.is_key_pressed(GLFW_KEY_A)) dposition.x = -1.f;
            if (m_window.is_key_pressed(GLFW_KEY_D)) dposition.x = 1.f;
            if (m_window.is_key_pressed(GLFW_KEY_LEFT_SHIFT)) dposition.y = -1.f;
            if (m_window.is_key_pressed(GLFW_KEY_SPACE)) dposition.y = 1.f;
            if (m_window.is_key_pressed(GLFW_KEY_W)) dposition.z = 1.f;
            if (m_window.is_key_pressed(GLFW_KEY_S)) dposition.z = -1.f;

            glm::dvec2 cursor;
            glfwGetCursorPos(m_window.handle(), &cursor.x, &cursor.y);

            if (m_last_cursor_pos) {
                dyaw = cursor.x - m_last_cursor_pos->x;
                dpitch = m_last_cursor_pos->y - cursor.y;
            }

            if (m_view_update_func) m_view_update_func(dposition, dyaw, dpitch);

            m_last_cursor_pos = cursor;
        }
    }
    ImGui::End();
}
