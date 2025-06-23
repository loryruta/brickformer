#include "UIStyle.h"

using namespace lego_builder;

void lego_builder::ui_apply_style()
{
    ImGuiIO& io = ImGui::GetIO();
    io.Fonts->AddFontFromFileTTF("fonts/RobotoMono-Regular.ttf", 17.0f);

    ImGuiStyle& style = ImGui::GetStyle();

    auto to_ImVec4 = [](uint32_t color, float a = 1.0f) {
        float r = float((color >> 16) & 0xff) / 255.0f;
        float g = float((color >> 8) & 0xff) / 255.0f;
        float b = float(color & 0xff) / 255.0f;
        return ImVec4(r, g, b, a);
    };

    style.Colors[ImGuiCol_TextDisabled] = ImVec4(0.60f, 0.60f, 0.60f, 1.00f);
    style.Colors[ImGuiCol_WindowBg] = to_ImVec4(0x1a1919);
    style.Colors[ImGuiCol_PopupBg] = to_ImVec4(0x1a1919);
    style.Colors[ImGuiCol_Border] = ImVec4(0.70f, 0.70f, 0.70f, 0.65f);
    style.Colors[ImGuiCol_BorderShadow] = ImVec4(0.00f, 0.00f, 0.00f, 0.00f);
    style.Colors[ImGuiCol_FrameBg] = to_ImVec4(0xffd321);
    style.Colors[ImGuiCol_FrameBgHovered] = to_ImVec4(0xffe166);
    style.Colors[ImGuiCol_FrameBgActive] = to_ImVec4(0xffd321);
    style.Colors[ImGuiCol_TitleBg] = to_ImVec4(0xffd321);
    style.Colors[ImGuiCol_TitleBgCollapsed] = to_ImVec4(0xffd321);
    style.Colors[ImGuiCol_TitleBgActive] = to_ImVec4(0xffd321);
    style.Colors[ImGuiCol_Tab] = to_ImVec4(0xffd321);
    style.Colors[ImGuiCol_TabHovered] = to_ImVec4(0xffe166);
    style.Colors[ImGuiCol_TabSelected] = to_ImVec4(0xffe166);
    style.Colors[ImGuiCol_TabUnfocused] = to_ImVec4(0xffd321);
    style.Colors[ImGuiCol_TabDimmed] = to_ImVec4(0xffd321);
    style.Colors[ImGuiCol_TabDimmedSelected] = to_ImVec4(0xffd321);
    style.Colors[ImGuiCol_MenuBarBg] = to_ImVec4(0xffd321);
    style.Colors[ImGuiCol_ScrollbarBg] = to_ImVec4(0xffd321);
    style.Colors[ImGuiCol_ScrollbarGrab] = to_ImVec4(0x1a1919);
    style.Colors[ImGuiCol_ScrollbarGrabHovered] = to_ImVec4(0xffe166);
    style.Colors[ImGuiCol_ScrollbarGrabActive] = to_ImVec4(0xffe166);
    style.Colors[ImGuiCol_CheckMark] = to_ImVec4(0);
    style.Colors[ImGuiCol_SliderGrab] = to_ImVec4(0xffd321);
    style.Colors[ImGuiCol_SliderGrabActive] = to_ImVec4(0xffe166);
    style.Colors[ImGuiCol_Button] = to_ImVec4(0xffd321);
    style.Colors[ImGuiCol_ButtonHovered] = ImVec4(0.50f, 0.69f, 0.99f, 0.68f);
    style.Colors[ImGuiCol_ButtonActive] = ImVec4(0.80f, 0.50f, 0.50f, 1.00f);
    style.Colors[ImGuiCol_Header] = to_ImVec4(0xffd321);
    style.Colors[ImGuiCol_HeaderHovered] = ImVec4(0.44f, 0.61f, 0.86f, 1.00f);
    style.Colors[ImGuiCol_HeaderActive] = ImVec4(0.38f, 0.62f, 0.83f, 1.00f);
    style.Colors[ImGuiCol_ResizeGrip] = ImVec4(1.00f, 1.00f, 1.00f, 0.85f);
    style.Colors[ImGuiCol_ResizeGripHovered] = ImVec4(1.00f, 1.00f, 1.00f, 0.60f);
    style.Colors[ImGuiCol_ResizeGripActive] = ImVec4(1.00f, 1.00f, 1.00f, 0.90f);
    style.Colors[ImGuiCol_PlotLines] = ImVec4(1.00f, 1.00f, 1.00f, 1.00f);
    style.Colors[ImGuiCol_PlotLinesHovered] = ImVec4(0.90f, 0.70f, 0.00f, 1.00f);
    style.Colors[ImGuiCol_PlotHistogram] = ImVec4(0.90f, 0.70f, 0.00f, 1.00f);
    style.Colors[ImGuiCol_PlotHistogramHovered] = ImVec4(1.00f, 0.60f, 0.00f, 1.00f);
    style.Colors[ImGuiCol_TextSelectedBg] = ImVec4(0.00f, 0.00f, 1.00f, 0.35f);
}