#include "User.h"

#include <random>

#include "log.h"
#include "util/misc.h"

#define ARP_LOG_CONTEXT "User"

using namespace bf;

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

    m_premium_license_expiration = m_secret; // If XOR-ed with m_secret is 0

    m_plan = &s_plan_free; // Imperative: set the free plan at initialization
}

User::User(const User& other)
    : m_uid(other.m_uid), m_email(other.m_email), m_premium_license_expiration(other.m_premium_license_expiration),
      m_secret(other.m_secret), m_plan(other.m_plan), m_last_synchronization_at(other.m_last_synchronization_at)
{
}

User User::copy()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    return *this;
}

void User::sync(const firebase::firestore::DocumentSnapshot& doc_snapshot)
{
    CHECK_ARG(doc_snapshot.exists());

    std::lock_guard<std::mutex> lock(m_mutex);

    auto doc_data = doc_snapshot.GetData();
    std::string user_id = doc_data["user_id"].string_value();
    std::string user_email = doc_data["user_email"].string_value();
    CHECK_STATE(m_uid == user_id, "Local user UID does not match with remote: %s (!= %s)", m_uid, user_id);
    CHECK_STATE(m_email == user_email, "Local user email does not match with remote: %s (!= %s)", m_email, user_email);
    int64_t premium_license_expiration = doc_data["premium_license_expiration"].timestamp_value().seconds();

    using namespace std::chrono;

    int64_t now = duration_cast<seconds>(system_clock::now().time_since_epoch()).count();

    // Verify if we can provide the user the premium license
    bool has_premium_license = false;
    do {
        const int64_t k_premium_license_expiration_margin = 5 * 30 * 24 * 60 * 60;
        if ((premium_license_expiration - now) < 0) { // Expired
            break;
        }
        // Expiration is too far, something's off
        if ((premium_license_expiration - now) > k_premium_license_expiration_margin) {
            ARP_WARN("Premium license expiration is too far in the future: %lld (now: %lld)",
                     premium_license_expiration,
                     now);
            break;
        }
        has_premium_license = true;
    } while (false);

    m_premium_license_expiration =
        premium_license_expiration ^ m_secret; // Cyphered to avoid storing it in plain text in memory
    m_plan = has_premium_license ? (PaidPlan*) &s_plan_premium : (PaidPlan*) &s_plan_free;

    touch_sync();
}

void User::touch_sync()
{
    using namespace std::chrono;
    m_last_synchronization_at = duration_cast<seconds>(system_clock::now().time_since_epoch()).count();
}

User& User::get()
{
    if (!g_user) {
        set_anonymous();
    }
    return *g_user;
}

void User::set(std::string uid, std::string email) { g_user = std::unique_ptr<User>(new User(uid, email)); }

void User::set_anonymous() { g_user = std::unique_ptr<User>(new User()); }
