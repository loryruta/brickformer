#pragma once

#include "Arpenteur.cuh"
#include "ArpenteurListener.hpp"
#include "model/Model.hpp"
#include "types.cuh"

namespace lego_builder
{
class OutputToGltf : public ArpenteurListener
{
private:
    const Arpenteur& m_arpenteur;

    std::vector<Vertex> m_vertices;
    std::vector<uint32_t> m_indices;

    glm::vec3 m_min_position;
    glm::vec3 m_max_position;

public:
    explicit OutputToGltf(const Arpenteur& arpenteur);
    ~OutputToGltf() = default;

    void complete(const std::filesystem::path& output_dir);

protected:
    void on_placement_end(uint32_t slice_y) override;

private:
    void set_brick_1x1(int x, int y, int z, int subslice_mask, const glm::vec<4, uint8_t>& color);
};
} // namespace lego_builder
