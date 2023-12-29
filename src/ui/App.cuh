#pragma once

#include <memory>
#include <optional>

#include "Arpenteur.cuh"
#include "Queue.hpp"
#include "ui/video/CustomFramebuffer.hpp"
#include "ui/video/cuda_interop_helpers.cuh"
#include "util/StopWatch.hpp"
#include "video/ModelRenderer.hpp"
#include "video/TextureRenderer.hpp"
#include "video/Window.hpp"

namespace lego_builder
{
class App : public ArpenteurListener
{
private:
    Window& m_window;

    std::filesystem::path m_model_path;
    uint32_t m_slice_side;

    std::unique_ptr<Arpenteur> m_arpenteur;

    ModelRenderer m_model_renderer;
    TextureRenderer m_texture_renderer;

    CustomFramebuffer m_model_view_framebuffer{512, 512};
    std::optional<CudaMappedGlTexture> m_color_map_cuda_mapping;
    std::optional<CudaMappedGlTexture> m_proximity_map_cuda_mapping;

    std::optional<CudaMappedGlTexture> m_subslice0_cuda_mapping;
    std::optional<CudaMappedGlTexture> m_subslice1_cuda_mapping;
    std::optional<CudaMappedGlTexture> m_subslice2_cuda_mapping;

    enum VisualizeMapType : uint8_t
    {
        VisualizeMapType_ColorMap = 0, VisualizeMapType_ProximityMap, VisualizeMapType_PlacementMap
    };

    VisualizeMapType m_visualized_map = VisualizeMapType_ColorMap;
    int32_t m_visualized_subslice_idx = 0; ///< The subslice being visualized

    /// If the placement takes too long, this stopwatch is used to visualize intermediate result at fixed intervals.
    StopWatch m_placement_stopwatch;
    const float k_placement_visualization_period = 5.0f;  // In seconds

    std::unique_ptr<BakedModel> m_baked_model;
    Camera m_camera;
    glm::vec3 m_look_at_position;
    float m_camera_speed = 40.0f;

    float m_dt;
    double m_last_frame_t;

    /// A queue holding the jobs that have to be executed on main thread (GL thread).
    Queue<std::function<void()>> m_job_queue;

    std::atomic<bool> m_arpenteur_should_run = true;  ///< Used to manually stop le thread de l'Arpenteur.
    std::atomic<bool> m_autorun = false; ///< If true, l'Arpenteur runs without having to be manually restarted.

    mutable std::mutex m_job_queue_mutex;
    std::condition_variable m_job_queue_cond_var;  ///< Used to wait for main thread jobs to complete before proceeding.

public:
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

    void copy_color_map();
    void copy_proximity_map();
    void write_placement_maps();

    /// Function meant to be called from the Arpenteur's thread:
    /// Enqueues a job to copy the color map, proximity map and placement maps; and blocks the thread until executed.
    void enqueue_and_wait_copy_maps_job();

    void show_model_window();
    void show_color_map_window();
    void show_proximity_map_window();
    void show_placement_map_window();
};
}

