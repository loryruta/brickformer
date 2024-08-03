#pragma once

#include <memory>
#include <optional>

#include "Arpenteur.cuh"
#include "BrickModelBuilder.hpp"
#include "Queue.hpp"
#include "ui.hpp"
#include "util/BoundingBox3f.hpp"
#include "util/StopWatch.hpp"
#include "video/CustomFramebuffer.hpp"
#include "video/VoxelModelBuilder.hpp"
#include "video/cuda_interop_helpers.cuh"
#include "video/GridRenderer.hpp"
#include "video/ModelRenderer.hpp"
#include "video/TextureRenderer.hpp"
#include "video/Window.hpp"

namespace lego_builder
{
class App : public ArpenteurListener
{
private:
    Window& m_window;

    std::unique_ptr<ModelRenderer> m_model_renderer;
    TextureRenderer m_texture_renderer;
    std::unique_ptr<GridRenderer> m_grid_renderer;

    CustomFramebuffer m_model_view_framebuffer{1500, 1500};

    std::optional<CudaMappedGlTexture> m_color_map_cuda_mapping;
    std::optional<CudaMappedGlTexture> m_proximity_map_cuda_mapping;
    std::vector<CudaMappedGlTexture> m_hashed_placement_map_cuda_mappings;
    std::vector<CudaMappedGlTexture> m_colored_placement_map_cuda_mappings;

    BrickModelBuilder m_brick_model_builder; // TODO rename
    std::unique_ptr<BakedModel> m_baked_construction_model;

    VoxelModelBuilder m_voxel_model_builder;
    std::unique_ptr<BakedModel> m_baked_voxel_model;

    /// If the placement takes too long, this stopwatch is used to visualize intermediate result at fixed intervals.
    StopWatch m_placement_stopwatch;
    const float k_placement_visualization_period = 5.0f;  // In seconds

    /* Model */
    std::string m_view_model_path = ""; // Used to detect when the UI model changes
    std::unique_ptr<Model> m_model;
    std::unique_ptr<BakedModel> m_baked_model;
    glm::mat4 m_model_to_view_transform; ///< Transform from original Model space to View space
    BoundingBox3f m_model_bbox; ///< Model bounding box in View space
    glm::mat4 m_conversion_to_view_transform; ///< Transform from Conversion space to View space

    /* UI */
    ui::InputWindow m_ui_input;
    ui::ViewSettingsWindow m_ui_view_settings;
    ui::MapsWindow m_ui_maps_window;
    std::unique_ptr<ui::View3dWindow> m_ui_view_3d_window;

    Camera m_camera;
    float m_camera_speed = 40.0f;
    bool m_freecam = true;  // TODO default false
    glm::mat4 m_undo_brick_height_adjustment_matrix{1.0f};

    float m_dt;
    double m_last_frame_t;

    /* Arpenteur */
    ArpenteurInput m_input;
    std::unique_ptr<Arpenteur> m_arpenteur;
    std::unique_ptr<std::thread> m_arpenteur_thread;

    /// A queue holding the jobs that have to be executed on main thread (GL thread).
    Queue<std::function<void()>> m_job_queue;

    std::atomic<bool> m_arpenteur_should_run = true;  ///< Used to manually stop le thread de l'Arpenteur.
    std::atomic<bool> m_autorun = false; ///< If true, l'Arpenteur runs without having to be manually restarted.

    mutable std::mutex m_job_queue_mutex;
    std::condition_variable m_job_queue_cond_var;  ///< Used to wait for main thread jobs to complete before proceeding.

public:
    static constexpr float k_max_view_side = 100.f;

    explicit App(Window& window);
    ~App();

    void run();

    // Arpenteur listener functions: async!

    void on_model_load(const Model& model) override;
    void on_placement_begin(uint32_t slice_y) override;
    void on_place(uint32_t slice_y, const Placement& placement, float reward) override;
    void on_placement_end(uint32_t slice_y) override;

private:
    void render();

    void stop_conversion();
    void start_conversion();

    void copy_color_map();
    void copy_proximity_map();

    /// Takes the slice placements and writes them to the given images (either by using their colors or hashed colors).
    /// The images are then expected to be used for visualization.
    void write_placement_maps(std::vector<CudaMappedGlTexture>& out_images, bool use_hashed_color);

    /// Having the placements for the current slice, adds the vertices of them to create the 3d model of the construction (for visualization).
    void add_placements_to_construction_model();

    /// Converts the pixels of the Color map to voxels shown in the 3d scene.
    void add_color_map_voxels();

    /// Function meant to be called from the Arpenteur's thread:
    /// Enqueues a job to copy the color map, proximity map and placement maps; and blocks the thread until executed.
    void enqueue_and_wait_copy_maps_job();

    /// Renders a 3d scene displaying the model and the LEGO construction while it's building up.
    void render_3d_scene();

    /// Method called whenever Arpenteur input changes (e.g. new model, resolution changed...).
    void on_input_change();

    void show_main_window();
};
}

