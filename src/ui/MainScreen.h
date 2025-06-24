#pragma once

#include <filesystem>
#include <optional>
#include <thread>

#include <glad/gl.h>

#include "Converter.h"
#include "ConverterVisualizationBridge.h"
#include "Screen.h"
#include "UserSyncDaemon.h"
#include "model/Model.h"
#include "video/Camera.hpp"
#include "video/ModelRenderer.hpp"
#include "video/cuda_interop_helpers.cuh"
#include "windows/BrickColorsWindow.h"
#include "windows/BrickModelWindow.h"
#include "windows/ConversionWindow.h"
#include "windows/InputWindow.h"
#include "windows/UserWindow.h"
#include "windows/View3dWindow.h"

namespace bf
{
// Forward decl
class MainScreen;

namespace ui
{
/// A window used to edit options regarding the model/construction visualization.
struct ViewSettingsWindow {
    bool show_model = true;
    bool perform_brick_height_adjustment = true;
    bool show_grid = true;
    bool show_brick_model = true;
    bool show_brick_plane = true;
    bool ssao = true;

    void show();
};

/// A window used to visualize all the maps used during the conversion process (i.e. color map, placement map, proximity
/// map).
struct MapsWindow {
    enum { MapType_ColorMap = 0, MapType_ProximityMap, MapType_PlacementMap } map_type = MapType_ColorMap;

    GLuint color_map;
    GLuint proximity_map;
    GLuint colored_placement_maps[3];
    GLuint hashed_placement_maps[3];
    bool show_colored_placement_map = false;
    int subslice_idx = 0;

    void show();
};
} // namespace ui

class MainScreen : public Screen, public ConverterListener
{
    friend class BrickModelWindow;
    friend class ConverterVisualizationBridge;
    friend class ConversionWindow;
    friend class InputWindow;

private:
    Camera m_camera;

    struct {
        std::unique_ptr<InputWindow> input_window;
        ui::ViewSettingsWindow view_settings;
        std::unique_ptr<UserWindow> user_window;
        std::unique_ptr<ConversionWindow> conversion_window;
        ui::MapsWindow maps;
        std::unique_ptr<ui::View3dWindow> view_3d_window;
        std::unique_ptr<BrickModelWindow> brick_model_window;
        std::unique_ptr<BrickColorsWindow> brick_colors_window;
    } m_ui;

    /* Model */
    std::unique_ptr<Model> m_model;
    std::unique_ptr<BakedModel> m_baked_model;

    /* Converter */
    std::unique_ptr<Converter> m_converter;
    std::unique_ptr<std::thread> m_converter_thread;
    std::unique_ptr<ConverterVisualizationBridge> m_converter_visualization_bridge;
    /// If \c false, the conversion stops after a slice is fully placed and has to be manually resumed.
    std::atomic<bool> m_converter_should_run = true;
    ///< If \c true, the conversion runs continuously without having to be manually resumed.
    std::atomic<bool> m_converter_autorun = false;

    /* View Conversion */
    /// The brick model to visualize (to aid construction).
    /// Can be either the live brick construction under conversion, or a pre-saved construction.
    std::shared_ptr<BrickModel> m_brick_model;
    std::unique_ptr<BrickRenderer_BakedModel> m_baked_brick_model;

    std::unique_ptr<UserSyncDaemon> m_user_sync_daemon;

public:
    explicit MainScreen();
    ~MainScreen();

    [[nodiscard]] const char* name() const override { return "MainScreen"; }

    void resize(glm::ivec2 resolution) override {}
    void update(float dt) override;
    void render() override;

    /* UI */
    void ui_user_window();
    void ui() override;

    /* ConverterListener */
    void on_model_load(const Model& model) override {}
    void on_placement_begin(uint32_t slice_y) override {}
    void on_place(uint32_t slice_y, const Placement& placement, float reward) override {}
    void on_placement_end(uint32_t slice_y, const std::vector<Placement>& placements) override;

    void set_brick_model(std::shared_ptr<BrickModel> brick_model, bool visualize);
    void clear_brick_model();

private:
    void load_and_display_model(const std::filesystem::path& model_filepath);

    void on_input_change();

    void start_conversion();
    void stop_conversion(bool discard);

    void render_3d_scene();
};
} // namespace bf
