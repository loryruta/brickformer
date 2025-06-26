#include "BrickModelIO.h"

#include <fstream>
#include <numeric>

#include <pugixml.hpp>
#include <stb_image_write.h>
#include <tiny_gltf.h>
#include <zipper/zipper.h>

#include "bricks.h"
#include "lego_dataset.h"
#include "log.h"
#include "util/exceptions.h"

#define BFC_CHECK_FORMAT(cond_)                                                                                        \
    if (!(cond_)) {                                                                                                    \
        throw IllegalStateException("BFC file is malformed: %s", #cond_);                                              \
    }

#define ARP_LOG_CONTEXT "BrickModelIO"

using namespace bf;

namespace
{
std::string current_datetime_str()
{
    auto now = std::chrono::system_clock::now();
    std::time_t now_c = std::chrono::system_clock::to_time_t(now);
    std::ostringstream oss;
    oss << std::put_time(std::localtime(&now_c), "%Y-%m-%d %H:%M:%S");
    return oss.str();
}
} // namespace

tinygltf::Value BrickModelIO::bfc_serialize_metadata(const BrickModel& brick_model)
{
    using tinygltf::Value;

    Value::Object json_ = Value::Object();

    json_["name"] = Value(brick_model.name());
    json_["description"] = Value("BrickFormer Conversion");
    json_["version"] = Value(BF_GIT_VERSION);
    json_["version_full"] = Value(BF_GIT_VERSION_FULL);
    json_["commit_hash"] = Value(BF_GIT_COMMIT_HASH);
    json_["commit_timestamp"] = Value(BF_GIT_COMMIT_TIMESTAMP);
    json_["created_at"] = Value(current_datetime_str());

    // Serialize subslice ranges
    {
        const auto& subslice_ranges = brick_model.subslice_ranges();
        Value::Array subslice_ranges_json = Value::Array();
        for (const std::pair<uint32_t, uint32_t>& entry : subslice_ranges) {
            int start_vertex = entry.first;
            int end_vertex = entry.second;
            subslice_ranges_json.emplace_back(Value::Array({Value(start_vertex), Value(end_vertex)}));
        }
        json_["subslice_ranges"] = Value(subslice_ranges_json);
    }

    // Serialize brick quantities
    {
        const auto& brick_quantities = brick_model.brick_quantities();
        Value::Array brick_quantities_json = Value::Array();
        for (const auto& [key, quantity] : brick_quantities) {
            int bid = (key >> 16) & 0xFFFF;
            int cid = key & 0xFFFF;
            int quantity_ = quantity;
            Value::Object entry = Value::Object();
            entry["bid"] = Value(bid);
            entry["cid"] = Value(cid);
            entry["quantity"] = Value(quantity_);
            brick_quantities_json.emplace_back(entry);
        }
        json_["brick_quantities"] = Value(brick_quantities_json);
    }

    return Value(json_);
}

void BrickModelIO::bfc_deserialize_metadata(const tinygltf::Value& json, BrickModel& out_brick_model)
{
    using tinygltf::Value;

    BFC_CHECK_FORMAT(json.IsObject());

    std::string name = json.Get("name").Get<std::string>();
    out_brick_model.m_name = name;

    std::string description = json.Get("description").Get<std::string>();
    std::string version = json.Get("version").Get<std::string>();
    std::string version_full = json.Get("version_full").Get<std::string>();
    std::string commit_hash = json.Get("commit_hash").Get<std::string>();
    std::string commit_timestamp = json.Get("commit_timestamp").Get<std::string>();
    std::string created_at = json.Get("created_at").Get<std::string>();
    ARP_INFO("BFC model metadata:\n"
             "  Name:             %s\n"
             "  Description:      %s\n"
             "  Version:          %s\n"
             "  Version full:     %s\n"
             "  Commit hash:      %s\n"
             "  Commit timestamp: %s\n"
             "  Created at:       %s",
             name,
             description,
             version,
             version_full,
             commit_hash,
             commit_timestamp,
             created_at);

    // Parse subslice ranges
    {
        Value::Array subslice_ranges_json = json.Get("subslice_ranges").Get<Value::Array>();
        size_t num_subslice_ranges = subslice_ranges_json.size();
        std::vector<std::pair<uint32_t, uint32_t>> subslice_ranges;
        subslice_ranges.reserve(num_subslice_ranges);
        for (int i = 0; i < num_subslice_ranges; ++i) {
            const Value::Array& entry = subslice_ranges_json.at(i).Get<Value::Array>();
            uint32_t start_vertex = entry.at(0).Get<int>();
            uint32_t end_vertex = entry.at(1).Get<int>();
            subslice_ranges.emplace_back(start_vertex, end_vertex);
        }
        out_brick_model.m_subslice_ranges = std::move(subslice_ranges);
    }

    // Parse brick quantities
    {
        Value::Array brick_quantities_json = json.Get("brick_quantities").Get<Value::Array>();
        size_t num_brick_quantities = brick_quantities_json.size();
        std::unordered_map<uint32_t, uint32_t> brick_quantities;
        brick_quantities.reserve(num_brick_quantities);
        for (int i = 0; i < num_brick_quantities; ++i) {
            const Value::Object& entry = brick_quantities_json.at(i).Get<Value::Object>();
            uint32_t bid = entry.at("bid").Get<int>();
            uint32_t cid = entry.at("cid").Get<int>();
            uint32_t quantity = entry.at("quantity").Get<int>();
            uint32_t key = ((bid & 0xFFFF) << 16) | (cid & 0xFFFF);
            brick_quantities[key] = quantity;
        }
        out_brick_model.m_brick_quantities = std::move(brick_quantities);
    }
}

void BrickModelIO::bfc_export(const BrickModel& brick_model, const std::filesystem::path& output_filepath)
{
    // .bfc extension (BrickFormer Conversion) is a .glb file with custom content
    CHECK_ARG(output_filepath.extension() == ".bfc", "Output file extension must be .bfc");

    const Mesh& mesh = brick_model.model().m_meshes.at(0);

    const std::vector<Vertex>& vertices = mesh.vertices;

    tinygltf::Model model{};

    /* Vertex Buffer */
    tinygltf::Buffer& vertex_buffer = model.buffers.emplace_back();
    vertex_buffer.name = "Vertex Buffer";
    vertex_buffer.data.resize(vertices.size() * sizeof(Vertex));
    std::memcpy(vertex_buffer.data.data(), vertices.data(), vertices.size() * sizeof(Vertex));
    ARP_INFO("Vertex buffer; Size: %zu", vertex_buffer.data.size());

    CHECK_ARG(mesh.indices.empty(), "Index Buffer for Brick Model is expected to be empty");

    /* Position attribute */
    tinygltf::BufferView& position_buffer_view = model.bufferViews.emplace_back();
    position_buffer_view.name = "Position buffer view";
    position_buffer_view.buffer = 0;
    position_buffer_view.byteOffset = offsetof(Vertex, position);
    position_buffer_view.byteLength = vertices.size() * sizeof(Vertex);
    position_buffer_view.byteStride = sizeof(Vertex);
    position_buffer_view.target = TINYGLTF_TARGET_ARRAY_BUFFER;
    ARP_INFO("Position buffer view; Byte offset: %zu, Byte length: %zu, Byte stride: %zu",
             position_buffer_view.byteOffset,
             position_buffer_view.byteLength,
             position_buffer_view.byteStride);
    tinygltf::Accessor& position_accessor = model.accessors.emplace_back();
    position_accessor.bufferView = 0;
    position_accessor.name = "Position accessor";
    position_accessor.byteOffset = 0;
    position_accessor.componentType = TINYGLTF_COMPONENT_TYPE_FLOAT;
    position_accessor.count = vertices.size();
    position_accessor.type = TINYGLTF_TYPE_VEC3;
    position_accessor.minValues = {mesh.m_min[0], mesh.m_min[1], mesh.m_min[2]};
    position_accessor.maxValues = {mesh.m_max[0], mesh.m_max[1], mesh.m_max[2]};

    /* Normal attribute */
    tinygltf::BufferView& normal_buffer_view = model.bufferViews.emplace_back();
    normal_buffer_view.name = "Normal buffer view";
    normal_buffer_view.buffer = 0;
    normal_buffer_view.byteOffset = offsetof(Vertex, normal);
    normal_buffer_view.byteLength = vertices.size() * sizeof(Vertex) - normal_buffer_view.byteOffset;
    normal_buffer_view.byteStride = sizeof(Vertex);
    normal_buffer_view.target = TINYGLTF_TARGET_ARRAY_BUFFER;
    ARP_INFO("Normal buffer view; Byte offset: %zu, Byte length: %zu, Byte stride: %zu",
             normal_buffer_view.byteOffset,
             normal_buffer_view.byteLength,
             normal_buffer_view.byteStride);
    tinygltf::Accessor& normal_accessor = model.accessors.emplace_back();
    normal_accessor.bufferView = 1;
    normal_accessor.name = "Normal accessor";
    normal_accessor.byteOffset = 0;
    normal_accessor.componentType = TINYGLTF_COMPONENT_TYPE_FLOAT;
    normal_accessor.count = vertices.size();
    normal_accessor.type = TINYGLTF_TYPE_VEC3;

    /* Color attribute */
    tinygltf::BufferView& color_buffer_view = model.bufferViews.emplace_back();
    color_buffer_view.name = "Color buffer view";
    color_buffer_view.buffer = 0;
    color_buffer_view.byteOffset = offsetof(Vertex, color);
    color_buffer_view.byteLength = vertices.size() * sizeof(Vertex) - color_buffer_view.byteOffset;
    color_buffer_view.byteStride = sizeof(Vertex);
    color_buffer_view.target = TINYGLTF_TARGET_ARRAY_BUFFER;
    ARP_INFO("Color buffer view; Byte offset: %zu, Byte length: %zu, Byte stride: %zu",
             color_buffer_view.byteOffset,
             color_buffer_view.byteLength,
             color_buffer_view.byteStride);
    tinygltf::Accessor& color_accessor = model.accessors.emplace_back();
    color_accessor.bufferView = 3;
    color_accessor.name = "Color accessor";
    color_accessor.byteOffset = 0;
    color_accessor.componentType = TINYGLTF_COMPONENT_TYPE_FLOAT;
    color_accessor.count = vertices.size();
    color_accessor.type = TINYGLTF_TYPE_VEC4;

    /* Outline Guide attribute */
    tinygltf::BufferView& outline_guide_buffer_view = model.bufferViews.emplace_back();
    outline_guide_buffer_view.name = "Outline Guide buffer view";
    outline_guide_buffer_view.buffer = 0;
    outline_guide_buffer_view.byteOffset = offsetof(Vertex, p2 /* p2 is outline guide */);
    outline_guide_buffer_view.byteLength = vertices.size() * sizeof(Vertex) - outline_guide_buffer_view.byteOffset;
    outline_guide_buffer_view.byteStride = sizeof(Vertex);
    outline_guide_buffer_view.target = TINYGLTF_TARGET_ARRAY_BUFFER;
    ARP_INFO("Outline Guide buffer view; Byte offset: %zu, Byte length: %zu, Byte stride: %zu",
             outline_guide_buffer_view.byteOffset,
             outline_guide_buffer_view.byteLength,
             outline_guide_buffer_view.byteStride);
    tinygltf::Accessor& outline_guide_accessor = model.accessors.emplace_back();
    outline_guide_accessor.bufferView = 3;
    outline_guide_accessor.name = "Outline Guide accessor";
    outline_guide_accessor.byteOffset = 0;
    outline_guide_accessor.componentType = TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT;
    outline_guide_accessor.count = vertices.size();
    outline_guide_accessor.type = TINYGLTF_TYPE_VEC2;

    /* Primitive */
    tinygltf::Primitive primitive{};
    primitive.attributes.emplace("POSITION", 0);
    primitive.attributes.emplace("NORMAL", 1);
    // primitive.attributes.emplace("TEXCOORD_0", 2);
    primitive.attributes.emplace("COLOR_0", 2);
    // Application -specific attribute:
    // https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#meshes-overview
    primitive.attributes.emplace("_OUTLINE_GUIDE", 3);
    primitive.material = -1;
    primitive.indices = -1;
    primitive.mode = TINYGLTF_MODE_TRIANGLES;

    /* Mesh */
    tinygltf::Mesh& gltf_mesh = model.meshes.emplace_back();
    gltf_mesh.primitives.push_back(primitive);

    /* Node */
    tinygltf::Node& node = model.nodes.emplace_back();
    node.mesh = 0;

    /* Scene */
    tinygltf::Scene& scene = model.scenes.emplace_back();
    scene.nodes.push_back(0);

    model.extras = bfc_serialize_metadata(brick_model);

    tinygltf::TinyGLTF writer{};
    writer.SetStoreOriginalJSONForExtrasAndExtensions(true);
    bool result = writer.WriteGltfSceneToFile(&model, output_filepath, true, true, false, true /* writeBinary */);
    CHECK_STATE(result, "Failed to write .bfc file: %s", output_filepath.string());
}

std::unique_ptr<BrickModel> BrickModelIO::bfc_import(const std::filesystem::path& input_filepath)
{
    CHECK_ARG(input_filepath.extension() == ".bfc", "Input file extension must be .bfc");

    tinygltf::Model model{};
    tinygltf::TinyGLTF loader{};
    std::string error;
    std::string warning;
    bool ret = loader.LoadBinaryFromFile(&model, &error, &warning, input_filepath.string());
    if (!ret || !error.empty()) {
        throw std::runtime_error(error.empty() ? error : ".bfc import failed with a generic error");
    }
    if (!warning.empty()) {
        ARP_WARN("glTF import warning: %s", warning.c_str());
    }
    BFC_CHECK_FORMAT(model.scenes.size() == 1);
    BFC_CHECK_FORMAT(model.buffers.size() == 1);
    BFC_CHECK_FORMAT(model.bufferViews.size() == 4);
    BFC_CHECK_FORMAT(model.accessors.size() == 4);
    BFC_CHECK_FORMAT(model.meshes.size() == 1);
    tinygltf::Mesh& gltf_mesh = model.meshes.at(0);
    BFC_CHECK_FORMAT(gltf_mesh.primitives.size() == 1);
    tinygltf::Primitive& primitive = gltf_mesh.primitives.at(0);
    BFC_CHECK_FORMAT(primitive.mode == TINYGLTF_MODE_TRIANGLES);
    BFC_CHECK_FORMAT(primitive.attributes.contains("POSITION"));
    BFC_CHECK_FORMAT(primitive.attributes.contains("NORMAL"));
    BFC_CHECK_FORMAT(primitive.attributes.contains("COLOR_0"));
    BFC_CHECK_FORMAT(primitive.attributes.contains("_OUTLINE_GUIDE"));

    const tinygltf::Buffer& buffer = model.buffers.at(0);
    BFC_CHECK_FORMAT(buffer.data.size() % sizeof(Vertex) == 0);
    size_t num_vertices = buffer.data.size() / sizeof(Vertex);
    std::vector<Vertex> vertices(num_vertices);
    std::memcpy(vertices.data(), buffer.data.data(), buffer.data.size());

    glm::vec3 min_, max_;
    const tinygltf::Accessor position_accessor = model.accessors.at(0 /* Position */);
    min_ = {position_accessor.minValues[0], position_accessor.minValues[1], position_accessor.minValues[2]};
    max_ = {position_accessor.maxValues[0], position_accessor.maxValues[1], position_accessor.maxValues[2]};

    BrickModel brick_model;
    bfc_deserialize_metadata(model.extras, brick_model);
    brick_model.m_model.m_min = min_;
    brick_model.m_model.m_max = max_;
    Mesh& mesh = brick_model.mesh();
    brick_model.m_mesh = &mesh;
    mesh.vertices = std::move(vertices);
    mesh.indices = {}; // No indices for Brick Model
    mesh.m_min = min_;
    mesh.m_max = max_;
    return std::make_unique<BrickModel>(std::move(brick_model));
}

/*
    Example LXFML file:

    <LXFML versionMajor="5" versionMinor="0" name="UntitledModel">
    <Meta>
      <Application name="LDraw Converter" versionMajor="2.25.5" versionMinor="1" />
    </Meta>
    <Cameras>
      <Camera refID="0" orthographic="False" fieldOfView="15" distance="32"
    transformation="1,-1.776357E-15,8.742279E-08,5.631931E-08,0.7648422,-0.6442177,-6.686463E-08,0.6442177,0.7648422,-2.139668E-06,20.61497,24.47495"
    />
    </Cameras>
    <Bricks cameraRef="0">
      <Brick refID="0" designID="3005" itemNos="300523">
        <Part refID="0" designID="3005" partType="rigid" materials="23,0">
          <Bone refID="0" transformation="1,0,0,0,1,0,0,0,1,-1.2,0,1.2" />
        </Part>
      </Brick>
      <Brick refID="1" designID="3004" itemNos="6022083">
        <Part refID="1" designID="3004" partType="rigid" materials="226,0">
          <Bone refID="1" transformation="1,0,0,0,1,0,0,0,1,0.3999999,0,2.8" />
        </Part>
      </Brick>
    </Bricks>
    <GroupSystems>
      <BrickGroupSystem isHierarchical="true" isUnique="true">
        <Group refID="1" transformation="1,0,0,0,1,0,0,0,1,0,0,0" pivot="0,0,0" brickRefs="0,1" />
      </BrickGroupSystem>
    </GroupSystems>
    <BuildingInstruction>
      <Steps rotation="0,-90,0">
        <Step refID="0" cameraType="standard">
          <In brickRef="0" />
          <In brickRef="1" />
        </Step>
      </Steps>
    </BuildingInstruction>
    </LXFML>
 */

void BrickModelIO::lxfml_export(const BrickModel& brick_model, const std::filesystem::path& output_filepath)
{
    CHECK_ARG(output_filepath.extension() == ".lxfml", "Output file extension must be .lxfml");

    pugi::xml_document doc;
    // LXFML
    pugi::xml_node lxfml = doc.append_child("LXFML");
    lxfml.append_attribute("versionMajor") = 5; // Copied from BrickLink Studio exported file
    lxfml.append_attribute("versionMinor") = 0;
    lxfml.append_attribute("name") = brick_model.name();
    // Meta
    pugi::xml_node meta = lxfml.append_child("Meta");
    pugi::xml_node application = meta.append_child("Application");
    application.append_attribute("name") = "BrickFormer";
    application.append_attribute("version") = BF_GIT_VERSION_FULL;
    // Bricks
    pugi::xml_node bricks = lxfml.append_child("Bricks");
    uint32_t ref_id = 0;
    for (const auto& [key, quantity] : brick_model.m_brick_quantities) {
        uint32_t bid = (key >> 16) & 0xFFFF;
        uint32_t cid = key & 0xFFFF;
        uint32_t lego_design_id = k_brick_design_ids[bid];
        uint32_t lego_color_id = k_brick_colors[cid].lego_id;
        uint64_t lego_element_id = k_lego_element_ids[bid][cid];
        ARP_DEBUG("Exporting quantity %3d of BID %03d, Design ID: %04d, Color ID: %03d -> Element ID: %d",
                  quantity,
                  bid,
                  lego_design_id,
                  lego_color_id,
                  lego_element_id);

        if (lego_element_id == UINT64_MAX) {
            ARP_ERROR("BID %d, CID %d (Design ID: %d, Color: %s), is not a valid LEGO element",
                      bid,
                      cid,
                      lego_design_id,
                      lego_color_id);
            continue;
        }
        for (uint32_t i = 0; i < quantity; ++i) {
            // Brick
            pugi::xml_node brick = bricks.append_child("Brick");
            brick.append_attribute("refID") = ref_id;
            brick.append_attribute("designID") = lego_design_id;
            brick.append_attribute("itemNos") = lego_element_id;
            // Part
            pugi::xml_node part = brick.append_child("Part");
            part.append_attribute("refID") = ref_id;
            part.append_attribute("designID") = lego_design_id;
            part.append_attribute("partType") = "rigid";
            part.append_attribute("materials") = tfm::format("%d,0", lego_color_id);
            ++ref_id;
        }
    }
    bool result = doc.save_file(output_filepath.string().c_str());
    CHECK_ARG(result, "Failed to export .lxfml file to: %s", output_filepath.string());
}

void BrickModelIO::lxf_export(const BrickModel& brick_model, const std::filesystem::path& output_filepath)
{
    using namespace zipper;

    CHECK_ARG(output_filepath.extension() == ".lxf", "Output file extension must be .lxf");

    std::filesystem::path lxfml_filepath = std::filesystem::temp_directory_path() / "IMAGE100.lxfml";
    lxfml_export(brick_model, lxfml_filepath);
    ARP_DEBUG("Exported LXFML to: %s", lxfml_filepath.string());

    std::filesystem::path thumbnail_filepath = std::filesystem::temp_directory_path() / "IMAGE100.png";
    // Dummy thumbnail, it's required to make Bricklink import work!
    std::vector<uint8_t> image_data(128 * 128 * 4, 0xFF);
    CHECK_STATE(stbi_write_png(thumbnail_filepath.c_str(), 128 /* w */, 128 /* h */, 4, image_data.data(), 0));
    ARP_DEBUG("Created dummy thumbnail at: %s", thumbnail_filepath.string());

    // Reference:
    // https://wiki.ldraw.org/wiki/LXF

    // Using Zipper;
    // Tried https://github.com/kuba--/zip/ but creates a .zip file not supported by Bricklink (no CRC?)
    Zipper zipper(output_filepath);
    {
        std::ifstream lxfml_file(lxfml_filepath, std::ios::binary);
        zipper.add(lxfml_file, "IMAGE100.lxfml");
    }
    {
        std::ifstream thumbnail_file(thumbnail_filepath, std::ios::binary);
        zipper.add(thumbnail_file, "IMAGE100.png");
    }
    zipper.close();
    ARP_INFO("Exported LXF at: %s", output_filepath.string());

    std::filesystem::remove(lxfml_filepath);
    std::filesystem::remove(thumbnail_filepath);
}
