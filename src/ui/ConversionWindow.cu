#include "ConversionWindow.h"

#include <imgui.h>
#include <stb_image.h>

#include "App.h"
#include "MainScreen.h"
#include "video/gl_helpers.hpp"

using namespace lego_builder;

ConversionWindow::ConversionWindow(MainScreen& parent) : m_parent(parent)
{
    m_pause_icon = load_gl_texture("pause.png");
    m_play_icon = load_gl_texture("play.png");
    m_stop_icon = load_gl_texture("stop.png");
}

ConversionWindow::~ConversionWindow()
{
    glDeleteTextures(1, &m_pause_icon);
    glDeleteTextures(1, &m_play_icon);
    glDeleteTextures(1, &m_stop_icon);
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

    if (ImGui::Begin("Conversion Window")) {
        if (!m_parent.m_converter_should_run) {
            if (ImGui::ImageButton("##ConversionResume", m_play_icon, k_button_size)) {
                resume_conversion();
            }
        } else {
            if (ImGui::ImageButton("##ConversionPause", m_pause_icon, k_button_size)) {
                m_parent.m_converter_should_run = false;
                m_parent.m_converter_autorun = false;
            }
        }
        ImGui::SameLine();
        if (ImGui::ImageButton("##ConversionStop", m_stop_icon, k_button_size)) {
            // Delegate the stop because we don't want to invalidate m_converter now!
            g_app->enqueue_job([&]() { m_parent.stop_conversion(); });
        }
        bool autorun = m_parent.m_converter_autorun.load();
        if (ImGui::Checkbox("Autorun", &autorun)) {
            m_parent.m_converter_autorun.store(autorun);
            resume_conversion();
        }

        const auto& converter = *m_parent.m_converter;
        const auto& placement_solver = *m_parent.m_converter->m_placement_solver;
        ImGui::Text("Solution space: %zu (possible placements)", placement_solver.m_num_placements);
        ImGui::Text("XZ resolution: %d", placement_solver.m_resolution);
        ImGui::Text("GPU grid: %zu", placement_solver.m_num_blocks);
        ImGui::Text("Y slice: %d/%d", converter.m_slice_y + 1, converter.m_num_slices);
    }
    ImGui::End();
}
