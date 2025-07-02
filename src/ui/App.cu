#include "App.h"

#include <GLFW/glfw3.h>
#include <glad/gl.h>
#include <imgui.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>

#include "AuthScreen.h"
#include "UIStyle.h"
#include "log.h"
#include "util/exceptions.h"
#include "video/gl_helpers.hpp"

#define ARP_LOG_CONTEXT "App"

using namespace bf;

App::App(Window& window) : m_window(window)
{
    CHECK_STATE(!g_app, "App initialized twice");
    g_app = this;

    // Init imgui
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;
    (void) io;

    ImGui_ImplGlfw_InitForOpenGL(m_window.handle(), true);
    ImGui_ImplOpenGL3_Init("#version 460 core");

    // Apply UI style
    ui_apply_style();

    // Create visualization stream
    CHECK_CU(cudaStreamCreate(&g_stream));

    // Init renderers
    m_model_renderer = std::make_unique<ModelRenderer>();
    m_grid_renderer = std::make_unique<GridRenderer>();
    m_brick_renderer = std::make_unique<BrickRenderer>();
    m_brick_plane_renderer = std::make_unique<BrickPlaneRenderer>();

    // Init firebase
    setup_firebase();

    // Set initial screen: authentication
    m_screen = std::make_unique<AuthScreen>();

    // Start sync daemon
    m_sync_daemon = std::make_unique<SyncDaemon>();
    m_sync_daemon->start();
}

App::~App()
{
    m_sync_daemon.reset();

    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();

    ImGui::DestroyContext();
}

void App::setup_firebase()
{
    firebase::AppOptions app_options;
    app_options.set_api_key("AIzaSyBng97YujpJM-xtkbT4TgU5GHrGKNJpREY");
    app_options.set_project_id("legobuilder-257af");
    app_options.set_storage_bucket("legobuilder-257af.firebasestorage.app");
    app_options.set_messaging_sender_id("930461315909");
    app_options.set_app_id("1:930461315909:web:972ae535fa5dda50ab042c");
    m_firebase_app = firebase::App::Create(app_options);
    CHECK_STATE(m_firebase_app, "Failed to initialize Firebase app");
    m_firebase_auth = firebase::auth::Auth::GetAuth(m_firebase_app);
    CHECK_STATE(m_firebase_auth, "Failed to initialize Firebase auth");
}

void App::start()
{
    // Loop
    while (!m_window.should_close()) {
        m_window.begin_frame();

        // Update
        double now = glfwGetTime();
        if (m_last_frame_t > 0.0f) {
            m_dt = now - m_last_frame_t;
        }
        m_last_frame_t = now;

        if (m_screen) m_screen->update(m_dt);

        // Render
        glBindFramebuffer(GL_FRAMEBUFFER, 0);

        glm::ivec2 framebuffer_size = m_window.framebuffer_size();
        glViewport(0, 0, framebuffer_size.x, framebuffer_size.y);

        m_window.begin_frame();

        glClearColor(0., 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        if (m_screen) m_screen->render();

        // UI
        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplGlfw_NewFrame();

        ImGui::NewFrame();

        if (m_screen) m_screen->ui();

        ImGui::Render();
        ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());

        //
        m_window.end_frame();

        // Execute all queued jobs
        while (!m_job_queue.empty()) {
            std::function<void()> job = m_job_queue.pop();
            job();
        }
        m_job_queue_cond_var.notify_all(); // Notify arpenteur thread that the job queue is now empty
    }
}

void App::set_should_close() { m_window.set_should_close(true); }

void App::clear_jobs_queue()
{
    while (!m_job_queue.empty()) m_job_queue.pop();
}
