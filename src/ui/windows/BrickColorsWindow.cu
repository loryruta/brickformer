#include "BrickColorsWindow.h"

#include <imgui.h>

#include "AssignPlacementColor.h"
#include "BrickColors.h"
#include "User.h"
#include "lego_dataset.h"
#include "ui/App.h"
#include "ui/UIStyle.h"

using namespace bf;

BrickColorsWindow::BrickColorsWindow() {}

void BrickColorsWindow::ui_color_list()
{
    BrickColors& colors = BrickColors::get();
    const PaidPlan* plan = User::get().copy().plan();

    bool reupload_colors = false;

    if (ui_window("Colors##BrickColors")) {
        ImGui::BeginTable("##BrickColorsTable", 4, ImGuiTableColumnFlags_WidthFixed);
        // Headers
        ImGui::TableSetupColumn("ID", ImGuiTableColumnFlags_WidthFixed, 50.0f);
        ImGui::TableSetupColumn("Color");
        ImGui::TableSetupColumn("Online ID", ImGuiTableColumnFlags_WidthFixed, 75.0f);
        ImGui::TableSetupColumn("Enabled", ImGuiTableColumnFlags_WidthFixed, 220.0f);
        ImGui::TableHeadersRow();
        // Data
        for (int cid = 0; cid < k_num_brick_colors; ++cid) {
            bool available = plan->is_brick_color_allowed(cid);
            ImGui::BeginDisabled(!available);
            const BrickColor& color = k_brick_colors[cid];
            ImGui::TableNextColumn(), ImGui::Text("%d", cid);
            // Color
            ImGui::TableNextColumn();
            glm::vec3 rgb_01 = k_brick_colors_rgb[cid] / 255.0f;
            ImVec4 rgb_imvec4;
            rgb_imvec4.x = rgb_01.r;
            rgb_imvec4.y = rgb_01.g;
            rgb_imvec4.z = rgb_01.b;
            rgb_imvec4.w = 1.0f;
            std::string color_id_str = "##BrickColor_Color_" + std::to_string(cid);
            ImGui::ColorButton(color_id_str.c_str(), rgb_imvec4, ImGuiColorEditFlags_NoAlpha);
            ImGui::SameLine();
            ImGui::Text("%s", color.name);
            // Online ID
            ImGui::TableNextColumn(), ImGui::Text("%d", color.lego_id);
            std::string checkbox_id_str = "##ActiveBrickColor_" + std::to_string(cid);
            // Enabled
            bool enabled = colors.is_enabled(cid);
            ImGui::TableNextColumn();
            if (available) {
                if (ImGui::Checkbox(checkbox_id_str.c_str(), &enabled)) {
                    colors.set_enabled(cid, enabled);
                    reupload_colors = true;
                }
            } else {
                ImGui::TextWrapped("Unavailable with your plan");
            }
            ImGui::EndDisabled();
        }
        ImGui::EndTable();
    }
    ImGui::End();

    if (reupload_colors) {
        closest_cid = -1;
        g_app->enqueue_job([&colors]() { colors.upload_colors(); });
    }
}

void BrickColorsWindow::ui_color_similarity_test()
{
    BrickColors& colors = BrickColors::get();

    if (ui_window("Similarity Test##BrickColors")) {
        ImGui::BeginTable("##BrickColors_SimilarityTest_Table", 2);

        ImGui::TableSetupColumn("ColorPicker##BrickColors");
        ImGui::TableSetupColumn("Result##BrickColors", ImGuiTableColumnFlags_WidthFixed, 200.0f);

        ImGui::TableNextColumn();
        ImGuiColorEditFlags color_edit_flags = ImGuiColorEditFlags_NoSmallPreview;
        color_edit_flags |= ImGuiColorEditFlags_NoInputs;
        bool changed = ImGui::ColorPicker3("Query Color##BrickColors", &query_color.r, color_edit_flags);
        if (changed || closest_cid < 0) {
            closest_cid =
                AssignPlacementColor::search_nearest_cid(query_color * 255.0f, colors.color_mask_all_bricks());
            if (closest_cid < 0) {
                CHECK_STATE(closest_cid >= 0, "Nearest Brick Color weirdly failed: %d (CID >= 0)", closest_cid);
            }
        }
        if (closest_cid >= 0) {
            const BrickColor& color = k_brick_colors[closest_cid];
            glm::vec3 rgb_01 = k_brick_colors_rgb[closest_cid] / 255.0f;
            ImVec4 rgb_imvec4;
            rgb_imvec4.x = rgb_01.r;
            rgb_imvec4.y = rgb_01.g;
            rgb_imvec4.z = rgb_01.b;
            rgb_imvec4.w = 1.0f;

            ImGui::TableNextColumn();
            ImGui::Text("Closest Color");
            ImGui::ColorButton("##BrickColors_ClosestColor", rgb_imvec4);
            ImGui::SameLine();
            ImGui::Text("%s", color.name);
            ImGui::Text("ID: %3d, Online ID: %3d", closest_cid, color.id);
        }
        ImGui::EndTable();
    }
    ImGui::End();
}

void BrickColorsWindow::ui()
{
    if (is_opened) {
        ImGuiWindowFlags flags = ImGuiWindowFlags_NoDocking;
        flags |= ImGuiWindowFlags_NoCollapse;
        ImGui::PushStyleColor(ImGuiCol_TitleBg, MAIN_COLOR);
        ImGui::PushStyleColor(ImGuiCol_TitleBgActive, MAIN_COLOR);
        ImGui::PushStyleColor(ImGuiCol_TitleBgCollapsed, MAIN_COLOR);
        if (ui_window("Brick Colors##BrickColors", &is_opened, flags)) {
            ImGui::PopStyleColor(3);
            ImGuiID dockspace_id = ImGui::GetID("DockSpace##BrickColors");
            ImGui::DockSpace(dockspace_id);
        }
        ImGui::End();

        ui_color_list();
        ui_color_similarity_test();
    }
}