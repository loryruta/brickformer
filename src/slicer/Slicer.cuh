#pragma once

#include <cstdint>

#include "DeviceModel.cuh"
#include "BuildBvh.cuh"
#include "../DeviceImage.cuh"

namespace lego_builder
{
    class Slicer
    {
    private:
        uint32_t m_slice_side;

        const Bvh* m_device_bvh;
        const DeviceModel* m_device_model;

        uint32_t m_num_slices;
        glm::mat4 m_transform;

    public:
        explicit Slicer(const Bvh* d_bvh,
                        const DeviceModel* d_model,
                        const glm::vec3& model_min,
                        const glm::vec3& model_max,
                        uint32_t slice_side
                        );
        ~Slicer() = default;

        [[nodiscard]] uint32_t num_slices() const { return m_num_slices; }

        void slice(uint32_t slice_y, DeviceImage<4, uint8_t>* out_d_slice);
    };
}
