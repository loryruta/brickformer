#pragma once

#include <memory>
#include <string>

#include <firebase/firestore.h>

#include "PaidPlan.h"

namespace bf
{
class User
{
    friend class UserSyncDaemon;

private:
    std::string m_uid{};
    std::string m_email{};
    uint64_t m_premium_license_expiration = 0;
    /// Secret used not to store the plan time ranges in plain (simple XOR cyphering).
    uint64_t m_secret = 0;
    PaidPlan* m_plan = nullptr;

    int64_t m_last_synchronization_at = 0;

    std::mutex m_mutex;

public:
    /// Create a signed-in user with UID and email.
    explicit User(std::string uid, std::string email);
    User(User&&) noexcept = default;

    [[nodiscard]] std::string uid() const { return m_uid; }
    [[nodiscard]] std::string email() const { return m_email; }

    [[nodiscard]] bool is_anonymous() const { return m_uid.empty() || m_email.empty(); }

    [[nodiscard]] uint64_t premium_license_expiration() const { return m_premium_license_expiration ^ m_secret; }

    [[nodiscard]] const PaidPlan* plan() const { return m_plan ? m_plan : &s_plan_free; }

    [[nodiscard]] int64_t last_synchronization_at() const { return m_last_synchronization_at; }

    /// Thread-safe copy of the user-data. Shall be used before accessing any user data for thread-safety.
    [[nodiscard]] User copy();

    static User& get();

    static void set(std::string uid, std::string email);
    static void set_anonymous();

private:
    /// Create an anonymous user (empty UID).
    explicit User();
    User(const User&); // Copy constructor is private; call copy() instead

    /// Sync the local user data with information retrieved from Firestore.
    void sync(const firebase::firestore::DocumentSnapshot& doc_snapshot);
    /// Update the synchronized at timestamp without doing anything else.
    void touch_sync();
};
} // namespace bf
