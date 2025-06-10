#pragma once

#include <string>

#define CHECK_STATE(condition, ...) lego_builder::check_state(!!(condition), #condition, __FILE__, __LINE__, nullptr)

#define CHECK_STATE_MSG(condition, message)                                                                            \
    lego_builder::check_state(condition, #condition, __FILE__, __LINE__, message)

#define CHECK_ARG(condition, ...) CHECK_STATE(condition)

namespace lego_builder
{

inline void check_state(bool condition, char const* check_str, char const* file, int line, char const* message)
{
    if (!condition) // TODO Mark as unlikely path
    {
        fprintf(stderr, "Invalid state: %s (file: %s, line: %d)", check_str, file, line);
        if (message) fprintf(stderr, "; %s", message);
        fprintf(stderr, "\n");
        exit(1);
    }
}

template <typename T>
std::string to_string(const T& element)
{
    return std::to_string(element);
}

template <typename ITERABLE>
std::string join(ITERABLE iterable, std::string separator = ", ")
{
    std::string result{};
    for (const std::string& str : iterable) {
        result += str + separator;
    }
    return result;
}


inline uint32_t uint32_to_float(float value)
{
    union {
        uint32_t u;
        float f;
    } union_;
    union_.f = value;
    return union_.u;
}

inline uint32_t uint32_to_float(uint32_t value)
{
    union {
        uint32_t u;
        float f;
    } union_;
    union_.f = value;
    return union_.u;
}

} // namespace lego_builder
