#pragma once

#include <filesystem>
#include <functional>
#include <string>

#include <glad/gl.h>
#include <glm/glm.hpp>

#include "View3dWindow.hpp"

namespace lego_builder::ui
{
/// The window where the user can select the model to convert and the resolution.
struct InputWindow
{
    std::filesystem::path model_path = "";
    int resolution = 50;
    bool flip_x = false;
    bool flip_y = false;
    bool flip_z = false;

    int display_num_slices = -1;

    /* Callbacks */
    std::function<void()> on_input_change;
    std::function<void()> on_submit;

    void show();
};

/// A window used to edit options regarding the model/construction visualization.
struct ViewSettingsWindow
{
    bool show_model = true;
    bool perform_brick_height_adjustment = true;
    bool show_grid = true;
    bool show_construction = true;
    bool show_voxels = false;
    bool ssao = true;

    void show();
};

/// A window used to visualize all the maps used during the conversion process (i.e. color map, placement map, proximity map).
struct MapsWindow
{
    enum
    {
        MapType_ColorMap = 0,
        MapType_ProximityMap,
        MapType_PlacementMap
    } map_type;

    GLuint color_map;
    GLuint proximity_map;
    GLuint colored_placement_maps[3];
    GLuint hashed_placement_maps[3];
    bool show_colored_placement_map = false;
    int subslice_idx = 0;

    void show();
};

} // namespace lego_builder::ui
