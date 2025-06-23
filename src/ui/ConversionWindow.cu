#include "ConversionWindow.h"

#include <imgui.h>
#include <imgui_internal.h>

#include "App.h"
#include "MainScreen.h"
#include "UIStyle.h"
#include "video/gl_helpers.hpp"

using namespace lego_builder;

ConversionWindow::ConversionWindow(MainScreen& parent) : m_parent(parent)
{
    m_pause_icon = load_gl_texture("pause.png");
    m_play_icon = load_gl_texture("play.png");
    m_stop_icon = load_gl_texture("stop.png");
    m_speed_play_icon = load_gl_texture("speed_play.png");
}

ConversionWindow::~ConversionWindow()
{
    glDeleteTextures(1, &m_pause_icon);
    glDeleteTextures(1, &m_play_icon);
    glDeleteTextures(1, &m_stop_icon);
    glDeleteTextures(1, &m_speed_play_icon);
}

void ConversionWindow::resume_conversion()
{
    m_parent.m_converter_should_run = true;
    m_parent.m_converter_should_run.notify_all();
}

void ConversionWindow::ui()
{
    static constexpr ImVec2 k_button_size = ImVec2(20.0f, 20.0f);

    CHECK_STATE(m_parent.m_converter, "Can't show Conversion window without converter");
    ImGuiWindowClass notabbar_class;
    notabbar_class.DockNodeFlagsOverrideSet = ImGuiDockNodeFlags_NoTabBar;
    ImGui::SetNextWindowClass(&notabbar_class);
    if (ui_window("Conversion Window")) {
        ImVec2 content_region = ImGui::GetContentRegionAvail();

        const Converter& converter = *m_parent.m_converter;
        bool is_done = converter.is_done();
        bool autorun = m_parent.m_converter_autorun;

        ImGui::BeginDisabled(is_done);
        if (!m_parent.m_converter_should_run && !autorun) {
            if (ImGui::ImageButton("##ConversionResume", m_play_icon, k_button_size)) {
                resume_conversion();
            }
        } else {
            if (ImGui::ImageButton("##ConversionPause", m_pause_icon, k_button_size)) {
                m_parent.m_converter_should_run = false;
                m_parent.m_converter_autorun = false;
            }
        }
        ImGui::BeginDisabled(autorun);
        ImGui::SameLine();
        if (ImGui::ImageButton("##ConversionAutorun", m_speed_play_icon, k_button_size)) {
            m_parent.m_converter_autorun = true;
            resume_conversion();
        }
        ImGui::EndDisabled();
        ImGui::EndDisabled();

        if (ui_button("Discard", ImVec2(content_region.x, 0))) {
            // Delegate the stop because we don't want to invalidate converter now!
            g_app->enqueue_job([&]() { m_parent.stop_conversion(true); });
        }
        if (ui_primary_button("Done", ImVec2(content_region.x, 0))) {
            g_app->enqueue_job([&]() { m_parent.stop_conversion(false); });
        }

        ImGui::SeparatorText("Converter Information");

        const auto& placement_solver = *m_parent.m_converter->m_placement_solver;
        ImGui::Text("Solution space: %zu", placement_solver.m_num_placements);
        ImGui::Text("XZ resolution:  %d", placement_solver.m_resolution);
        ImGui::Text("GPU grid:       %zu", placement_solver.m_num_blocks);
        ImGui::Text("Y slice:        %d/%d", converter.m_slice_y + 1, converter.m_num_slices);
    }
    ImGui::End();
}
