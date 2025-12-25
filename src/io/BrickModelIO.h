#pragma once

#include <filesystem>

#include <tiny_gltf.h>

#include "BrickModel.h"
#include "ConverterListener.h"
#include "model/Model.h"
#include "types.h"

namespace bf
{
class BrickModelIO
{
public:
    /* BFC */
    static std::unique_ptr<BrickModel> bfc_import(const std::filesystem::path& input_filepath);
    static void bfc_export(const BrickModel& brick_model, const std::filesystem::path& output_filepath);
    static void bbfc_export(const BrickModel& brick_model, const std::filesystem::path& output_filepath);

    /* LXF/LXFML */
    static void lxfml_export(const BrickModel& brick_model, const std::filesystem::path& output_filepath);
    static void lxf_export(const BrickModel& brick_model, const std::filesystem::path& output_filepath);

private:
    static tinygltf::Value bfc_serialize_metadata(const BrickModel& brick_model);
    static void bfc_deserialize_metadata(const tinygltf::Value& json, BrickModel& out_brick_model);

    explicit BrickModelIO() = default;
};
} // namespace bf
