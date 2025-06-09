#pragma once

#include "model/Model.hpp"
#include "types.cuh"

namespace lego_builder
{
/// Given several placements, procedurally generate a brick model.
class BrickModelBuilder
{
private:
    /// The brick model under construction.
    Model m_model;
    /// A pointer to the first and only mesh of the model.
    Mesh* m_mesh;

public:
    explicit BrickModelBuilder();
    ~BrickModelBuilder() = default;

    [[nodiscard]] const Model& model() const { return m_model; }

    /// Procedurally generate the vertices for the given placement.
    void add_placement(int slice_y, uint32_t pid, const Placement& placement);
};
} // namespace lego_builder
