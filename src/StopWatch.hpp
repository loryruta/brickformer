#pragma once

#include <cstdint>
#include <chrono>

namespace lego_builder
{
    class StopWatch
    {
        using ClockT = std::chrono::system_clock;

    private:
        ClockT::time_point m_start;

    public:
        StopWatch() { reset(); };
        ~StopWatch() = default;

        void reset() { m_start = std::chrono::system_clock::now(); }

        ClockT::duration elapsed_time() { return std::chrono::system_clock::now() - m_start; }

        uint64_t elapsed_millis() { return std::chrono::duration_cast<std::chrono::milliseconds>(elapsed_time()).count(); }
        uint64_t elapsed_nanos() { return std::chrono::duration_cast<std::chrono::nanoseconds>(elapsed_time()).count(); }
    };
}
