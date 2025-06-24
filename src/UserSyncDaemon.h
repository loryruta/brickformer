#pragma once

#include <memory>
#include <thread>

#include "User.h"

namespace bf
{
/// A class wrapping a thread that periodically query user data from Firestore.
/// If this class fails in any manner (e.g. no internet), the user must be brought to login screen.
class UserSyncDaemon
{
private:
    User& m_user;

    std::unique_ptr<std::thread> m_thread;
    bool m_should_stop = false;

public:
    std::function<void(const std::string&)> user_auth_error;
    std::function<void(const std::string&)> user_document_retrieve_error;

    explicit UserSyncDaemon(User& user);
    ~UserSyncDaemon();

    void start();

private:
    void thread_start();
};
} // namespace bf
