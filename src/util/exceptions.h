#pragma once

#include <cstdarg>
#include <exception>
#include <string>
#include <utility>

#include <tinyformat.h>

#define CHECK_STATE(condition, ...) bf::check_state(!!(condition), #condition, __FILE__, __LINE__, ##__VA_ARGS__)

#define CHECK_ARG(condition, ...) bf::check_arg(!!(condition), #condition, __FILE__, __LINE__, ##__VA_ARGS__)

namespace bf
{
///
class CustomException : public std::exception
{
private:
    std::string m_error;

public:
    explicit CustomException(std::string error) : m_error(std::move(error)) {}

    [[nodiscard]] const char* what() const noexcept override { return m_error.c_str(); }
};

class IllegalStateException : public CustomException
{
public:
    template <typename... ARGS>
    explicit IllegalStateException(const char* fmt, ARGS&&... args)
        : CustomException(tfm::format(fmt, std::forward<ARGS>(args)...))
    {
    }
};

class IllegalArgumentException : public CustomException
{
public:
    template <typename... ARGS>
    explicit IllegalArgumentException(const char* fmt, ARGS&&... args)
        : CustomException(tfm::format(fmt, std::forward<ARGS>(args)...))
    {
    }
};

template <typename... ARGS>
void check_state(bool condition,
                 char const* condition_str,
                 char const* file,
                 int line,
                 const char* additional_message_fmt,
                 ARGS&&... args)
{
    if (!condition) [[unlikely]] {
        std::string fmt = "Illegal state \"%s\"";
#ifndef NDEBUG
        fmt += std::string(" (%s:%d)");
#endif
        if (additional_message_fmt) {
            fmt += std::string(":\n") + additional_message_fmt;
        }
#ifndef NDEBUG
        throw IllegalStateException(fmt.c_str(), condition_str, file, line, std::forward<ARGS>(args)...);
#else
        throw IllegalStateException(fmt.c_str(), condition_str, std::forward<ARGS>(args)...);
#endif
    }
}

template <typename... ARGS>
void check_arg(bool condition,
               char const* condition_str,
               char const* file,
               int line,
               const char* additional_message_fmt,
               ARGS&&... args)
{
    if (!condition) [[unlikely]] {
        std::string fmt = "Illegal argument \"%s\"";
#ifndef NDEBUG
        fmt += std::string(" (%s:%d)");
#endif
        if (additional_message_fmt) {
            fmt += std::string(":\n") + additional_message_fmt;
        }
#ifndef NDEBUG
        throw IllegalArgumentException(fmt.c_str(), condition_str, file, line, std::forward<ARGS>(args)...);
#else
        throw IllegalArgumentException(fmt.c_str(), condition_str, std::forward<ARGS>(args)...);
#endif
    }
}

inline void check_state(bool condition, char const* condition_str, char const* file, int line)
{
    check_state(condition, condition_str, file, line, nullptr);
}

inline void check_arg(bool condition, char const* condition_str, char const* file, int line)
{
    check_arg(condition, condition_str, file, line, nullptr);
}

} // namespace bf
