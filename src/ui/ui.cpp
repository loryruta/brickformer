#include "ui.hpp"

#include <imgui.h>
#include <nfd.h>

using namespace lego_builder::ui;

void InputWindow::show()
{
    if (ImGui::Begin("##Input"))
    {
        ImGui::Text("Model: %s", model_path.filename().c_str());

        if (ImGui::Button("Select a model"))
        {
            nfdu8char_t* out_path;
            nfdu8filteritem_t filters[]{{"glTF", "gltf,glb"}};
            nfdopendialogu8args_t args{};
            args.filterList = filters;
            args.filterCount = 1;

            nfdresult_t nfd_result = NFD_OpenDialogU8_With(&out_path, &args);
            if (nfd_result == NFD_OKAY)
            {
                std::filesystem::path tmp_model_path = out_path;
                if (!std::filesystem::exists(tmp_model_path))
                {
                    printf("[ERROR] [InputForm] Invalid path: %s!\n", tmp_model_path.c_str());
                }
                else if (std::filesystem::is_directory(tmp_model_path))
                {
                    printf("[ERROR] [InputForm] Not a file: %s\n", tmp_model_path.c_str());
                }
                else if (tmp_model_path.extension() != ".glb" && tmp_model_path.extension() != ".gltf")
                {
                    printf("[ERROR] [InputForm] Invalid extension (supported .glb/.gltf): %s\n", tmp_model_path.extension().c_str());
                }
                else
                {
                    printf("[INFO ] [InputForm] Selected model: %s\n", out_path);
                    model_path = tmp_model_path;
                    if (on_input_change) on_input_change();
                }
                NFD_FreePathU8(out_path);
            }
        }

        if (ImGui::SliderInt("Resolution", &resolution, 1, 256) && on_input_change) on_input_change();
        ImGui::Text("Num slices: %d", display_num_slices);

        if (ImGui::Checkbox("Flip X", &flip_x) && on_input_change) on_input_change();
        if (ImGui::Checkbox("Flip Y", &flip_y) && on_input_change) on_input_change();
        if (ImGui::Checkbox("Flip Z", &flip_z) && on_input_change) on_input_change();

        if (ImGui::SliderFloat("Alpha test threshold", &alpha_test_threshold, 0.f, 0.999f) && on_input_change) on_input_change();

        ImGui::Text("Proximity");
        ImGui::Checkbox("Auto", &auto_proximity_settings);
        if (auto_proximity_settings) ImGui::BeginDisabled();
        ImGui::SliderInt("Max value", &proximity_max_value, 1, 254);
        ImGui::SliderInt("Threshold", &proximity_threshold, 1, 32);
        if (auto_proximity_settings) ImGui::EndDisabled();

        if (model_path.empty())
            ImGui::BeginDisabled();
        if (ImGui::Button("Convert"))
        {
            if (on_submit)
                on_submit();
        }
        if (model_path.empty())
            ImGui::EndDisabled();
    }
    ImGui::End();
}

void ViewSettingsWindow::show()
{
    if (ImGui::Begin("View settings"))
    {
        ImGui::Checkbox("Show model", &show_model);
        ImGui::Checkbox("Show Brick height adjustment", &perform_brick_height_adjustment);
        ImGui::Checkbox("Show grid", &show_grid);
        ImGui::Checkbox("Show construction", &show_construction);
        ImGui::Checkbox("Show voxels", &show_voxels);
        ImGui::Checkbox("Ambient Occlusion", &ssao);
    }
    ImGui::End();
}

void MapsWindow::show()
{
    if (ImGui::Begin("Maps"))
    {
        ImGui::RadioButton("Color map", (int*) &map_type, MapType_ColorMap);
        ImGui::RadioButton("Placement map", (int*) &map_type, MapType_PlacementMap);
        ImGui::RadioButton("Proximity map (previous slice)", (int*) &map_type, MapType_ProximityMap);

        GLuint texture = 0;

        // Color map
        if (map_type == MapType_ColorMap)
        {
            ImGui::NewLine();
            texture = color_map;
        }
        // Proximity map
        else if (map_type == MapType_ProximityMap)
        {
            ImGui::NewLine();
            texture = proximity_map;
        }
        // Placement map
        else if (map_type == MapType_PlacementMap)
        {
            if (ImGui::ArrowButton("subslice_left", ImGuiDir_Left) && subslice_idx > 0)
            {
                if (subslice_idx > 0) --subslice_idx;
            }
            ImGui::SameLine();
            if (ImGui::ArrowButton("subslice_right", ImGuiDir_Right) && subslice_idx < 2)
            {
                if (subslice_idx < 2) ++subslice_idx;
            }
            ImGui::SameLine();
            ImGui::Text("Slice %d/2", subslice_idx);
            ImGui::SameLine();
            ImGui::Checkbox("Color", &show_colored_placement_map);

            texture = show_colored_placement_map ? colored_placement_maps[subslice_idx] : hashed_placement_maps[subslice_idx];
        }

        ImVec2 image_size;
        image_size.x = ImGui::GetContentRegionAvail().x;
        image_size.y = ImGui::GetContentRegionAvail().x;

        ImGui::Image(reinterpret_cast<void*>(texture), image_size, ImVec2(0, 1), ImVec2(1, 0));
    }
    ImGui::End();
}

