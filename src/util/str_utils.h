#pragma once

#include <iomanip>
#include <sstream>
#include <string>

namespace bf
{
inline std::string num_bytes_to_string(std::size_t bytes)
{
    const char* suffixes[] = {"bytes", "Kb", "Mb", "Gb", "Tb", "Pb", "Eb", "Zb", "Yb"};
    double size = static_cast<double>(bytes);
    int order = 0;

    while (size >= 1024.0 && order < static_cast<int>(sizeof(suffixes) / sizeof(suffixes[0])) - 1) {
        size /= 1024.0;
        ++order;
    }

    std::ostringstream oss;
    oss << std::fixed << std::setprecision(2) << size << " " << suffixes[order];
    return oss.str();
}
} // namespace bf
