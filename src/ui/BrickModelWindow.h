#pragma once

#include <glad/gl.h>

namespace lego_builder
{
// Forward decl
class MainScreen;

class BrickModelWindow
{
private:
    MainScreen& m_parent;

    GLuint m_arrow_left_icon;
    GLuint m_arrow_right_icon;

public:
    /// The last subslice displayed (bottom-up).
    int current_subslice = 0;
    /// If the conversion is running, the current subslice will automatically update to catch the conversion.
    bool current_subslice_catch_conversion = true;

    explicit BrickModelWindow(MainScreen& parent);
    ~BrickModelWindow();

    void ui();

private:
    void export_bfc();
    void export_lxf();
};
} // namespace lego_builder
