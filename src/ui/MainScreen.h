#pragma once

#include <filesystem>
#include <optional>
#include <thread>

#include <glad/gl.h>

#include "Converter.h"
#include "ConverterVisualizationBridge.h"
#include "Screen.h"
#include "View3dWindow.h"
#include "model/Model.hpp"
#include "util/BoundingBox3f.hpp"
#include "video/Camera.hpp"
#include "video/ModelRenderer.hpp"
#include "video/cuda_interop_helpers.cuh"

namespace lego_builder
{
namespace ui
{
/// The window where the user can select the model to convert and the resolution.
struct InputWindow {
    std::filesystem::path model_path = "";
    int resolution = 50;
    bool flip_x = false;
    bool flip_y = false;
    bool flip_z = false;
    float alpha_test_threshold = 0.7f;

    bool auto_proximity_settings = true;
    int proximity_max_value = UINT8_MAX;
    int proximity_threshold = 1;

    int display_num_slices = -1;

    /* Callbacks */
    std::function<void()> on_input_change;
    std::function<void()> on_submit;

    void show();
};

/// A window used to edit options regarding the model/construction visualization.
struct ViewSettingsWindow {
    bool show_model = true;
    bool perform_brick_height_adjustment = true;
    bool show_grid = true;
    bool show_construction = true;
    bool show_voxels = false;
    bool ssao = true;

    void show();
};

/// A window used to visualize all the maps used during the conversion process (i.e. color map, placement map, proximity
/// map).
struct MapsWindow {
    enum { MapType_ColorMap = 0, MapType_ProximityMap, MapType_PlacementMap } map_type;

    GLuint color_map;
    GLuint proximity_map;
    GLuint colored_placement_maps[3];
    GLuint hashed_placement_maps[3];
    bool show_colored_placement_map = false;
    int subslice_idx = 0;

    void show();
};
} // namespace ui

class MainScreen : public Screen
{
private:
    Camera m_camera;
    float m_camera_speed = 40.0f;
    bool m_freecam = true; // TODO default false
    glm::mat4 m_undo_brick_height_adjustment_matrix{1.0f};

    struct {
        ui::InputWindow input;
        ui::ViewSettingsWindow view_settings;
        ui::MapsWindow maps;
        std::unique_ptr<ui::View3dWindow> view_3d_window;
    } m_ui;

    /* Model */
    std::string m_view_model_path{}; // Used to detect when the UI model changes
    std::unique_ptr<Model> m_model;
    std::unique_ptr<BakedModel> m_baked_model;
    glm::mat4 m_model_to_view_transform;      ///< Transform from original Model space to View space
    BoundingBox3f m_model_bbox;               ///< Model bounding box in View space
    glm::mat4 m_conversion_to_view_transform; ///< Transform from Conversion space to View space

    /* Conversion */
    std::unique_ptr<Converter> m_converter;
    std::unique_ptr<std::thread> m_converter_thread;
    std::unique_ptr<ConverterVisualizationBridge> m_converter_visualization_bridge;

    std::atomic<bool> m_converter_should_run = true; ///< Used to manually stop the Converter thread
    std::atomic<bool> m_autorun = false; ///< If \c true, l'Arpenteur runs without having to be manually restarted

public:
    static constexpr float k_max_view_side = 100.f;

    explicit MainScreen();
    ~MainScreen() = default;

    [[nodiscard]] const char* name() const override { return "MainScreen"; }

    void resize(glm::ivec2 resolution) override {}
    void update(float dt) override;
    void render() override;
    void ui() override;

private:
    void on_input_change();

    void start_conversion();
    void clear_conversion();

    void render_3d_scene();
};
} // namespace lego_builder
