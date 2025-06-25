#include "UserWindow.h"

#include "User.h"
#include "ui/UIStyle.h"

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
    User user = User::get().copy();

    if (ui_window("User")) {
        if (user.is_anonymous()) {
            ImGui::Text("Anonymous User");
        } else {
            ImGui::Text("Email: %s", user.email().c_str());
        }
        ImGui::Text("Plan:  %s", user.plan()->name().c_str());

        uint64_t premium_plan_begin = user.premium_plan_begin();
        if (premium_plan_begin != UINT64_MAX) {
            ImGui::SeparatorText("Last purchase:");
            std::string plan_begin = unix_timestamp_to_readable_str(premium_plan_begin);
            std::string plan_end = unix_timestamp_to_readable_str(user.premium_plan_end());
            ImGui::Text("Start: %s", plan_begin.c_str());
            ImGui::Text("End:   %s", plan_end.c_str());
        }
    }
    ImGui::End();
}
