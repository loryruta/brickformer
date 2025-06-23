#pragma once

#include <filesystem>

#include <tiny_gltf.h>

#include "ConverterListener.h"
#include "model/Model.hpp"
#include "types.cuh"
#include "ui/BrickModelBuilder.h"

namespace lego_builder
{
class BrickModelIO
{
public:
    /* BFC */
    static std::unique_ptr<BrickModelBuilder> bfc_import(const std::filesystem::path& input_filepath);
    static void bfc_export(const BrickModelBuilder& brick_model, const std::filesystem::path& output_filepath);

    /* LXF/LXFML */
    static void lxfml_export(const BrickModelBuilder& brick_model, const std::filesystem::path& output_filepath);
    static void lxf_export(const BrickModelBuilder& brick_model, const std::filesystem::path& output_filepath);

private:
    static tinygltf::Value bfc_serialize_metadata(const BrickModelBuilder& brick_model);
    static void bfc_deserialize_metadata(const tinygltf::Value& json, BrickModelBuilder& out_brick_model);

    explicit BrickModelIO() = default;
};
} // namespace lego_builder
