#pragma once

#include <exception>
#include <string>
#include <utility>

#include <tinyformat.h>

namespace lego_builder
{
///
class CustomException : public std::exception
{
private:
    std::string m_error;

public:
    explicit CustomException(std::string error) : m_error(std::move(error)) {}

    const char* what() { return m_error.c_str(); }
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

class IllegalStateException : public CustomException
{
public:
    template <typename... ARGS>
    explicit IllegalStateException(const char* fmt, ARGS&&... args)
        : CustomException(tfm::format(fmt, std::forward<ARGS>(args)...))
    {
    }
};
} // namespace lego_builder
