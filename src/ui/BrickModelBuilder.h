#pragma once

#include "model/Model.hpp"

namespace lego_builder
{
class BrickModelBuilder  // TODO Rename to BrickConstructionBuilder ?
{
private:
    Model m_model;
    Mesh* m_mesh;  // A pointer to the first and only mesh of the model

public:
    explicit BrickModelBuilder();
    ~BrickModelBuilder() = default;

    [[nodiscard]] const Model& model() const { return m_model; }

    void place(int slice_y, int x, int z, int bid, uint8_t subslice_mask, const glm::vec4& color);

private:
    void place_1x1(int slice_y, int x, int z, uint8_t subslice_mask, const glm::vec4& color);
};
}
