#pragma once

#include <string>

#include "exceptions.h"

namespace bf
{
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
} // namespace bf
