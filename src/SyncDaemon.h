#pragma once

#include <memory>
#include <thread>

#include "util/StopWatch.h"

namespace bf
{
/// A class that syncs the BrickFormer version and user data with the backend.
class SyncDaemon
{
private:
    std::unique_ptr<std::thread> m_thread;
    bool m_should_stop = false;

public:
    /// As soon as the user signs in, we want to instantly check (and show) its real plan.
    std::atomic<bool> force_plan_check = false;

    explicit SyncDaemon();
    ~SyncDaemon();

    void start();

private:
    void thread_start();
};
} // namespace bf
