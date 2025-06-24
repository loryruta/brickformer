#pragma once

#include "DeviceImage.h"

namespace bf
{
/// Given an image with one channel, spreads pixel values to their 4-connected neighbors.
class SpreadValue
{
public:
    using DeviceImageT = DeviceImage<1, uint8_t>;

    explicit SpreadValue() = default;
    ~SpreadValue() = default;

    void spread(DeviceImageT& image, int num_iterations, cudaStream_t stream);
};
} // namespace bf
