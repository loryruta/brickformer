#include "User.h"

using namespace lego_builder;

namespace
{
/// The authenticated user, by default initialized as an anonymous user with free plan.
std::unique_ptr<User> g_user = [] {
    auto user = std::make_unique<User>();
    auto plan = std::make_unique<FreePlan>();
    user->set_plan(std::move(plan));
    return user;
}();
} // namespace

User& User::get() { return *g_user; }
