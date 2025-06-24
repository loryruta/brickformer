#include "User.h"

#include <random>

#include "util/misc.hpp"

using namespace lego_builder;

namespace
{
/// The authenticated user, by default initialized as an anonymous user with free plan.
std::unique_ptr<User> g_user;
} // namespace

User::User() : User("", "") {}

User::User(std::string uid, std::string email) : m_uid(std::move(uid)), m_email(std::move(email))
{
    // Generate random secret
    std::random_device rd;
    std::mt19937_64 gen(rd());
    std::uniform_int_distribution<uint64_t> dist(0, std::numeric_limits<uint64_t>::max());
    m_secret = dist(gen);

    m_premium_plan_begin_cyphered = ~m_secret; // Set to UINT64_MAX
    m_premium_plan_end_cyphered = ~m_secret;   // Set to UINT64_MAX

    m_plan = &s_plan_free; // At initialization, use always the freeplan
}

User::User(const User& other)
    : m_uid(other.m_uid), m_email(other.m_email), m_premium_plan_begin_cyphered(other.m_premium_plan_begin_cyphered),
      m_premium_plan_end_cyphered(other.m_premium_plan_end_cyphered), m_secret(other.m_secret), m_plan(other.m_plan),
      m_last_synchronization_at(other.m_last_synchronization_at)
{
}

User User::copy()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    return *this;
}

void User::sync(const firebase::firestore::DocumentSnapshot& doc_snapshot)
{
    std::lock_guard<std::mutex> lock(m_mutex);

    auto doc_data = doc_snapshot.GetData();

    std::string user_id = doc_data["user_id"].string_value();
    std::string user_email = doc_data["user_email"].string_value();
    CHECK_STATE(m_uid == user_id, "Local user UID does not match with remote: %s (!= %s)", m_uid, user_id);
    CHECK_STATE(m_email == user_email, "Local user email does not match with remote: %s (!= %s)", m_email, user_email);
    if (doc_data.contains("last_purchase")) {
        auto last_purchase = doc_data["last_purchase"].map_value();
        m_premium_plan_begin_cyphered = last_purchase["start"].timestamp_value().seconds() ^ m_secret;
        m_premium_plan_end_cyphered = last_purchase["end"].timestamp_value().seconds() ^ m_secret;
    } else {
        m_premium_plan_begin_cyphered = ~m_secret; // UINT64_MAX
        m_premium_plan_end_cyphered = ~m_secret;   // UINT64_MAX
    }

    // Update the plan
    using namespace std::chrono;
    bool has_premium_plan = true;
    has_premium_plan &= m_premium_plan_end_cyphered != ~m_secret;
    int64_t now = duration_cast<seconds>(system_clock::now().time_since_epoch()).count();
    has_premium_plan &= now >= (m_premium_plan_begin_cyphered ^ m_secret);
    has_premium_plan &= now <= (m_premium_plan_end_cyphered ^ m_secret);
    m_plan = has_premium_plan ? (PaidPlan*) &s_plan_premium : (PaidPlan*) &s_plan_free;

    m_last_synchronization_at = now;
}

User& User::get()
{
    if (!g_user) set_anonymous();
    return *g_user;
}

void User::set(std::string uid, std::string email) { g_user = std::unique_ptr<User>(new User(uid, email)); }

void User::set_anonymous() { g_user = std::unique_ptr<User>(new User()); }
