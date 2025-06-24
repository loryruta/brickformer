#include "UIStyle.h"

using namespace bf;

void bf::ui_apply_style()
{
    ImGuiIO& io = ImGui::GetIO();
    ImFontConfig config{};

    config.SizePixels = 17;
    config.OversampleH = config.OversampleV = 1;
    config.PixelSnapH = true;
    g_font = io.Fonts->AddFontFromFileTTF("fonts/RobotoMono-Regular.ttf", 17.0f, &config);

    config.SizePixels = 150;
    config.OversampleH = config.OversampleV = 1;
    config.PixelSnapH = true;
    g_title_font = io.Fonts->AddFontFromFileTTF("fonts/RobotoMono-Bold.ttf", 150.0f, &config);

    ImGuiStyle& style = ImGui::GetStyle();

    style.Colors[ImGuiCol_TextDisabled] = ImVec4(0.60f, 0.60f, 0.60f, 1.00f);
    style.Colors[ImGuiCol_WindowBg] = DARK_COLOR;
    style.Colors[ImGuiCol_PopupBg] = DARK_COLOR;
    style.Colors[ImGuiCol_Border] = ImVec4(0.70f, 0.70f, 0.70f, 0.65f);
    style.Colors[ImGuiCol_BorderShadow] = ImVec4(0.00f, 0.00f, 0.00f, 0.00f);
    style.Colors[ImGuiCol_FrameBg] = DARK_COLOR_LIGHT;
    style.Colors[ImGuiCol_FrameBgHovered] = DARK_COLOR_LIGHT2;
    style.Colors[ImGuiCol_FrameBgActive] = DARK_COLOR_LIGHT2;
    style.Colors[ImGuiCol_TitleBg] = MAIN_COLOR;
    style.Colors[ImGuiCol_TitleBgCollapsed] = MAIN_COLOR;
    style.Colors[ImGuiCol_TitleBgActive] = MAIN_COLOR;
    style.Colors[ImGuiCol_Tab] = MAIN_COLOR;
    style.Colors[ImGuiCol_TabHovered] = MAIN_COLOR_LIGHT;
    style.Colors[ImGuiCol_TabSelected] = MAIN_COLOR_LIGHT;
    style.Colors[ImGuiCol_TabUnfocused] = MAIN_COLOR;
    style.Colors[ImGuiCol_TabDimmed] = MAIN_COLOR;
    style.Colors[ImGuiCol_TabDimmedSelected] = MAIN_COLOR;
    style.Colors[ImGuiCol_MenuBarBg] = MAIN_COLOR;
    style.Colors[ImGuiCol_ScrollbarBg] = MAIN_COLOR;
    style.Colors[ImGuiCol_ScrollbarGrab] = DARK_COLOR;
    style.Colors[ImGuiCol_ScrollbarGrabHovered] = MAIN_COLOR_LIGHT;
    style.Colors[ImGuiCol_ScrollbarGrabActive] = MAIN_COLOR_LIGHT;
    style.Colors[ImGuiCol_CheckMark] = MAIN_COLOR;
    style.Colors[ImGuiCol_SliderGrab] = MAIN_COLOR;
    style.Colors[ImGuiCol_SliderGrabActive] = MAIN_COLOR_LIGHT;
    style.Colors[ImGuiCol_Button] = MAIN_COLOR;
    style.Colors[ImGuiCol_ButtonHovered] = MAIN_COLOR_LIGHT;
    style.Colors[ImGuiCol_ButtonActive] = MAIN_COLOR_LIGHT;
    style.Colors[ImGuiCol_Header] = MAIN_COLOR;
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