#pragma once

#include <memory>
#include <optional>

#include <glm/glm.hpp>

#include "video/CustomFramebuffer.hpp"
#include "video/Window.hpp"

namespace lego_builder::ui
{
/// A window used to display and explore a 3d scene.
class View3dWindow
{
public:
    using ViewUpdateFuncT = std::function<void(const glm::vec3& dposition, float dyaw, float dpitch)>;
    using RenderFuncT = std::function<void()>;

private:
    Window& m_window;
    std::unique_ptr<CustomFramebuffer> m_framebuffer;
    ViewUpdateFuncT m_view_update_func;
    RenderFuncT m_render_func;

    bool m_cursor_captured = false;
    std::optional<glm::dvec2> m_last_cursor_pos;

public:
    explicit View3dWindow(Window& window, RenderFuncT render_func, ViewUpdateFuncT view_update_func);
    ~View3dWindow() = default;

    void ui();
};
} // namespace lego_builder::ui
