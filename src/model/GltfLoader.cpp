#include "GltfLoader.hpp"

#include "glm/gtc/matrix_transform.hpp"
#include "glm/gtc/quaternion.hpp"

using namespace lego_builder;

GltfLoader::GltfLoader() {}

void GltfLoader::copy_accessor_data(const tinygltf::Accessor& src_accessor, int src_type, void* dst_data, size_t dst_stride)
{
    assert(dst_data);

    size_t elem_size = tinygltf::GetNumComponentsInType(src_type) *
                       tinygltf::GetComponentSizeInBytes(src_accessor.componentType);

    bool dst_tightly_packed = dst_stride == 0 || dst_stride == elem_size;

    tinygltf::BufferView& buffer_view = m_gltf_model.bufferViews.at(src_accessor.bufferView);
    size_t offset = buffer_view.byteOffset + src_accessor.byteOffset;

    tinygltf::Buffer& buffer = m_gltf_model.buffers.at(buffer_view.buffer);

    if (buffer_view.byteStride == 0 && dst_tightly_packed)
    {
        // If elements are tightly packed both in src and dst, we can copy in one shot
        std::memcpy(dst_data, buffer.data.data() + offset, elem_size * src_accessor.count);
    }
    else
    {
        if (dst_stride == 0) dst_stride = elem_size;

        for (size_t i = 0; i < src_accessor.count; i++)
        {
            std::memcpy(&((uint8_t*) dst_data)[dst_stride * i], &buffer.data[offset + elem_size * i], elem_size);
        }
    }
}

void GltfLoader::parse_vertices(const tinygltf::Primitive& primitive, Mesh& mesh, const glm::mat4& transform)
{
    assert(primitive.mode == TINYGLTF_MODE_TRIANGLES);

    tinygltf::Material& material = m_gltf_model.materials.at(primitive.material);

    int accessor_idx;

    // Position
    accessor_idx = primitive.attributes.at("POSITION");
    tinygltf::Accessor& pos_accessor = m_gltf_model.accessors[accessor_idx];
    assert(pos_accessor.componentType == TINYGLTF_COMPONENT_TYPE_FLOAT);
    assert(pos_accessor.type == TINYGLTF_TYPE_VEC3);

    // Normal
    accessor_idx = primitive.attributes.at("NORMAL");
    tinygltf::Accessor& normal_accessor = m_gltf_model.accessors[accessor_idx];
    assert(normal_accessor.componentType == TINYGLTF_COMPONENT_TYPE_FLOAT);
    assert(normal_accessor.type == TINYGLTF_TYPE_VEC3);

    // Texcoord
    tinygltf::TextureInfo& texture = material.pbrMetallicRoughness.baseColorTexture;
    std::string texcoord_set_name = std::string("TEXCOORD_") + std::to_string(texture.texCoord);
    accessor_idx = primitive.attributes.at(texcoord_set_name);
    tinygltf::Accessor& texcoord_accessor = m_gltf_model.accessors[accessor_idx];
    assert(normal_accessor.componentType == TINYGLTF_COMPONENT_TYPE_FLOAT);
    assert(normal_accessor.type == TINYGLTF_TYPE_VEC2 || normal_accessor.type == TINYGLTF_TYPE_VEC3);

    // Color
    tinygltf::Accessor* color_accessor = nullptr;

    if (primitive.attributes.contains("COLOR_0"))
    {
        accessor_idx = primitive.attributes.at("COLOR_0");
        color_accessor = &m_gltf_model.accessors[accessor_idx];
        assert(normal_accessor.componentType == TINYGLTF_COMPONENT_TYPE_FLOAT);
        assert(normal_accessor.type == TINYGLTF_TYPE_VEC3 || normal_accessor.type == TINYGLTF_TYPE_VEC4);
    }

    //
    size_t num_vertices = pos_accessor.count;
    assert(num_vertices == normal_accessor.count);
    assert(num_vertices == texcoord_accessor.count);
    assert(!color_accessor || num_vertices == color_accessor->count);

    mesh.m_vertices.resize(num_vertices);

    printf("[GltfLoader] Uploading %zu vertices...\n", num_vertices);

    uint8_t* dst_vertices = (uint8_t*) mesh.m_vertices.data();

    copy_accessor_data(pos_accessor, TINYGLTF_TYPE_VEC3, dst_vertices + offsetof(Vertex, m_position), sizeof(Vertex));
    copy_accessor_data(normal_accessor, TINYGLTF_TYPE_VEC3, dst_vertices + offsetof(Vertex, m_normal), sizeof(Vertex));
    copy_accessor_data(texcoord_accessor, TINYGLTF_TYPE_VEC2, dst_vertices + offsetof(Vertex, m_texcoord), sizeof(Vertex));

    if (color_accessor)
    {
        copy_accessor_data(*color_accessor, color_accessor->type, dst_vertices + offsetof(Vertex, m_color), sizeof(Vertex));
    }

    // Apply the transform to all vertices' position
    mesh.apply_transform(transform);

    // Compute the mesh min/max
    mesh.update_min_max();
}

void GltfLoader::parse_indices(const tinygltf::Primitive& primitive, Mesh& mesh)
{
    assert(primitive.indices >= 0);

    tinygltf::Accessor& indices_accessor = m_gltf_model.accessors[primitive.indices];
    assert(indices_accessor.count % 3 == 0);
    assert(indices_accessor.componentType == TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT ||
           indices_accessor.componentType == TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT
           );
    assert(indices_accessor.type == TINYGLTF_TYPE_SCALAR);

    mesh.m_indices.resize(indices_accessor.count);

    if (indices_accessor.componentType == TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT)
    {
        copy_accessor_data(indices_accessor, TINYGLTF_TYPE_SCALAR, (uint8_t*) mesh.m_indices.data(), 0);
    }
    else if (indices_accessor.componentType == TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT)
    {
        std::vector<uint16_t> indices16(indices_accessor.count);
        copy_accessor_data(indices_accessor, TINYGLTF_TYPE_SCALAR, (uint8_t*) indices16.data(), 0);

        // Yay! Iterate them... :')
        for (size_t i = 0; i < indices_accessor.count; i++) mesh.m_indices[i] = indices16[i];
    }
    else
    {
        assert(false); // TODO throw an exception or smth
    }
}

void GltfLoader::parse_mesh(const tinygltf::Mesh& gltf_mesh, const glm::mat4& transform)
{
    Mesh mesh{};

    for (const tinygltf::Primitive& primitive : gltf_mesh.primitives)
    {
        if (primitive.mode != TINYGLTF_MODE_TRIANGLES)
        {
            printf("[GltfLoader] WARNING: Skipping primitive mode: %d\n", primitive.mode);
            continue;
        }

        parse_vertices(primitive, mesh, transform);
        parse_indices(primitive, mesh);

        tinygltf::Material& material = m_gltf_model.materials.at(primitive.material);
        mesh.m_texture_idx = material.pbrMetallicRoughness.baseColorTexture.index;
    }

    m_model.m_meshes.emplace_back(std::move(mesh));
}

void GltfLoader::parse_node(const tinygltf::Node& gltf_node, glm::mat4 transform)
{
    if (!gltf_node.matrix.empty())
    {
        for (int i = 0; i < 4; i++)
        {
            transform[i][0] = gltf_node.matrix[i * 4 + 0];
            transform[i][1] = gltf_node.matrix[i * 4 + 1];
            transform[i][2] = gltf_node.matrix[i * 4 + 2];
            transform[i][3] = gltf_node.matrix[i * 4 + 3];
        }
    }
    else
    {
        if (!gltf_node.translation.empty())
        {
            transform = glm::translate(transform, glm::vec3(
                    gltf_node.translation[0],
                    gltf_node.translation[1],
                    gltf_node.translation[2]
                    ));
        }

        if (!gltf_node.rotation.empty())
        {
            glm::quat quat(gltf_node.rotation[0], gltf_node.rotation[1], gltf_node.rotation[2], gltf_node.rotation[3]);
            transform = transform * glm::mat4_cast(quat);
        }

        if (!gltf_node.scale.empty())
        {
            transform = glm::scale(transform, glm::vec3(gltf_node.scale[0], gltf_node.scale[1], gltf_node.scale[2]));
        }
    }

    if (gltf_node.mesh >= 0) parse_mesh(m_gltf_model.meshes.at(gltf_node.mesh), transform);

    for (int child_idx : gltf_node.children)
    {
        const tinygltf::Node& child = m_gltf_model.nodes.at(child_idx);
        parse_node(child, transform);
    }
}

void GltfLoader::parse_scene(const tinygltf::Scene& gltf_scene)
{
    for (int node_idx : gltf_scene.nodes)
    {
        const tinygltf::Node& gltf_node = m_gltf_model.nodes.at(node_idx);
        parse_node(gltf_node, glm::identity<glm::mat4>());
    }
}

void GltfLoader::load_textures()
{
    for (const tinygltf::Texture& gltf_texture : m_gltf_model.textures)
    {
        assert(gltf_texture.source >= 0);

        Texture texture{};
        texture.m_name = gltf_texture.name;

        const tinygltf::Image& gltf_image = m_gltf_model.images[gltf_texture.source];
        assert(!gltf_image.as_is);  // Expect tinygltf to uniform image data (i.e. RGBA, UNSIGNED_BYTE, uncompressed...)
        assert(!gltf_image.image.empty());

        texture.m_width = gltf_image.width;
        texture.m_height = gltf_image.height;
        texture.m_image_data = gltf_image.image;

        printf("[GltfLoader] Texture loaded; Width: %d, Height: %d, Data size: %zu\n",
               texture.m_width, texture.m_height, texture.m_image_data.size());

        m_model.m_textures.emplace_back(texture);
    }
}

Model&& GltfLoader::load_file(const std::filesystem::path& model_path)
{
    tinygltf::TinyGLTF gltf_loader;
    std::string error;
    std::string warning;

    // Load model
    printf("[GltfLoader] Loading GLTF model \"%s\"...\n", model_path.c_str());

    m_gltf_model = {};

    bool loaded;
    if (model_path.extension() == ".gltf")
    {
        loaded = gltf_loader.LoadASCIIFromFile(&m_gltf_model, &error, &warning, model_path);
    }
    else if (model_path.extension() == ".glb")
    {
        loaded = gltf_loader.LoadBinaryFromFile(&m_gltf_model, &error, &warning, model_path);
    }
    else
    {
        printf("Invalid model format \"%s\": %s\n", model_path.extension().c_str(), model_path.c_str());
        exit(1);
    }

    if (!loaded)
    {
        printf("Can't load model at: %s\n", model_path.c_str());
        exit(1);
    }

    if (!warning.empty()) printf("Warning: %s\n", warning.c_str());

    if (!error.empty())
    {
        printf("Error: %s\n", error.c_str());
        exit(1);
    }

    // Parse model
    m_model = {};

    load_textures();
    parse_scene(m_gltf_model.scenes.at(m_gltf_model.defaultScene));

    m_model.update_min_max(false /* update_mesh_minmax */);

    printf("Model loaded!\n");

    m_gltf_model = {};

    //
    return std::move(m_model);
}
