#pragma once

#include <memory>
#include <optional>

#include <firebase/app.h>
#include <firebase/auth.h>

#include "BrickModel.h"
#include "Screen.h"
#include "util/Queue.h"
#include "util/StopWatch.h"
#include "video/BrickPlaneRenderer.h"
#include "video/BrickRenderer.h"
#include "video/CustomFramebuffer.hpp"
#include "video/GridRenderer.hpp"
#include "video/ModelRenderer.hpp"
#include "video/TextureRenderer.hpp"
#include "video/VoxelModelBuilder.hpp"
#include "video/Window.hpp"
#include "video/cuda_interop_helpers.cuh"

namespace bf
{
class App
{
private:
    Window& m_window;

    /* Renderers */
    std::unique_ptr<ModelRenderer> m_model_renderer;
    std::unique_ptr<TextureRenderer> m_texture_renderer;
    std::unique_ptr<GridRenderer> m_grid_renderer;
    std::unique_ptr<BrickRenderer> m_brick_renderer;
    std::unique_ptr<BrickPlaneRenderer> m_brick_plane_renderer;

    /// If the placement takes too long, this stopwatch is used to visualize intermediate result at fixed intervals.
    StopWatch m_placement_stopwatch;
    const float k_placement_visualization_period = 5.0f; // In seconds

    /* Firebase */
    firebase::App* m_firebase_app;
    firebase::auth::Auth* m_firebase_auth;

    std::shared_ptr<Screen> m_screen;

    float m_dt;
    double m_last_frame_t;

    /// A queue holding the jobs that have to be executed on main thread (GL thread).
    Queue<std::function<void()>> m_job_queue;

    mutable std::mutex m_job_queue_mutex;
    std::condition_variable m_job_queue_cond_var; ///< Used to wait for main thread jobs to complete before proceeding.

public:
    explicit App(Window& window);
    ~App();

    [[nodiscard]] Window& window() { return m_window; }
    [[nodiscard]] glm::ivec2 resolution() const { return m_window.framebuffer_size(); }

    ModelRenderer& model_renderer() const { return *m_model_renderer; }
    TextureRenderer& texture_renderer() const { return *m_texture_renderer; }
    GridRenderer& grid_renderer() const { return *m_grid_renderer; }
    BrickRenderer& brick_renderer() const { return *m_brick_renderer; }
    BrickPlaneRenderer& brick_plane_renderer() const { return *m_brick_plane_renderer; }

    firebase::App* firebase_app() const { return m_firebase_app; }
    firebase::auth::Auth* firebase_auth() const { return m_firebase_auth; }

    void set_screen(std::shared_ptr<Screen>&& new_screen)
    {
        // Changing the screen can't be executed immediately otherwise the calling screen will delete itself!
        // Therefore, the switch operation is queued at the end of the frame
        m_job_queue.push([this, new_screen = std::move(new_screen)]() {
            const char* from_name = m_screen ? m_screen->name() : "null";
            const char* to_name = new_screen ? new_screen->name() : "null";
            printf("[INFO ] [App] Switching screen: %s -> %s\n", from_name, to_name);
            // Delete current screen if any
            m_screen.reset();
            // Create and set the new screen
            m_screen = new_screen;
            if (new_screen) {
                glm::ivec2 resolution_ = resolution();
                m_screen->resize(resolution_);
                printf("[DEBUG] [App] Resized %s to (%d, %d)\n", to_name, resolution_.x, resolution_.y);
            }
        });
    }

    void start();

    /* Jobs */
    void enqueue_job(const std::function<void()>& job) { m_job_queue.push(job); }
    void wait_job_completion()
    {
        std::unique_lock<std::mutex> lock(m_job_queue_mutex);
        m_job_queue_cond_var.wait(lock, [this]() { return m_job_queue.empty(); });
    }
    void clear_jobs_queue();

private:
    void setup_firebase();
};

inline App* g_app = nullptr;
/// CUDA stream used by the main thread, generally for visualization purposes.
inline cudaStream_t g_stream = nullptr;
} // namespace bf
