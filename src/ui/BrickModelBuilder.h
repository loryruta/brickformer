#pragma once

#include <atomic>
#include <memory>

#include "model/Model.hpp"
#include "types.cuh"

namespace lego_builder
{
// Forward decl
class BrickRenderer_BakedModel;

/// Given several placements, procedurally generate a brick model.
class BrickModelBuilder
{
    friend class BrickModelIO;

private:
    /// A representative name for the brick model.
    std::string m_name;
    /// The model/mesh under construction.
    Model m_model;
    /// A pointer to the first and only mesh of the model.
    Mesh* m_mesh;
    /// A list of ranges [start, end] that denote the vertices of every subslice, bottom-up.
    /// Complete bricks are store along with subslice 0 bricks.
    std::vector<std::pair<uint32_t, uint32_t>> m_subslice_ranges;
    /// Counter used to differentiate placements for the outline guide.
    /// It's important to assign a unique ID to every placement (starting from 1).
    std::atomic<uint32_t> m_next_pid = 1;
    /// A map where the key is an encoding of brick ID and color ID, while the value is the quantity.
    std::unordered_map<uint32_t, uint32_t> m_brick_quantities;
    size_t m_total_brick_count = 0;

public:
    explicit BrickModelBuilder(std::string name);
    BrickModelBuilder(BrickModelBuilder&&) noexcept;
    ~BrickModelBuilder() = default;

    [[nodiscard]] const std::string& name() const { return m_name; }
    [[nodiscard]] const Model& model() const { return m_model; }
    [[nodiscard]] const Mesh& mesh() const { return *m_mesh; }
    [[nodiscard]] Mesh& mesh() { return *m_mesh; }
    [[nodiscard]] const auto& subslice_ranges() const { return m_subslice_ranges; }
    [[nodiscard]] const auto& brick_quantities() const { return m_brick_quantities; }

    [[nodiscard]] size_t bytesize() const;
    /// Return the total number of bricks (i.e. placements) that make up the model.
    [[nodiscard]] size_t total_brick_count() const { return m_total_brick_count; }

    /// Procedurally generate vertices for multiple placements in parallel.
    void add_slice(int slice_y, const std::vector<Placement>& placements);

private:
    explicit BrickModelBuilder();

    /// Procedurally generate vertices for the given placement's subslice.
    void add_placement(
        int slice_y, int subslice, uint32_t pid, const Placement& placement, std::vector<Vertex>& out_vertices);
    /// Procedurally generate vertices for the given placement.
    void add_placement(int slice_y, const Placement& placement, std::vector<Vertex>& out_vertices);
};
} // namespace lego_builder
