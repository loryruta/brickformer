#pragma once

#include <cstdint>

#include "glm/glm.hpp"
#include <thrust/device_vector.h>

#include "DeviceImage.cuh"
#include "model/DeviceModel.h"

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
    int m_resolution;
    float m_alpha_test_threshold;

    const DeviceModel* m_model_d;
    thrust::device_vector<TriRef> m_triangles_d;

public:
    /// Initializes data structures; the model is uploaded to GPU and its meshes' triangles are linearized into one
    /// device-local triangle list. After the call, the model can be freed.
    explicit Slicer(const Model& model, int resolution, float alpha_test_threshold, cudaStream_t stream);
    ~Slicer() = default;

    void slice(uint32_t slice_y, SliceT& out_slice, cudaStream_t stream);

private:
    void linearize_triangles(const Model& model, cudaStream_t stream);
};
} // namespace lego_builder
