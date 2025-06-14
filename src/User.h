#pragma once

#include <string>
#include <memory>

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
    explicit User(const std::string& uid, const std::string& email) : m_uid(uid), m_email(email) {}

    [[nodiscard]] const std::string& uid() const { return m_uid; }
    [[nodiscard]] const std::string& email() const { return m_email; }
    [[nodiscard]] bool is_anonymous() const { return m_uid.empty(); }

    [[nodiscard]] PaidPlan& plan() const { return *m_paid_plan; };
};
} // namespace lego_builder
