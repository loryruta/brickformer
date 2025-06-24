#pragma once

#include <string>

#include <imgui.h>

#define MAKE_IMVEC4(hex_)                                                                                              \
    ImVec4(float((hex_ >> 16) & 0xff) / 255.0f, float((hex_ >> 8) & 0xff) / 255.0f, float(hex_ & 0xff) / 255.0f, 1.0f)

// Created in:
// https://coolors.co/
// clang-format off
#define DARK_COLOR        MAKE_IMVEC4(0x1a1919)
#define DARK_COLOR_LIGHT  MAKE_IMVEC4(0x343232)
#define DARK_COLOR_LIGHT2 MAKE_IMVEC4(0x535050)
#define MAIN_COLOR_LIGHT  MAKE_IMVEC4(0xFFDE5C)
#define MAIN_COLOR        MAKE_IMVEC4(0xffd321)
#define MAIN_COLOR_DARK  MAKE_IMVEC4(0xCCA300)
// clang-format on

namespace bf
{
inline ImFont* g_font;
inline ImFont* g_title_font;

inline bool ui_window(const char* name, bool* p_open = nullptr, ImGuiWindowFlags flags = 0)
{
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0, 0, 0, 1));
    bool opened = ImGui::Begin(name, p_open, flags);
    ImGui::PopStyleColor();
    return opened;
}

inline bool ui_popup_modal(const char* name, bool* p_open = nullptr, ImGuiWindowFlags flags = 0)
{
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0, 0, 0, 1));
    bool opened = ImGui::BeginPopupModal(name, p_open, flags);
    ImGui::PopStyleColor();
    return opened;
}

inline bool ui_button(const char* name, ImVec2 size = ImVec2(0, 0))
{
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0, 0, 0, 1));
    bool pressed = ImGui::Button(name, size);
    ImGui::PopStyleColor();
    return pressed;
}

inline bool ui_primary_button(const char* label, ImVec2 size = ImVec2(0, 0))
{
    ImGui::PushStyleColor(ImGuiCol_Button, 0xfffd6e0d);
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, 0xffd75e0b);
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, 0xffd75e0b);
    ImGui::PushStyleColor(ImGuiCol_Text, 0xffffffff);
    bool ret = ImGui::Button(label, size);
    ImGui::PopStyleColor(4);
    return ret;
}

inline void ui_text_danger(const char* fmt, ...)
{
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.0f, 0.0f, 1));
    va_list args;
    va_start(args, fmt);
    ImGui::TextV(fmt, args);
    va_end(args);
    ImGui::PopStyleColor();
}

inline void ui_text_wrapped_danger(const char* fmt, ...)
{
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.0f, 0.0f, 1));
    va_list args;
    va_start(args, fmt);
    ImGui::TextWrappedV(fmt, args);
    va_end(args);
    ImGui::PopStyleColor();
}

inline void ui_text_wrapped_muted(const char* fmt, ...)
{
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.6f, 0.6f, 0.6f, 1));
    va_list args;
    va_start(args, fmt);
    ImGui::TextWrappedV(fmt, args);
    va_end(args);
    ImGui::PopStyleColor();
}

inline bool ui_slider_int_with_text(
    const char* label, int* v, int v_min, int v_max, const char* format = "%d", ImGuiSliderFlags flags = 0)
{
    std::string real_label = "##" + std::string(label);
    bool ret = ImGui::SliderInt(real_label.c_str(), v, v_min, v_max, format, flags);
    ImGui::SameLine();
    ImGui::Text("%s", label);
    return ret;
}

inline bool
ui_slider_int(const char* label, int* v, int v_min, int v_max, const char* format = "%d", ImGuiSliderFlags flags = 0)
{
    bool ret = ImGui::SliderInt(label, v, v_min, v_max, format, flags);
    return ret;
}

inline bool ui_slider_float(
    const char* label, float* v, float v_min, float v_max, const char* format = "%.3f", ImGuiSliderFlags flags = 0)
{
    return ImGui::SliderFloat(label, v, v_min, v_max, format, flags);
}

void ui_apply_style();
} // namespace bf