#pragma once

#include <cstdint>

#include "glm/glm.hpp"
#include <thrust/device_vector.h>

#include "DeviceImage.cuh"
#include "model/DeviceModel.cuh"

namespace lego_builder
{
struct TriRef
{
    glm::vec3 m_vertices[3];
    uint32_t m_triangle_idx;
    uint32_t m_mesh_idx;
};

using SliceT = DeviceImage<4, uint8_t>;

class Slicer
{
private:
    uint32_t m_slice_side;
    const DeviceModel* m_model_d;
    thrust::device_vector<TriRef> m_triangles_d;

public:
    /// Initializes data structures; the model is uploaded to GPU and its meshes' triangles are linearized into one
    /// device-local triangle list. After the call, the model can be freed.
    explicit Slicer(const Model& model, uint32_t slice_side);
    ~Slicer() = default;

    [[nodiscard]] uint32_t slice_side() const { return m_slice_side; }

    void slice(uint32_t slice_y, SliceT& out_slice);

private:
    void linearize_triangles(const Model& model);
};
} // namespace lego_builder
