#pragma once

#include <cstdint>

#include "glm/glm.hpp"

#include "Model.h"

namespace bf
{
    struct DeviceMesh
    {
        const Vertex* m_vertices;
        const uint32_t* m_indices;

        glm::vec4 m_color;
        int m_texture_idx;
    };

    struct DeviceModel
    {
        const cudaTextureObject_t* m_textures;
        const DeviceMesh* m_meshes;
    };

    const DeviceModel* upload_model(const Model& model, cudaStream_t stream);
}