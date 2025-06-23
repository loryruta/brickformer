#pragma once

#include <memory>
#include <string>

#include "PaidPlan.h"

namespace lego_builder
{
class User
{
private:
    std::string m_uid{};
    std::string m_email{};
    std::unique_ptr<PaidPlan> m_paid_plan; // Lazy initialized

public:
    /// Create an anonymous user (empty UID).
    explicit User() = default;
    /// Create a signed-in user with UID and email.
    explicit User(std::string uid, std::string email) : m_uid(std::move(uid)), m_email(std::move(email)) {}

    [[nodiscard]] const std::string& uid() const { return m_uid; }
    [[nodiscard]] const std::string& email() const { return m_email; }
    [[nodiscard]] bool is_anonymous() const { return m_uid.empty(); }

    [[nodiscard]] PaidPlan& plan() const { return *m_paid_plan; };
    void set_plan(std::unique_ptr<PaidPlan>&& plan) { m_paid_plan = std::move(plan); }

    static User& get();
};
} // namespace lego_builder
