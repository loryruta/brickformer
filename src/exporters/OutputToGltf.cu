#include "OutputToGltf.cuh"

#include <numeric>

#include <tiny_gltf.h>

#include "brick_models.hpp"
#include "bricks.hpp"

using namespace lego_builder;

OutputToGltf::OutputToGltf(const Arpenteur& arpenteur) :
    m_arpenteur(arpenteur),
    m_min_position(std::numeric_limits<float>::infinity()),
    m_max_position(-std::numeric_limits<float>::infinity())
{
}

std::vector<Vertex> transform_vertices(const std::vector<Vertex>& vertices, const glm::mat4& transform, const glm::vec4& color)
{
    std::vector<Vertex> result(vertices.size());
    std::transform(
        vertices.begin(), vertices.end(), result.begin(),
        [&](const Vertex& v)
        {
            Vertex tv = v;
            tv.m_position = transform * glm::vec4(tv.m_position, 1.0f);
            tv.m_color = glm::clamp(color / 255.f, 0.f, 1.f);
            return tv;
        }
    );
    return result;
}

void OutputToGltf::set_brick_1x1(int x, int y, int z, int subslice_mask, const glm::vec<4, uint8_t>& color)
{
    auto add_vertices = [&](const std::vector<Vertex>& vertices, const glm::mat4& transform)
    {
        std::vector<Vertex> transformed_vertices = transform_vertices(vertices, transform, color);

        for (const Vertex& v : transformed_vertices)
        {
            m_min_position = glm::min(m_min_position, v.m_position);
            m_max_position = glm::max(m_max_position, v.m_position);
        }

        uint32_t start_idx = m_vertices.size();
        m_vertices.insert(m_vertices.end(), transformed_vertices.begin(), transformed_vertices.end());

        std::vector<uint32_t> new_indices(vertices.size());
        std::iota(new_indices.begin(), new_indices.end(), start_idx);
        m_indices.insert(m_indices.end(), new_indices.begin(), new_indices.end());
    };

    glm::mat4 brick_transform = glm::identity<glm::mat4>();
    brick_transform = glm::translate(brick_transform, glm::vec3{x, y * (k_1x1_brick_size.y / k_1x1_brick_size.x), z}); // Translate to voxel
    brick_transform = glm::scale(brick_transform, glm::vec3{1.0f / k_1x1_brick_plate_size.x});                         // Normalization

    bool is_full_brick = (subslice_mask & 0x7) == 0x7;
    if (is_full_brick)
    {
        add_vertices(k_1x1_brick_vertices, brick_transform);
    }
    else
    {
        for (int subslice = 0; subslice < 3; subslice++)
        {
            if (subslice_mask & (1 << subslice))
            {
                glm::mat4 plate_transform{1.0f};
                if (subslice > 0)
                {
                    // Move the plate at subslice height
                    float norm_plate_y = k_1x1_brick_plate_size.y / k_1x1_brick_plate_size.x;
                    plate_transform = glm::translate(plate_transform, glm::vec3{0, subslice * norm_plate_y, 0});
                }

                add_vertices(k_1x1_brick_plate_vertices, plate_transform * brick_transform);
            }
        }
    }
}

void OutputToGltf::on_placement_end(uint32_t slice_y)
{
    for (const ColoredPlacement& colored_placement : m_arpenteur.m_colored_placements)
    {
        const Placement& placement = colored_placement.m_placement;

        int x = placement.m_x;
        int z = placement.m_y;
        int y = (int) slice_y;

        auto& brick = k_bricks[placement.m_bid];
        for (int bz = 0; bz < BRICK_MAX_HEIGHT; bz++)
        {
            for (int bx = 0; bx < BRICK_MAX_WIDTH; bx++)
            {
                if (brick[bz][bx])
                {
                    set_brick_1x1(x + bx, y, z + bz, colored_placement.m_subslice_mask, colored_placement.m_color);
                }
            }
        }
    }
}

void OutputToGltf::complete(const std::filesystem::path& output_dir)
{
    tinygltf::Model model{};

    printf("[INFO ] [OutputToGltf] Competed; Vertices: %zu, Indices: %zu\n", m_vertices.size(), m_indices.size());

    if (m_vertices.empty() || m_indices.empty())
    {
        printf("[WARN ] [OutputToGltf] No vertices/indices, nothing to export!\n");
        return;
    }

    // Vertex buffer
    tinygltf::Buffer& vertex_buffer = model.buffers.emplace_back();
    vertex_buffer.name = "Vertex buffer";
    vertex_buffer.data.resize(m_vertices.size() * sizeof(Vertex));
    std::memcpy(vertex_buffer.data.data(), m_vertices.data(), m_vertices.size() * sizeof(Vertex));

    printf("[INFO ] [OutputToGltf] Vertex buffer; Size: %zu\n", vertex_buffer.data.size());

    // Index buffer
    tinygltf::Buffer& index_buffer = model.buffers.emplace_back();
    index_buffer.name = "Index buffer";
    index_buffer.data.resize(m_indices.size() * sizeof(uint32_t));
    std::memcpy(index_buffer.data.data(), m_indices.data(), m_indices.size() * sizeof(uint32_t));

    printf("[INFO ] [OutputToGltf] Index buffer; Size: %zu\n", index_buffer.data.size());

    // Position
    tinygltf::BufferView& position_buffer_view = model.bufferViews.emplace_back();
    position_buffer_view.name = "Position buffer view";
    position_buffer_view.buffer = 0;
    position_buffer_view.byteOffset = offsetof(Vertex, m_position);
    position_buffer_view.byteLength = m_vertices.size() * sizeof(Vertex);
    position_buffer_view.byteStride = sizeof(Vertex);
    position_buffer_view.target = TINYGLTF_TARGET_ARRAY_BUFFER;

    printf(
        "[INFO ] [OutputToGltf] Position buffer view; Byte offset: %zu, Byte length: %zu, Byte stride: %zu\n", position_buffer_view.byteOffset,
        position_buffer_view.byteLength, position_buffer_view.byteStride
    );

    tinygltf::Accessor& position_accessor = model.accessors.emplace_back();
    position_accessor.bufferView = 0;
    position_accessor.name = "Position accessor";
    position_accessor.byteOffset = 0;
    position_accessor.componentType = TINYGLTF_COMPONENT_TYPE_FLOAT;
    position_accessor.count = m_vertices.size();
    position_accessor.type = TINYGLTF_TYPE_VEC3;
    position_accessor.minValues = {m_min_position[0], m_min_position[1], m_min_position[2]};
    position_accessor.maxValues = {m_max_position[0], m_max_position[1], m_max_position[2]};

    // Normal
    tinygltf::BufferView& normal_buffer_view = model.bufferViews.emplace_back();
    normal_buffer_view.name = "Normal buffer view";
    normal_buffer_view.buffer = 0;
    normal_buffer_view.byteOffset = offsetof(Vertex, m_normal);
    normal_buffer_view.byteLength = m_vertices.size() * sizeof(Vertex) - normal_buffer_view.byteOffset;
    normal_buffer_view.byteStride = sizeof(Vertex);
    normal_buffer_view.target = TINYGLTF_TARGET_ARRAY_BUFFER;

    printf(
        "[INFO ] [OutputToGltf] Normal buffer view; Byte offset: %zu, Byte length: %zu, Byte stride: %zu\n", normal_buffer_view.byteOffset,
        normal_buffer_view.byteLength, normal_buffer_view.byteStride
    );

    tinygltf::Accessor& normal_accessor = model.accessors.emplace_back();
    normal_accessor.bufferView = 1;
    normal_accessor.name = "Normal accessor";
    normal_accessor.byteOffset = 0;
    normal_accessor.componentType = TINYGLTF_COMPONENT_TYPE_FLOAT;
    normal_accessor.count = m_vertices.size();
    normal_accessor.type = TINYGLTF_TYPE_VEC3;

    // Texcoord
    tinygltf::BufferView& texcoord_buffer_view = model.bufferViews.emplace_back();
    texcoord_buffer_view.name = "Texcoord buffer view";
    texcoord_buffer_view.buffer = 0;
    texcoord_buffer_view.byteOffset = offsetof(Vertex, m_texcoord);
    texcoord_buffer_view.byteLength = m_vertices.size() * sizeof(Vertex) - offsetof(Vertex, m_texcoord);
    texcoord_buffer_view.byteStride = sizeof(Vertex);
    texcoord_buffer_view.target = TINYGLTF_TARGET_ARRAY_BUFFER;

    printf(
        "[INFO ] [OutputToGltf] Texcoord buffer view; Byte offset: %zu, Byte length: %zu, Byte stride: %zu\n", texcoord_buffer_view.byteOffset,
        texcoord_buffer_view.byteLength, texcoord_buffer_view.byteStride
    );

    tinygltf::Accessor& texcoord_accessor = model.accessors.emplace_back();
    texcoord_accessor.bufferView = 2;
    texcoord_accessor.name = "Texcoord accessor";
    texcoord_accessor.byteOffset = 0;
    texcoord_accessor.componentType = TINYGLTF_COMPONENT_TYPE_FLOAT;
    texcoord_accessor.count = m_vertices.size();
    texcoord_accessor.type = TINYGLTF_TYPE_VEC2;

    // Color
    tinygltf::BufferView& color_buffer_view = model.bufferViews.emplace_back();
    color_buffer_view.name = "Color buffer view";
    color_buffer_view.buffer = 0;
    color_buffer_view.byteOffset = offsetof(Vertex, m_color);
    color_buffer_view.byteLength = m_vertices.size() * sizeof(Vertex) - offsetof(Vertex, m_color);
    color_buffer_view.byteStride = sizeof(Vertex);
    color_buffer_view.target = TINYGLTF_TARGET_ARRAY_BUFFER;

    printf(
        "[INFO ] [OutputToGltf] Texcoord buffer view; Byte offset: %zu, Byte length: %zu, Byte stride: %zu\n", color_buffer_view.byteOffset,
        color_buffer_view.byteLength, color_buffer_view.byteStride
    );
    tinygltf::Accessor& color_accessor = model.accessors.emplace_back();
    color_accessor.bufferView = 3;
    color_accessor.name = "Color accessor";
    color_accessor.byteOffset = 0;
    color_accessor.componentType = TINYGLTF_COMPONENT_TYPE_FLOAT;
    color_accessor.count = m_vertices.size();
    color_accessor.type = TINYGLTF_TYPE_VEC4;

    // Index
    tinygltf::BufferView& index_buffer_view = model.bufferViews.emplace_back();
    index_buffer_view.name = "Index buffer view";
    index_buffer_view.buffer = 1;
    index_buffer_view.byteOffset = 0;
    index_buffer_view.byteLength = m_indices.size() * sizeof(uint32_t);
    index_buffer_view.byteStride = 0; // Tightly packed
    index_buffer_view.target = TINYGLTF_TARGET_ELEMENT_ARRAY_BUFFER;

    printf(
        "[INFO ] [OutputToGltf] Index buffer view; Byte offset: %zu, Byte length: %zu, Byte stride: %zu\n", index_buffer_view.byteOffset,
        index_buffer_view.byteLength, index_buffer_view.byteStride
    );

    tinygltf::Accessor& index_accessor = model.accessors.emplace_back();
    index_accessor.bufferView = 4;
    index_accessor.name = "Index accessor";
    index_accessor.byteOffset = 0;
    index_accessor.componentType = TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT;
    index_accessor.count = m_indices.size();
    index_accessor.type = TINYGLTF_TYPE_SCALAR;

    //
    tinygltf::Primitive primitive{};
    primitive.attributes.emplace("POSITION", 0);
    primitive.attributes.emplace("NORMAL", 1);
    primitive.attributes.emplace("TEXCOORD_0", 2);
    primitive.attributes.emplace("COLOR_0", 3);
    primitive.material = -1; // TODO material ?
    primitive.indices = 4;
    primitive.mode = TINYGLTF_MODE_TRIANGLES;

    tinygltf::Mesh& mesh = model.meshes.emplace_back();
    mesh.primitives.push_back(primitive);

    tinygltf::Node& node = model.nodes.emplace_back();
    node.mesh = 0;

    tinygltf::Scene& scene = model.scenes.emplace_back();
    scene.nodes.push_back(0);

    tinygltf::TinyGLTF writer{};
    writer.WriteGltfSceneToFile(&model, (output_dir / "output.gltf").string(), true, true, true, false /* writeBinary */);
    writer.WriteGltfSceneToFile(&model, (output_dir / "output.glb").string(), true, true, false, true /* writeBinary */);
}
