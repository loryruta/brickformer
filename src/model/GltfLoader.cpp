#include "GltfLoader.h"

#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/quaternion.hpp>

#include "log.h"
#include "util/misc.h"

#define ARP_LOG_CONTEXT "GltfLoader"

using namespace bf;

GltfLoader::GltfLoader() {}

void GltfLoader::copy_accessor_data(const tinygltf::Accessor& src_accessor,
                                    int src_type,
                                    void* dst_data,
                                    size_t dst_stride)
{
    CHECK_ARG(dst_data);

    size_t elem_size =
        tinygltf::GetNumComponentsInType(src_type) * tinygltf::GetComponentSizeInBytes(src_accessor.componentType);

    bool dst_tightly_packed = dst_stride == 0 || dst_stride == elem_size;

    tinygltf::BufferView& buffer_view = m_gltf_model.bufferViews.at(src_accessor.bufferView);
    size_t offset = buffer_view.byteOffset + src_accessor.byteOffset;

    tinygltf::Buffer& buffer = m_gltf_model.buffers.at(buffer_view.buffer);

    if (buffer_view.byteStride == 0 && dst_tightly_packed) {
        // If elements are tightly packed both in src and dst, we can copy in one shot
        std::memcpy(dst_data, buffer.data.data() + offset, elem_size * src_accessor.count);
    } else {
        if (dst_stride == 0) dst_stride = elem_size;

        for (size_t i = 0; i < src_accessor.count; i++) {
            std::memcpy(&((uint8_t*) dst_data)[dst_stride * i], &buffer.data[offset + elem_size * i], elem_size);
        }
    }
}

void GltfLoader::parse_vertices(const tinygltf::Primitive& primitive, Mesh& mesh, const glm::mat4& transform)
{
    assert(primitive.mode == TINYGLTF_MODE_TRIANGLES);

    tinygltf::Material& material = m_gltf_model.materials.at(primitive.material);
    tinygltf::PbrMetallicRoughness& pbr = material.pbrMetallicRoughness;

    // clang-format off
    ARP_DEBUG("Material \"%s\":\n"
              "  Emissive factor: (%.1f, %.1f, %.1f), Alpha mode: %s, Alpha cutoff: %f, Double sided: %d\n"
              "  Normal texture: %d, Occlusion texture: %d, Emissive texture: %d\n"
              "  PBR metallic roughness:\n"
              "    Base color factor: (%.1f, %.1f, %.1f, %.1f), Base color texture: %d\n"
              "    Metallic factor: %f, Roughness factor: %f, Metallic roughness texture: %d",
              material.name,
              material.emissiveFactor[0], material.emissiveFactor[1], material.emissiveFactor[2],
              material.alphaMode, material.alphaCutoff, material.doubleSided,
              material.normalTexture.index, material.occlusionTexture.index, material.emissiveTexture.index,
              pbr.baseColorFactor[0], pbr.baseColorFactor[1], pbr.baseColorFactor[2], pbr.baseColorFactor[3],
              pbr.baseColorTexture.index,
              pbr.metallicFactor, pbr.roughnessFactor, pbr.metallicRoughnessTexture.index
              );
    // clang-format on

    auto& attribs = primitive.attributes;

    ARP_DEBUG("Attributes:");
    for (const auto& [attrib_name, accessor_idx] : attribs) {
        ARP_DEBUG("    %s: %d", attrib_name.c_str(), accessor_idx);
    }

    // ------------------------------------------------------------------------------------------------
    // Initialize and sanitize accessors
    // ------------------------------------------------------------------------------------------------

    int position_accessor_idx = -1;
    int normal_accessor_idx = -1;
    int texcoord_accessor_idx = -1;
    int color_accessor_idx = -1;

    // Position
    position_accessor_idx = attribs.contains("POSITION") ? attribs.at("POSITION") : -1;
    CHECK_STATE(position_accessor_idx != -1, "POSITION attribute/accessor is required");
    size_t num_vertices;
    {
        tinygltf::Accessor& accessor = m_gltf_model.accessors[position_accessor_idx];
        CHECK_STATE(accessor.componentType == TINYGLTF_COMPONENT_TYPE_FLOAT);
        CHECK_STATE(accessor.type == TINYGLTF_TYPE_VEC3);
        num_vertices = accessor.count;
    }
    // Normal
    normal_accessor_idx = attribs.contains("NORMAL") ? attribs.at("NORMAL") : -1;
    if (normal_accessor_idx != -1) {
        tinygltf::Accessor& accessor = m_gltf_model.accessors.at(normal_accessor_idx);
        CHECK_STATE(accessor.componentType == TINYGLTF_COMPONENT_TYPE_FLOAT);
        CHECK_STATE(accessor.type == TINYGLTF_TYPE_VEC3);
        CHECK_STATE(accessor.count == num_vertices);
    } else {
        ARP_WARN("NORMAL attribute/accessor not found");
    }
    // Texcoord
    tinygltf::TextureInfo& texture = material.pbrMetallicRoughness.baseColorTexture;
    std::string texcoord_set_name = std::string("TEXCOORD_") + std::to_string(texture.texCoord);
    texcoord_accessor_idx = attribs.contains(texcoord_set_name) ? attribs.at(texcoord_set_name) : -1;
    if (texcoord_accessor_idx != -1) {
        tinygltf::Accessor& accessor = m_gltf_model.accessors.at(texcoord_accessor_idx);
        CHECK_STATE(accessor.componentType == TINYGLTF_COMPONENT_TYPE_FLOAT);
        CHECK_STATE(accessor.type == TINYGLTF_TYPE_VEC2 || accessor.type == TINYGLTF_TYPE_VEC3);
        CHECK_STATE(num_vertices == accessor.count);
    } else {
        ARP_WARN("%s attribute/accessor not found", texcoord_set_name);
    }
    // Color
    color_accessor_idx = attribs.contains("COLOR_0") ? attribs.at("COLOR_0") : -1;
    if (color_accessor_idx != -1) {
        color_accessor_idx = primitive.attributes.at("COLOR_0");
        tinygltf::Accessor& accessor = m_gltf_model.accessors.at(color_accessor_idx);
        CHECK_STATE(accessor.componentType == TINYGLTF_COMPONENT_TYPE_FLOAT);
        CHECK_STATE(accessor.type == TINYGLTF_TYPE_VEC3 || accessor.type == TINYGLTF_TYPE_VEC4);
        CHECK_STATE(accessor.count == num_vertices);
    } else {
        ARP_WARN("COLOR_0 attribute/accessor not found");
    }

    ARP_DEBUG("Uploading %zu vertices...", num_vertices);
    mesh.vertices.resize(num_vertices);

    // ----------------------------------------------------------------
    // Copy accessors data
    // ----------------------------------------------------------------

    uint8_t* dst_vertices = (uint8_t*) mesh.vertices.data();
    // Position
    {
        tinygltf::Accessor& accessor = m_gltf_model.accessors.at(position_accessor_idx);
        copy_accessor_data(accessor, TINYGLTF_TYPE_VEC3, dst_vertices + offsetof(Vertex, position), sizeof(Vertex));
    }
    // Normal
    if (normal_accessor_idx != -1) {
        tinygltf::Accessor& accessor = m_gltf_model.accessors.at(normal_accessor_idx);
        copy_accessor_data(accessor, TINYGLTF_TYPE_VEC3, dst_vertices + offsetof(Vertex, normal), sizeof(Vertex));
    } else {
    }
    // Texcoord
    if (texcoord_accessor_idx != -1) {
        tinygltf::Accessor& accessor = m_gltf_model.accessors.at(texcoord_accessor_idx);
        copy_accessor_data(accessor, TINYGLTF_TYPE_VEC2, dst_vertices + offsetof(Vertex, texcoord), sizeof(Vertex));
    }
    // Color
    if (color_accessor_idx != -1) {
        tinygltf::Accessor& accessor = m_gltf_model.accessors.at(color_accessor_idx);
        copy_accessor_data(accessor, accessor.type, dst_vertices + offsetof(Vertex, color), sizeof(Vertex));
    }

    // ----------------------------------------------------------------
    // Finalize vertices (e.g. missing texcoord)
    // ----------------------------------------------------------------

    for (size_t i = 0; i < mesh.vertices.size(); ++i) {
        Vertex& v = mesh.vertices.at(i);
        if (texcoord_accessor_idx == -1) {
            v.texcoord = glm::vec2(0);
        }
        if (color_accessor_idx != -1) {
            tinygltf::Accessor& accessor = m_gltf_model.accessors.at(color_accessor_idx);
            if (accessor.type == TINYGLTF_TYPE_VEC3) v.color[3] = 1.0f; // Set alpha
        }
    }

    // ----------------------------------------------------------------
    // Apply node transformation
    // ----------------------------------------------------------------

    mesh.apply_transform(transform);

    // ----------------------------------------------------------------
    // Compute bounding box
    // ----------------------------------------------------------------

    mesh.update_min_max();
}

void GltfLoader::parse_indices(const tinygltf::Primitive& primitive, Mesh& mesh)
{
    assert(primitive.indices >= 0);

    tinygltf::Accessor& indices_accessor = m_gltf_model.accessors[primitive.indices];
    assert(indices_accessor.count % 3 == 0);
    assert(indices_accessor.componentType == TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT ||
           indices_accessor.componentType == TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT);
    assert(indices_accessor.type == TINYGLTF_TYPE_SCALAR);

    mesh.indices.resize(indices_accessor.count);

    if (indices_accessor.componentType == TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT) {
        copy_accessor_data(indices_accessor, TINYGLTF_TYPE_SCALAR, (uint8_t*) mesh.indices.data(), 0);
    } else if (indices_accessor.componentType == TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT) {
        std::vector<uint16_t> indices16(indices_accessor.count);
        copy_accessor_data(indices_accessor, TINYGLTF_TYPE_SCALAR, (uint8_t*) indices16.data(), 0);
        // Yay! Iterate them... :')
        for (size_t i = 0; i < indices_accessor.count; i++) mesh.indices[i] = indices16[i];
    } else {
        throw IllegalArgumentException("Unsupported indices component type: %d", indices_accessor.componentType);
    }
}

void GltfLoader::parse_mesh(const tinygltf::Mesh& gltf_mesh, const glm::mat4& transform)
{
    ARP_DEBUG("Parsing mesh \"%s\" with %zu primitives...", gltf_mesh.name, gltf_mesh.primitives.size());

    for (size_t primitive_idx = 0; primitive_idx < gltf_mesh.primitives.size(); ++primitive_idx) {
        const tinygltf::Primitive& primitive = gltf_mesh.primitives.at(primitive_idx);

        if (primitive.mode != TINYGLTF_MODE_TRIANGLES) {
            ARP_WARN("Skipping \"%s\" primitive #%d. Unsupported primitive mode: %d",
                     gltf_mesh.name,
                     primitive_idx,
                     primitive.mode);
            continue;
        }

        Mesh mesh{};

        parse_vertices(primitive, mesh, transform);
        parse_indices(primitive, mesh);

        tinygltf::Material& material = m_gltf_model.materials.at(primitive.material);

        if (material.extensions.contains("KHR_materials_pbrSpecularGlossiness")) {
            auto& extension = material.extensions["KHR_materials_pbrSpecularGlossiness"];

            CHECK_STATE(extension.Get("diffuseFactor").IsArray());

            if (extension.Has("diffuseFactor")) {
                auto& diffuse_factor = extension.Get("diffuseFactor");
                mesh.m_color[0] = diffuse_factor.Get(0).GetNumberAsDouble();
                mesh.m_color[1] = diffuse_factor.Get(1).GetNumberAsDouble();
                mesh.m_color[2] = diffuse_factor.Get(2).GetNumberAsDouble();
                mesh.m_color[3] = diffuse_factor.Get(3).GetNumberAsDouble();
            }

            if (extension.Has("diffuseTexture")) {
                mesh.m_texture_idx = extension.Get("diffuseTexture").Get("index").GetNumberAsInt();
            }
        } else {
            auto& base_color_factor = material.pbrMetallicRoughness.baseColorFactor;
            mesh.m_color[0] = base_color_factor[0];
            mesh.m_color[1] = base_color_factor[1];
            mesh.m_color[2] = base_color_factor[2];
            mesh.m_color[3] = base_color_factor[3];

            mesh.m_texture_idx = material.pbrMetallicRoughness.baseColorTexture.index;
        }

        ARP_DEBUG("Adding mesh \"%s\" primitive %d; Color: (%.1f, %.1f, %.1f, %.1f), Texture: %d",
                  gltf_mesh.name,
                  primitive_idx,
                  mesh.m_color[0],
                  mesh.m_color[1],
                  mesh.m_color[2],
                  mesh.m_color[3],
                  mesh.m_texture_idx);

        m_model.m_meshes.emplace_back(mesh);
    }
}

void GltfLoader::parse_node(const tinygltf::Node& gltf_node, glm::mat4 transform)
{
    if (!gltf_node.matrix.empty()) {
        glm::mat4 matrix{};
        for (int i = 0; i < 4; i++) {
            matrix[i][0] = gltf_node.matrix[i * 4];
            matrix[i][1] = gltf_node.matrix[i * 4 + 1];
            matrix[i][2] = gltf_node.matrix[i * 4 + 2];
            matrix[i][3] = gltf_node.matrix[i * 4 + 3];
        }
        transform = transform * matrix;
    } else {
        if (!gltf_node.translation.empty()) {
            transform = glm::translate(
                transform, glm::vec3(gltf_node.translation[0], gltf_node.translation[1], gltf_node.translation[2]));
        }

        if (!gltf_node.rotation.empty()) {
            glm::quat quat(gltf_node.rotation[0], gltf_node.rotation[1], gltf_node.rotation[2], gltf_node.rotation[3]);
            transform = transform * glm::mat4_cast(quat);
        }

        if (!gltf_node.scale.empty()) {
            transform = glm::scale(transform, glm::vec3(gltf_node.scale[0], gltf_node.scale[1], gltf_node.scale[2]));
        }
    }

    if (gltf_node.mesh >= 0) {
        parse_mesh(m_gltf_model.meshes.at(gltf_node.mesh), transform);
    }

    for (int child_idx : gltf_node.children) {
        const tinygltf::Node& child = m_gltf_model.nodes.at(child_idx);
        parse_node(child, transform);
    }
}

void GltfLoader::parse_scene(const tinygltf::Scene& gltf_scene)
{
    for (int node_idx : gltf_scene.nodes) {
        const tinygltf::Node& gltf_node = m_gltf_model.nodes.at(node_idx);
        parse_node(gltf_node, glm::identity<glm::mat4>());
    }
}

void GltfLoader::load_textures()
{
    for (const tinygltf::Texture& gltf_texture : m_gltf_model.textures) {
        assert(gltf_texture.source >= 0);

        Texture texture{};
        texture.m_name = gltf_texture.name;

        const tinygltf::Image& gltf_image = m_gltf_model.images[gltf_texture.source];
        assert(!gltf_image.as_is); // Expect tinygltf to uniform image data (i.e. RGBA, UNSIGNED_BYTE, uncompressed...)
        assert(!gltf_image.image.empty());

        texture.m_width = gltf_image.width;
        texture.m_height = gltf_image.height;
        texture.m_image_data = gltf_image.image;

        ARP_DEBUG("Texture \"%s\" loaded; Width: %d, Height: %d, Bytesize: %zu",
                  texture.m_name,
                  texture.m_width,
                  texture.m_height,
                  texture.m_image_data.size());

        m_model.m_textures.emplace_back(texture);
    }
}

Model&& GltfLoader::load_file(const std::filesystem::path& model_path)
{
    tinygltf::TinyGLTF gltf_loader;
    std::string error;
    std::string warning;

    ARP_INFO("Loading GLTF model \"%s\"...", model_path.c_str());

    m_gltf_model = {};
    bool loaded;
    if (model_path.extension() == ".gltf") {
        loaded = gltf_loader.LoadASCIIFromFile(&m_gltf_model, &error, &warning, model_path);
    } else if (model_path.extension() == ".glb") {
        loaded = gltf_loader.LoadBinaryFromFile(&m_gltf_model, &error, &warning, model_path);
    } else {
        throw IllegalArgumentException("Invalid model format \"%s\": %s (expected .gltf or .glb)",
                                       model_path.string(),
                                       model_path.extension().string());
    }
    if (!loaded) {
        throw IllegalArgumentException(
            "Can't load model \"%s\"; Error: %s, Warning: %s", model_path.string(), error, warning);
    }
    if (!warning.empty()) {
        ARP_WARN("Warning issued during loading: %s", model_path.string(), warning);
    }

    // Parse model
    m_model = {};

    load_textures();
    parse_scene(m_gltf_model.scenes.at(m_gltf_model.defaultScene));

    m_model.update_min_max(false /* update_mesh_minmax */);

    ARP_INFO("Loaded model \"%s\"", model_path.string());

    m_gltf_model = {};

    return std::move(m_model);
}
