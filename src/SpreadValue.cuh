#pragma once

#include "DeviceImage.cuh"

namespace lego_builder
{
/// Given an image with one channel, spreads pixel values to their 4-connected neighbors, iteratively.
class SpreadValue
{
public:
    explicit SpreadValue() = default;
    ~SpreadValue() = default;

    void spread(DeviceImage<1, uint8_t>& image);
};
} // namespace lego_builder
