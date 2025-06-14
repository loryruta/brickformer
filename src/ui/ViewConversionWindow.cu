#include "ViewConversionWindow.h"

#include <imgui.h>

#include "MainScreen.h"
#include "util/misc.hpp"

using namespace lego_builder;

ViewConversionWindow::ViewConversionWindow(MainScreen& parent) : m_parent(parent) { current_subslice = 0; }

void ViewConversionWindow::ui()
{
    CHECK_STATE(m_parent.m_brick_model, "Brick model not present");

    size_t num_subslices = m_parent.m_brick_model->subslice_ranges().size();

    if (ImGui::Begin("View Conversion")) {
        if (ImGui::Button("<")) {
            if (current_subslice > 0) {
                --current_subslice;
                // If the current subslice is manually updated, disable the automatic catch-up
                current_subslice_catch_conversion = false;
            }
        }
        ImGui::SameLine();
        if (ImGui::Button(">")) {
            if (current_subslice < num_subslices - 1) {
                ++current_subslice;
                // If the current subslice is manually updated, disable the automatic catch-up
                current_subslice_catch_conversion = false;
            }
        }
        ImGui::SameLine();
        ImGui::Text("Slice %d/%zu", current_subslice + 1, num_subslices);

        if (ImGui::Button("Reset")) current_subslice = 0;
        if (ImGui::Checkbox("Catch-up with Conversion", &current_subslice_catch_conversion)) {
            if (current_subslice_catch_conversion && m_parent.m_converter) {
                current_subslice = m_parent.m_converter->m_slice_y;
            }
        }
    }
    ImGui::End();
}
