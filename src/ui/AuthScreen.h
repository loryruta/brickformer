#pragma once

#include <optional>

#include <firebase/app.h>
#include <firebase/auth.h>
#include <imgui.h>

#include "Screen.h"

namespace lego_builder
{
class AuthScreen : public Screen
{
private:
    char m_email[1024]{};
    char m_password[1024]{};

    std::optional<firebase::Future<firebase::auth::AuthResult>> m_auth_result_future;
    std::string m_auth_error;

    ImFont* m_font;
    ImFont* m_title_font;

public:
    explicit AuthScreen();
    ~AuthScreen() = default;

    [[nodiscard]] const char* name() const override { return "AuthScreen"; }

    void resize(glm::ivec2 resolution) override {} ;
    void update(float dt) override;
    void render() override;
    void ui() override;

private:
    void on_sign_in();

    void ui_title_window();
    void ui_auth_form();
};
} // namespace lego_builder
