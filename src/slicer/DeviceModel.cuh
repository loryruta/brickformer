#pragma once

#include <cstdint>

#include <glm/glm.hpp>

#include "Model.hpp"

namespace lego_builder
{
    struct DeviceMesh
    {
        const Vertex* m_vertices;
        const uint32_t* m_indices;

        int m_texture_idx;
    };

    struct DeviceModel
    {
        const cudaTextureObject_t* m_textures;
        const DeviceMesh* m_meshes;
    };

    const DeviceModel* upload_model(const Model& model);
}