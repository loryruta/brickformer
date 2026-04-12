#include "User.h"

#include <random>

#include "PaidPlan.h"
#include "log.h"
#include "util/misc.h"

#define ARP_LOG_CONTEXT "User"

using namespace bf;

namespace
{
/// The authenticated user, if the user has not authenticated yet, then it is null.
std::unique_ptr<User> g_user;
} // namespace

User::User(std::string uid, std::string email) : m_uid(std::move(uid)), m_email(std::move(email))
{
    // Generate random secret
    std::random_device rd;
    std::mt19937_64 gen(rd());
    std::uniform_int_distribution<uint64_t> dist(0, std::numeric_limits<uint64_t>::max());

#ifndef BF_OPENSOURCE
    set_plan("free"); // Imperative: set the free plan at initialization
#else
    // For users who manage to build BrickFormer, we reward the lifetime Premium plan!
    set_plan("premium");
#endif
}

User::User(const User& other) : m_uid(other.m_uid), m_email(other.m_email), m_plan(other.m_plan) {}

void User::set_plan(PaidPlan* plan)
{
    CHECK_ARG(plan != nullptr);

    std::lock_guard<std::mutex> lock(m_mutex);
    m_plan = plan;
}

void User::set_plan(const std::string& plan_name)
{
    if (plan_name == "free") {
        set_plan(&s_plan_free);
    } else if (plan_name == "premium") {
        set_plan(&s_plan_premium);
    } else {
        throw IllegalArgumentException("Invalid plan: %s", plan_name);
    }
}

User User::copy()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    return *this;
}

std::unique_ptr<User>& User::get() { return g_user; }

void User::set(std::string uid, std::string email) { g_user = std::make_unique<User>(uid, email); }

void User::unset() { g_user.reset(); }
