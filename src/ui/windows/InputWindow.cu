#include "InputWindow.h"

#include <filesystem>

#include <imgui.h>
#include <nfd.h>

#include "Converter.h"
#include "User.h"
#include "io/BrickModelIO.h"
#include "log.h"
#include "ui/App.h"
#include "ui/MainScreen.h"
#include "ui/UIStyle.h"
#include "util/exceptions.h"

#define ARP_LOG_CONTEXT "InputWindow"

using namespace bf;

void InputWindow::browse_model()
{
    nfdu8char_t* out_path;
    nfdu8filteritem_t filters[]{{"glTF", "gltf,glb"}};
    nfdopendialogu8args_t args{};
    args.filterList = filters;
    args.filterCount = 1;

    nfdresult_t nfd_result = NFD_OpenDialogU8_With(&out_path, &args);
    if (nfd_result == NFD_OKAY) {
        std::filesystem::path tmp_model_path = out_path;
        if (!std::filesystem::exists(tmp_model_path)) {
            printf("[ERROR] [InputForm] Invalid path: %s\n", tmp_model_path.c_str());
        } else if (std::filesystem::is_directory(tmp_model_path)) {
            printf("[ERROR] [InputForm] Not a file: %s\n", tmp_model_path.c_str());
        } else if (tmp_model_path.extension() != ".glb" && tmp_model_path.extension() != ".gltf") {
            printf("[ERROR] [InputForm] Invalid extension (supported .glb/.gltf): %s\n",
                   tmp_model_path.extension().c_str());
        } else {
            printf("[INFO ] [InputForm] Selected model: %s\n", out_path);
            model_path = tmp_model_path;
            g_app->enqueue_job([&]() { m_parent.load_and_display_model(model_path); });
        }
        NFD_FreePathU8(out_path);
    }
}

void InputWindow::import_brickformer_construction()
{
    nfdu8char_t* out_path;
    nfdu8filteritem_t filters[]{{"BrickFormer Construction", "bfc"}};
    nfdopendialogu8args_t args{};
    args.filterList = filters;
    args.filterCount = 1;

    nfdresult_t nfd_result = NFD_OpenDialogU8_With(&out_path, &args);
    if (nfd_result == NFD_OKAY) {
        std::filesystem::path bfc_filepath = out_path;
        NFD_FreePathU8(out_path);
        if (!std::filesystem::exists(bfc_filepath) || std::filesystem::is_directory(bfc_filepath)) {
            throw IllegalArgumentException("Invalid file: %s", bfc_filepath.string());
        } else if (bfc_filepath.extension() != ".bfc") {
            throw IllegalArgumentException("Invalid file extension (expected .bfc): %s", bfc_filepath.string());
        }
        g_app->enqueue_job([this, bfc_filepath]() {
            std::shared_ptr<BrickModel> brick_model = BrickModelIO::bfc_import(bfc_filepath);
            m_parent.set_brick_model(brick_model, true /* visualize */);
            ARP_INFO("Imported and baked brick model \"%s\" from: %s\n", brick_model->name(), bfc_filepath.string());
        });
    }
}

void InputWindow::ui()
{
    const PaidPlan* plan = User::get().copy().plan();

    if (ui_window("Input")) {
        ImVec2 content_region = ImGui::GetContentRegionAvail();

        bool can_convert = true;

        ImGui::Text("Model: %s", model_path.empty() ? "-" : model_path.filename().c_str());

        if (!model_path.empty() && ImGui::IsItemHovered()) {
            ImGui::BeginTooltip();
            ImGui::Text("%s", model_path.c_str());
            ImGui::EndTooltip();
        } else if (model_path.empty()) {
            can_convert = false;
        }

        if (ui_button("Browse a model...", ImVec2(content_region.x, 0))) {
            g_app->enqueue_job([this]() { browse_model(); });
        }
        ui_text_wrapped_muted("Supported formats: .glb, .gltf");

        /* XZ Resolution */
        ImGui::Text("XZ Resolution");
        if (ImGui::BeginItemTooltip()) {
            ImGui::Text("The bricks length along the largest axis between X and Z.\n"
                        "The number of Y slices is derived dynamically and displayed below.");
            ImGui::EndTooltip();
        }
        ImGui::SetNextItemWidth(content_region.x);
        ui_slider_int("##Input_Resolution", &resolution, 1, 150);
        if (plan->is_resolution_allowed(resolution)) {
            ImGui::Text("");
        } else {
            ui_text_wrapped_danger("Resolution not available with your plan");
            can_convert = false;
        }

        ImGui::Text("Model orientation");
        ImGui::BeginTable("##Input_ModelOrientation", 2);
        ImGui::TableNextColumn();
        ImGui::RadioButton("+X up", &up_axis, 0);
        ImGui::RadioButton("+Y up", &up_axis, 1);
        ImGui::RadioButton("+Z up", &up_axis, 2);
        ImGui::TableNextColumn();
        ImGui::Checkbox("Flip X", &flip_x);
        ImGui::Checkbox("Flip Y", &flip_y);
        ImGui::Checkbox("Flip Z", &flip_z);
        ImGui::EndTable();

        // Alpha threshold
        ImGui::Text("Alpha threshold");
        if (ImGui::BeginItemTooltip()) {
            ImGui::Text("During conversion, the alpha threshold below which fragments are discarded.\n"
                        "Above, they are converted to a solid color.");
            ImGui::EndTooltip();
        }
        ImGui::SetNextItemWidth(content_region.x);
        ui_slider_float("###Input_AlphaThreshold", &alpha_test_threshold, 0.f, 0.999f);

        if (ui_button("Open Brick Colors...", ImVec2(content_region.x, 0))) {
            g_app->enqueue_job([&]() { m_parent.m_ui.brick_colors_window->is_opened = true; });
        }

        ImGui::Text("Proximity");
        ImGui::Checkbox("Auto", &auto_proximity);
        if (auto_proximity) {
            ImGui::BeginDisabled();
            proximity_threshold = Converter::calc_proximity_threshold(resolution);
            proximity_max_value = Converter::calc_proximity_max_value(resolution);
        }
        ui_slider_int_with_text("Max value", &proximity_max_value, 1, 254);
        ui_slider_int_with_text("Threshold", &proximity_threshold, 1, 32);
        if (auto_proximity) ImGui::EndDisabled();

        ImGui::BeginDisabled(!can_convert);
        if (ui_primary_button("Convert", ImVec2(content_region.x, 50.0f))) {
            g_app->enqueue_job([&]() { m_parent.start_conversion(); });
        }
        ImGui::EndDisabled();

        ImGui::Spacing();
        ImGui::Spacing();
        ImGui::Spacing();

        ImGui::Separator();

        ImGui::Spacing();
        ImGui::Spacing();
        ImGui::Spacing();

        if (ui_button("Import a Brick Construction...", ImVec2(content_region.x, 30.0f))) {
            import_brickformer_construction();
        }

        ui_text_wrapped_muted(
            "Load a previously created brick construction (.bfc format) and visit it slice by slice.");
    }
    ImGui::End();
}

glm::mat4 InputWindow::model_orientation() const
{
    glm::mat4 m{};
    m[3][3] = 1;
    // clang-format off
    // Permute axes but keep the coordinate system left-handed
    if      (up_axis == 0) m[2][0] =  1, m[0][1] = 1, m[1][2] = 1;
    else if (up_axis == 1) m[0][0] =  1, m[1][1] = 1, m[2][2] = 1;
    else if (up_axis == 2) m[0][0] = -1, m[2][1] = 1, m[1][2] = 1;
    // Flip individual axes
    if (flip_x) m[0][0] *= -1, m[1][0] *= -1, m[2][0] *= -1;
    if (flip_y) m[0][1] *= -1, m[1][1] *= -1, m[2][1] *= -1;
    if (flip_z) m[0][2] *= -1, m[1][2] *= -1, m[2][2] *= -1;
    // clang-format on
    return m;
}