#include "AuthScreen.h"

#include <imgui.h>

#include <utility>

#include "App.h"
#include "UIStyle.h"
#include "User.h"
#include "log.h"
#include "ui/MainScreen.h"

#define ARP_LOG_CONTEXT "AuthScreen"

using namespace bf;

AuthScreen::AuthScreen() {}

AuthScreen::AuthScreen(std::string external_error, bool severe_error)
    : m_external_error(std::move(external_error)), m_severe_error(severe_error)
{
}

void AuthScreen::update(float dt)
{
    if (m_auth_result_future) {
        if (m_auth_result_future->status() == firebase::kFutureStatusComplete) {
            int error = m_auth_result_future->error();
            if (error == firebase::auth::kAuthErrorNone) {
                m_auth_error.clear();
                ARP_INFO("Signed in");
                on_sign_in();
            } else {
                const char* error_message = m_auth_result_future->error_message();
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
    if (m_auth_result_future) {
        const firebase::auth::AuthResult* auth_result = m_auth_result_future->result();

        std::string uid = auth_result->user.uid();
        std::string email = auth_result->user.email();

        User::set(uid, email);

        g_app->enqueue_job([&/* &g_app */]() { g_app->set_screen(std::make_shared<MainScreen>()); });
    }
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
        ImGui::PushFont(g_title_font);
        ImGui::PushStyleColor(ImGuiCol_Text, MAIN_COLOR);
        ImGui::Text("BrickFormer");
        ImGui::PopStyleColor();
        ImGui::PopFont();
    }
    ImGui::End();
}

void AuthScreen::ui_auth_form()
{
    ImGuiIO& io = ImGui::GetIO();
    ImGui::PushFont(g_font);
    ImGui::SetNextWindowPos(
        ImVec2(io.DisplaySize.x * 0.5f, io.DisplaySize.y * 0.5f), ImGuiCond_Always, ImVec2(0.5f, 0.5f));
    ImGui::SetNextWindowSize(ImVec2(0, 0)); // Fit content
    ImGuiWindowFlags flags = ImGuiWindowFlags_NoMove;
    flags |= ImGuiWindowFlags_NoCollapse;
    flags |= ImGuiWindowFlags_NoTitleBar;

    if (ImGui::Begin("Sign In###login_form", nullptr, flags)) {
        ImVec2 content_region = ImGui::GetContentRegionAvail();
        ImGui::PushItemWidth(content_region.x);

        ImGui::Text("Email");
        ImGui::InputText("###email", m_email, sizeof(m_email));
        ImGui::Text("Password");
        ImGui::InputText("###password", m_password, sizeof(m_password), ImGuiInputTextFlags_Password);

        ImGui::Spacing();

        if (ui_primary_button("Sign In", ImVec2(content_region.x, 40.0f))) {
            ARP_DEBUG("Signing; Email: %s, Password: %s", m_email, m_password);
            m_auth_result_future = g_app->firebase_auth()->SignInWithEmailAndPassword(m_email, m_password);
        }

        /*
        if (ui_button("Sign In Anonymously", ImVec2(content_region.x, 25.0f))) {
            m_auth_result_future = std::nullopt;
            g_app->enqueue_job([this]() { on_sign_in(); });
        }*/

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

    // TODO this should be more general and not be restricted to the AuthScreen.
    //   Maybe put this logic in App?
    if (!m_external_error.empty()) {
        ImGui::OpenPopup(":(##AuthScreen_ExternalErrorModal");

        ImGuiIO& io = ImGui::GetIO();
        ImGui::SetNextWindowPos(
            ImVec2(io.DisplaySize.x * 0.5f, io.DisplaySize.y * 0.5f), ImGuiCond_Always, ImVec2(0.5f, 0.5f));
        ImGui::SetNextWindowSize(ImVec2(0, 0)); // Fit content

        bool opened = true;
        if (ui_popup_modal(":(##AuthScreen_ExternalErrorModal", &opened)) {
            ImVec2 content_window = ImGui::GetContentRegionAvail();

            ui_text_danger("%s", m_external_error.c_str());

            ImGui::Spacing();
            ImGui::Spacing();
            ImGui::Spacing();

            if (ui_button("Close", ImVec2(content_window.x, 0))) opened = false;

            ImGui::EndPopup();
        }
        if (!opened) {
            m_external_error.clear();
            if (m_severe_error) g_app->set_should_close();
        }
    }
}
