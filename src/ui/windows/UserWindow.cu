#include "UserWindow.h"

#include "User.h"
#include "ui/UIStyle.h"
#include "util/exceptions.h"

using namespace bf;

namespace
{
std::string unix_timestamp_to_readable_str(int64_t timestamp)
{
    std::tm* utc_tm = std::gmtime(&timestamp);
    char buffer[100];
    std::strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S UTC", utc_tm);
    return buffer;
}
} // namespace

void UserWindow::ui()
{
    CHECK_ARG(User::get(), "User must be present when showing UserWindow");
    User user = User::get()->copy();

    if (ui_window("User")) {
        ImGui::Text("Email: %s", user.email().c_str());
        ImGui::Text("Plan:  %s", user.plan()->name().c_str());
    }
    ImGui::End();
}
