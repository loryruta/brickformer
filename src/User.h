#pragma once

#include <memory>
#include <mutex>
#include <string>

#include "PaidPlan.h"

namespace bf
{
class User
{
private:
    std::string m_uid{};
    std::string m_email{};
    PaidPlan* m_plan = nullptr;

    std::mutex m_mutex;

public:
    /// Create a signed-in user with UID and email.
    explicit User(std::string uid, std::string email);
    User(User&&) noexcept = default;

    /// Get UID. Non thread-safe.
    [[nodiscard]] std::string uid() const { return m_uid; }
    /// Get email. Non thread-safe.
    [[nodiscard]] std::string email() const { return m_email; }
    /// Get plan (e.g. free, premium). Non thread-safe.
    [[nodiscard]] const PaidPlan* plan() const { return m_plan ? m_plan : &s_plan_free; }

    void set_plan(PaidPlan* plan);
    void set_plan(const std::string& plan_name);

    /// Thread-safe copy of the user-data. Shall be used before accessing any user data for thread-safety.
    [[nodiscard]] User copy();

    static std::unique_ptr<User>& get();

    static void set(std::string uid, std::string email);
    static void unset();

private:
    User(const User&); // Copy constructor is private; call copy() instead
};
} // namespace bf
