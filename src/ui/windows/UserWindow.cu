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

        int64_t premium_license_expiration = user.premium_license_expiration();
        ImGui::Text("Premium Plan Expiration:\n%s", premium_license_expiration > 0 ?
                        unix_timestamp_to_readable_str(premium_license_expiration).c_str() : "-");
        int64_t synchronized_at = user.last_synchronization_at();
        ImGui::Text("Synchronized at:\n%s", synchronized_at > 0 ?
                    unix_timestamp_to_readable_str(synchronized_at).c_str() : "-");
    }
    ImGui::End();
}
