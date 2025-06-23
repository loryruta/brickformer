#pragma once

#include <atomic>

#include <glad/gl.h>

namespace lego_builder
{
// Forward decl
class MainScreen;

/// Window opened while the conversion process is running.
class ConversionWindow
{
private:
    MainScreen& m_parent;

    GLuint m_pause_icon = 0;
    GLuint m_play_icon = 0;
    GLuint m_stop_icon = 0;
    GLuint m_speed_play_icon = 0;

public:
    explicit ConversionWindow(MainScreen& parent);
    ~ConversionWindow();

    void ui();

private:
    void resume_conversion();
};
} // namespace lego_builder
