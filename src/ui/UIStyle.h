#pragma once

#include <string>

#include <imgui.h>

namespace lego_builder
{
inline bool ui_window(const char* name, bool* p_open = nullptr, ImGuiWindowFlags flags = 0)
{
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0, 0, 0, 1));
    bool opened = ImGui::Begin(name, p_open, flags);
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
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0, 0, 0, 1));
    std::string real_label = "##" + std::string(label);
    bool ret = ImGui::SliderInt(real_label.c_str(), v, v_min, v_max, format, flags);
    ImGui::PopStyleColor();
    ImGui::SameLine();
    ImGui::Text("%s", label);
    return ret;
}

inline bool
ui_slider_int(const char* label, int* v, int v_min, int v_max, const char* format = "%d", ImGuiSliderFlags flags = 0)
{
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0, 0, 0, 1));
    bool ret = ImGui::SliderInt(label, v, v_min, v_max, format, flags);
    ImGui::PopStyleColor();
    return ret;
}

inline bool ui_slider_float(
    const char* label, float* v, float v_min, float v_max, const char* format = "%.3f", ImGuiSliderFlags flags = 0)
{
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0, 0, 0, 1));
    bool ret = ImGui::SliderFloat(label, v, v_min, v_max, format, flags);
    ImGui::PopStyleColor();
    return ret;
}

void ui_apply_style();
} // namespace lego_builder