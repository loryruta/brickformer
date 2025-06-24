#pragma once

#include "model/Model.h"

namespace bf
{

class VoxelModelBuilder
{
private:
    Model m_model;
    Mesh* m_mesh;

public:
    explicit VoxelModelBuilder();
    ~VoxelModelBuilder() = default;

    [[nodiscard]] const Model& model() const { return m_model; }

    void set_voxel(int x, int y, int z, const glm::vec4& color);
};

}
