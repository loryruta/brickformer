#pragma once

#include <optional>

#include <firebase/app.h>
#include <firebase/auth.h>
#include <imgui.h>

#include "Screen.h"

#ifndef BF_OPENSOURCE // Sanity check
#error "This class shouldn't be provided in the opensource version"
#endif

namespace bf
{
class AuthScreen : public Screen
{
private:
    char m_email[1024]{};
    char m_password[1024]{};

    /// An external error to be displayed when opening the screen.
    std::string m_external_error = "";
    /// If the external error is severe, when the dialog is closed, the application will close.
    bool m_severe_error = false;

    std::optional<firebase::Future<firebase::auth::AuthResult>> m_auth_result_future;
    std::string m_auth_error;

public:
    explicit AuthScreen();
    explicit AuthScreen(std::string external_error, bool severe_error);
    ~AuthScreen() = default;

    [[nodiscard]] const char* name() const override { return "AuthScreen"; }

    void resize(glm::ivec2 resolution) override {};
    void update(float dt) override;
    void render() override;
    void ui() override;

private:
    void on_sign_in();

    void ui_title_window();
    void ui_auth_form();
};
} // namespace bf
