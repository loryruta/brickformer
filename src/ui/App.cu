#include "App.h"

#include <GLFW/glfw3.h>
#include <glad/gl.h>
#include <imgui.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>
#include <nfd.h>

#include "AuthScreen.h"
#include "MainScreen.h"
#include "brick_colors.hpp"
#include "bricks.hpp"
#include "log.hpp"
#include "model/GltfLoader.hpp"
#include "util/StopWatch.hpp"
#include "video/gl_helpers.hpp"

#define ARP_LOG_CONTEXT "App"

using namespace lego_builder;

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

    // Init renderers
    m_model_renderer = std::make_unique<ModelRenderer>();
    m_grid_renderer = std::make_unique<GridRenderer>();

    // Init firebase
    setup_firebase();

    // Set initial screen: authentication
    m_screen = std::make_unique<MainScreen>();
}

App::~App()
{
    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();

    ImGui::DestroyContext();
}

void App::setup_firebase()
{
    firebase::AppOptions app_options;
    m_firebase_app = firebase::App::Create(app_options);
    CHECK_STATE(m_firebase_app, "Failed to initialize Firebase app");
    m_firebase_auth = firebase::auth::Auth::GetAuth(m_firebase_app);
    CHECK_STATE(m_firebase_auth, "Failed to initialize Firebase auth");
}

std::optional<firebase::auth::User> App::auth_user() const
{
    firebase::auth::User user = m_firebase_auth->current_user();
    if (!user.is_valid()) return std::nullopt; // Not authenticated
    firebase::Future<std::string> auth_token = user.GetToken(true /* renew */);
    while (auth_token.status() == firebase::kFutureStatusPending)
        ;
    if (auth_token.status() != firebase::kFutureStatusComplete) return std::nullopt;
    return user;
}

void App::start()
{
    //    m_window.set_key_callback([&](int key, int scancode, int action, int mods) {
    //        bool is_autorun_pressed = key == GLFW_KEY_F1 && action == GLFW_PRESS;
    //
    //        if ((key == GLFW_KEY_ENTER && action == GLFW_PRESS) || is_autorun_pressed) {
    //            // Resume the Arpenteur thread (by default it stops after a slice is completed)
    //            m_arpenteur_should_run = true;
    //            m_arpenteur_should_run.notify_all();
    //        }
    //
    //        if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS) m_window.set_should_close(true); // Bye bye! :)
    //
    //        if (is_autorun_pressed) m_autorun = !m_autorun;
    //    });

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

void App::clear_jobs_queue()
{
    while (!m_job_queue.empty()) m_job_queue.pop();
}
