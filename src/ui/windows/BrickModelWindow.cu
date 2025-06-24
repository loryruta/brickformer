#include "BrickModelWindow.h"

#include <imgui.h>
#include <nfd.h>

#include "io/BrickModelIO.h"
#include "log.h"
#include "ui/App.h"
#include "ui/MainScreen.h"
#include "ui/UIStyle.h"
#include "util/exceptions.h"
#include "util/misc.h"
#include "util/str_utils.h"
#include "video/gl_helpers.hpp"

#define ARP_LOG_CONTEXT "BrickModelWindow"

using namespace bf;

BrickModelWindow::BrickModelWindow(MainScreen& parent) : m_parent(parent)
{
    current_subslice = 0;

    m_arrow_left_icon = load_gl_texture("arrow_left.png");
    m_arrow_right_icon = load_gl_texture("arrow_right.png");
}

BrickModelWindow::~BrickModelWindow()
{
    glDeleteTextures(1, &m_arrow_left_icon);
    glDeleteTextures(1, &m_arrow_right_icon);
}

void BrickModelWindow::export_bfc()
{
    std::shared_ptr<BrickModel> brick_model = m_parent.m_brick_model;
    CHECK_STATE(brick_model);

    nfdu8char_t* out_path;
    nfdu8filteritem_t filters[]{{"BrickFormer Construction", "bfc"}};
    nfdsavedialognargs_t args{};
    args.filterList = filters;
    args.filterCount = 1;

    nfdresult_t nfd_result = NFD_SaveDialogU8_With(&out_path, &args);
    if (nfd_result == NFD_OKAY) {
        std::filesystem::path export_filepath = out_path;
        NFD_FreePathU8(out_path);
        if (export_filepath.extension() != ".bfc") export_filepath += ".bfc";
        if (std::filesystem::is_directory(export_filepath)) {
            throw IllegalArgumentException("File is a directory: %s", export_filepath.string());
        }
        g_app->enqueue_job([brick_model, export_filepath]() {
            BrickModelIO::bfc_export(*brick_model, export_filepath);
            ARP_INFO("Brick model \"%s\" exported to: %s", brick_model->name(), export_filepath.string());
        });
    }
}

void BrickModelWindow::export_lxf()
{
    std::shared_ptr<BrickModel> brick_model = m_parent.m_brick_model;
    CHECK_STATE(brick_model);

    nfdu8char_t* out_path;
    nfdu8filteritem_t filters[]{{"LXF", "lxf"}};
    nfdsavedialognargs_t args{};
    args.filterList = filters;
    args.filterCount = 1;

    nfdresult_t nfd_result = NFD_SaveDialogU8_With(&out_path, &args);
    if (nfd_result == NFD_OKAY) {
        std::filesystem::path export_filepath = out_path;
        NFD_FreePathU8(out_path);
        if (export_filepath.extension() != ".lxf") export_filepath += ".lxf";
        if (std::filesystem::is_directory(export_filepath)) {
            throw IllegalArgumentException("File is a directory: %s", export_filepath.string());
        }
        g_app->enqueue_job([brick_model, export_filepath]() {
            BrickModelIO::lxf_export(*brick_model, export_filepath);
            ARP_INFO("Brick model \"%s\" exported to: %s", brick_model->name(), export_filepath.string());
        });
    }
}

void BrickModelWindow::ui()
{
    std::shared_ptr<BrickModel> brick_model = m_parent.m_brick_model;
    CHECK_STATE(brick_model, "Brick model not present");
    size_t num_subslices = brick_model->subslice_ranges().size();

    if (ui_window("Brick model", nullptr)) {
        ImVec2 content_region = ImGui::GetContentRegionAvail();

        bool is_converting = m_parent.m_converter && !m_parent.m_converter->is_done();

        ImVec2 slice_button_size(25, 25);
        if (ImGui::ImageButton("##SlicePrev", m_arrow_left_icon, slice_button_size)) {
            if (current_subslice > 0) {
                --current_subslice;
                // If the current subslice is manually updated, disable the automatic catch-up
                current_subslice_catch_conversion = false;
            }
        }
        ImGui::SameLine();
        if (ImGui::ImageButton("##SliceNext", m_arrow_right_icon, slice_button_size)) {
            if (current_subslice < num_subslices - 1) {
                ++current_subslice;
                // If the current subslice is manually updated, disable the automatic catch-up
                current_subslice_catch_conversion = false;
            }
        }
        ImGui::Text("Slice %d/%zu", current_subslice + 1, num_subslices);
        if (is_converting) {
            if (ImGui::Checkbox("Catch-up with Conversion", &current_subslice_catch_conversion)) {
                if (current_subslice_catch_conversion) {
                    current_subslice = m_parent.m_converter->m_slice_y;
                }
            }
        }

        if (ui_button("Initial slice")) current_subslice = 0;
        ImGui::SameLine();
        if (ui_button("Final slice")) current_subslice = num_subslices - 1;

        ImGui::Spacing();

        ImGui::BeginDisabled(is_converting);

        ImGui::BeginGroup();
        {
            ImGuiStyle& style = ImGui::GetStyle();
            float width = (content_region.x - style.FramePadding.x * 2) / 2.0f;
            if (ui_primary_button("Export as BFC", ImVec2(width, 0))) export_bfc();
            ImGui::SameLine();
            if (ui_primary_button("Export as LXF", ImVec2(width, 0))) export_lxf();
        }
        ImGui::EndGroup();

        if (ImGui::BeginItemTooltip()) {
            ImGui::Text("Export the brick construction as BFC or LXF file.\n"
                        "The LXF file can be used to import bricks on your Bricklink cart.");
            ImGui::EndTooltip();
        }

        ImGui::Spacing();

        if (ui_button("Discard")) {
            g_app->enqueue_job([this]() { m_parent.clear_brick_model(); });
        }

        ImGui::EndDisabled();

        ImGui::Spacing();

        /* Debug */
        ImGui::SeparatorText("Debug");

        ImGui::Text("Name:     %s", brick_model->name().c_str());
        ImGui::Text("Vertices: %zu", brick_model->mesh().vertices.size());
        ImGui::Text("Indices:  %zu", brick_model->mesh().indices.size());
        ImGui::Text("Size:     %s", num_bytes_to_string(brick_model->bytesize()).c_str());
        ImGui::Text("Bricks:   %zu", brick_model->total_brick_count());
    }
    ImGui::End();
}
