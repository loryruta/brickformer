#include "AuthScreen.h"

#include <imgui.h>

#include "App.h"
#include "log.hpp"
#include "ui/MainScreen.h"

#define ARP_LOG_CONTEXT "AuthScreen"

using namespace lego_builder;

AuthScreen::AuthScreen()
{
    ImGuiIO& io = ImGui::GetIO();
    ImFontConfig config{};

    config.SizePixels = 13;
    config.OversampleH = config.OversampleV = 1;
    config.PixelSnapH = true;
    m_font = io.Fonts->AddFontDefault(&config);

    config.SizePixels = 50;
    config.OversampleH = config.OversampleV = 1;
    config.PixelSnapH = true;
    m_title_font = io.Fonts->AddFontDefault(&config);
}

void AuthScreen::update(float dt)
{
    if (m_auth_result_future) {
        if (m_auth_result_future->status() == firebase::kFutureStatusComplete) {
            int error = m_auth_result_future->error();
            const char* error_message = m_auth_result_future->error_message();
            if (error == firebase::auth::kAuthErrorNone) {
                m_auth_error.clear();
                ARP_INFO("Signed in");
                on_sign_in();
            } else {
                ARP_INFO("Sign in attempt failed (%d): %s", error, error_message);
                if (error == firebase::auth::kAuthErrorFailure) {
                    m_auth_error = "Invalid username or password";
                } else {
                    m_auth_error = error_message;
                }
            }
            m_auth_result_future.reset();
        } else if (m_auth_result_future->status() == firebase::kFutureStatusInvalid) {
            m_auth_result_future.reset();
        } else {
            // firebase::kFutureStatusPending
        }
    }
}

void AuthScreen::on_sign_in()
{
    const firebase::auth::AuthResult* auth_result = m_auth_result_future->result();
    // Nothing to do here, the current user is obtained through current_user() (in App)

    g_app->set_screen(std::make_shared<MainScreen>());
}

void AuthScreen::render()
{
    glClearColor(0, 0, 0, 0);
    glClear(GL_COLOR_BUFFER_BIT);
}

void AuthScreen::ui_title_window()
{
    ImGuiIO& io = ImGui::GetIO();
    ImGui::SetNextWindowPos(
        ImVec2(io.DisplaySize.x * 0.5f, io.DisplaySize.y * 0.25f), ImGuiCond_Always, ImVec2(0.5f, 0.5f));
    ImGui::SetNextWindowSize(ImVec2(0, 0)); // Fit content
    ImGuiWindowFlags flags = ImGuiWindowFlags_NoMove;
    flags |= ImGuiWindowFlags_NoCollapse;
    flags |= ImGuiWindowFlags_NoTitleBar;
    flags |= ImGuiWindowFlags_NoBackground;
    if (ImGui::Begin("###title_window", nullptr, flags)) {
        ImGui::PushFont(m_title_font);
        ImGui::Text("BrickFormer");
        ImGui::PopFont();
    }
    ImGui::End();
}

void AuthScreen::ui_auth_form()
{
    ImGuiIO& io = ImGui::GetIO();
    ImGui::PushFont(m_font);
    ImGui::SetNextWindowPos(
        ImVec2(io.DisplaySize.x * 0.5f, io.DisplaySize.y * 0.5f), ImGuiCond_Always, ImVec2(0.5f, 0.5f));
    ImGui::SetNextWindowSize(ImVec2(0, 0)); // Fit content
    ImGuiWindowFlags flags = ImGuiWindowFlags_NoMove;
    flags |= ImGuiWindowFlags_NoCollapse;
    flags |= ImGuiWindowFlags_NoTitleBar;

    if (ImGui::Begin("Sign In###login_form", nullptr, flags)) {
        ImVec2 window_size = ImGui::GetContentRegionAvail();
        ImGui::PushItemWidth(window_size.x);

        ImGui::Text("Email");
        ImGui::InputText("###email", m_email, sizeof(m_email));
        ImGui::Text("Password");
        ImGui::InputText("###password", m_password, sizeof(m_password), ImGuiInputTextFlags_Password);
        ImGui::Spacing();
        if (ImGui::Button("Sign In")) {
            ARP_DEBUG("Signing; Email: %s, Password: %s", m_email, m_password);
            m_auth_result_future = g_app->firebase_auth()->SignInWithEmailAndPassword(m_email, m_password);
        }
        // Sign in error
        if (!m_auth_error.empty()) {
            ImGui::TextColored(ImVec4(1, 0, 0, 1), "ERROR: %s", m_auth_error.c_str());
        } else {
            ImGui::Text(" "); // Just for spacing
        }
        // Not registered yet?
        ImGui::Text("Not registered yet?");
        ImGui::SameLine();
        ImGui::TextLinkOpenURL("Click here", "https://brickformer.io/signup");
        ImGui::SameLine();
        ImGui::Text("to sign up.");
        ImGui::PopItemWidth();
    }
    ImGui::End();
    ImGui::PopFont();
}

void AuthScreen::ui()
{
    ui_title_window();
    ui_auth_form();
}
