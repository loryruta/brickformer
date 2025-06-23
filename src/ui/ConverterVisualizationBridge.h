#pragma once

#include <memory>
#include <vector>

#include "BrickModelBuilder.h"
#include "Converter.h"
#include "ConverterListener.h"
#include "video/BrickRenderer.h"
#include "video/ModelRenderer.hpp"
#include "video/VoxelModelBuilder.hpp"
#include "video/cuda_interop_helpers.cuh"

namespace lego_builder
{
// Forward decl
class MainScreen;

/// A class that serves to bridge the conversion with the visualization:
/// as an example, copies the proximity map to a GL-mapped texture which can be visualized.
class ConverterVisualizationBridge : public ConverterListener
{
private:
    MainScreen& m_parent;
    Converter& m_converter;

    std::unique_ptr<CUDAMappedGLTexture> m_color_map_texture;
    std::vector<CUDAMappedGLTexture> m_placement_map_hashed_color_textures;
    std::vector<CUDAMappedGLTexture> m_placement_map_color_textures;
    std::unique_ptr<CUDAMappedGLTexture> m_proximity_map_texture;

    std::shared_ptr<BrickModelBuilder> m_brick_model;

public:
    explicit ConverterVisualizationBridge(MainScreen& parent);
    ~ConverterVisualizationBridge() = default;

    [[nodiscard]] GLuint color_map_texture() const { return m_color_map_texture->texture(); }
    [[nodiscard]] GLuint placement_map_hashed_color_texture(int subslice) const
    {
        CHECK_ARG(subslice >= 0 && subslice < 3);
        return m_placement_map_hashed_color_textures.at(subslice).texture();
    }
    [[nodiscard]] GLuint placement_map_color_texture(int subslice) const
    {
        CHECK_ARG(subslice >= 0 && subslice < 3);
        return m_placement_map_color_textures.at(subslice).texture();
    }
    [[nodiscard]] GLuint proximity_map_texture() const { return m_proximity_map_texture->texture(); }

    [[nodiscard]] const std::shared_ptr<BrickModelBuilder>& brick_model() const { return m_brick_model; }

    void copy_color_map(cudaStream_t stream);
    void copy_placement_maps(cudaStream_t stream);
    void copy_proximity_map(cudaStream_t stream);
    /// Having the placements for the current slice, adds the vertices of them to create the 3d model of the
    /// construction (for visualization).
    void add_placements_to_construction_model(cudaStream_t stream);

    void on_model_load(const Model& model) override {}
    void on_placement_begin(uint32_t slice_y) override {}
    void on_place(uint32_t slice_y, const Placement& placement, float reward) override {}
    void on_placement_end(uint32_t slice_y, const std::vector<Placement>& placements) override;
};
} // namespace lego_builder
