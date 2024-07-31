#include "View3dWindow.hpp"

#include <imgui.h>

using namespace lego_builder::ui;

View3dWindow::View3dWindow(Window& window, const RenderFuncT& render_func, const ViewUpdateFuncT& view_update_func) :
    m_window(window),
    m_framebuffer(std::make_unique<CustomFramebuffer>(k_framebuffer_width, k_framebuffer_height)),
    m_render_func(render_func),
    m_view_update_func(view_update_func)
{
}

void View3dWindow::show()
{
    if (ImGui::Begin("View###PreviewWindow"))
    {
        float framebuffer_ar = m_framebuffer->get_aspect_ratio();

        ImVec2 image_size{};
        image_size.x = std::min(ImGui::GetContentRegionAvail().x, framebuffer_ar * ImGui::GetContentRegionAvail().y);
        image_size.y = ImGui::GetContentRegionAvail().y;
        m_framebuffer->render([&]()
        {
            if (m_render_func) m_render_func();
        });

        float img_content_ar = float(image_size.x) / float(image_size.y);
        float e = std::min((img_content_ar / framebuffer_ar) * .5f, .5f);
        ImGui::Image(reinterpret_cast<void*>(m_framebuffer->get_texture()), image_size, ImVec2(.5f - e, 1.f), ImVec2(.5f + e, 0.f));

        if (ImGui::IsItemHovered() && ImGui::IsMouseDown(ImGuiMouseButton_Left) && !m_cursor_captured)
        {
            m_cursor_captured = true;
            ImGui::GetIO().ConfigWindowsMoveFromTitleBarOnly = true;
            glfwSetInputMode(m_window.handle(), GLFW_CURSOR, GLFW_CURSOR_DISABLED);
        }

        if (!ImGui::IsMouseDown(ImGuiMouseButton_Left) && m_cursor_captured)
        {
            m_cursor_captured = false;
            m_last_cursor_pos.reset();
            ImGui::GetIO().ConfigWindowsMoveFromTitleBarOnly = false;
            glfwSetInputMode(m_window.handle(), GLFW_CURSOR, GLFW_CURSOR_NORMAL);
        }

        if (m_cursor_captured)
        {
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

            if (m_last_cursor_pos)
            {
                dyaw = cursor.x - m_last_cursor_pos->x;
                dpitch = m_last_cursor_pos->y - cursor.y;
            }

            if (m_view_update_func) m_view_update_func(dposition, dyaw, dpitch);

            m_last_cursor_pos = cursor;
        }
    }
    ImGui::End();
}
