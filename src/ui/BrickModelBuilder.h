#pragma once

#include <atomic>

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
    /// A list of ranges [start, end] that denote the vertices of every subslice, bottom-up.
    /// Complete bricks are store along with subslice 0 bricks.
    std::vector<std::pair<uint32_t, uint32_t>> m_subslice_ranges;
    /// Counter used to differentiate placements for the outline guide.
    /// It's important to assign a unique ID to every placement (starting from 1).
    std::atomic<uint32_t> m_next_pid = 1;

public:
    explicit BrickModelBuilder();
    ~BrickModelBuilder() = default;

    [[nodiscard]] const Model& model() const { return m_model; }
    [[nodiscard]] const std::vector<std::pair<uint32_t, uint32_t>>& subslice_ranges() const
    {
        return m_subslice_ranges;
    }

    /// Procedurally generate vertices for multiple placements in parallel.
    void add_slice(int slice_y, const std::vector<Placement>& placements);

private:
    /// Procedurally generate vertices for the given placement's subslice.
    void add_placement(
        int slice_y, int subslice, uint32_t pid, const Placement& placement, std::vector<Vertex>& out_vertices);
    /// Procedurally generate vertices for the given placement.
    void add_placement(int slice_y, const Placement& placement, std::vector<Vertex>& out_vertices);
};
} // namespace lego_builder
