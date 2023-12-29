#pragma once

#include <filesystem>

#include <tiny_gltf.h>

#include "Model.hpp"

namespace lego_builder
{
    class GltfLoader
    {
    private:
        tinygltf::TinyGLTF m_gltf_loader;

        tinygltf::Model m_gltf_model;
        Model m_model;

    public:
        explicit GltfLoader();
        GltfLoader(const GltfLoader& other) = delete;
        GltfLoader(GltfLoader&& other) = default;
        ~GltfLoader() = default;

        Model&& load_file(const std::filesystem::path& model_path);

    private:
        void copy_accessor_data(const tinygltf::Accessor& src_accessor, int src_type, void* dst_data, size_t dst_size);

        void parse_vertices(const tinygltf::Primitive& primitive, Mesh& mesh, const glm::mat4& transform);
        void parse_indices(const tinygltf::Primitive& primitive, Mesh& mesh);

        void parse_mesh(const tinygltf::Mesh& gltf_mesh, const glm::mat4& transform);
        void parse_node(const tinygltf::Node& gltf_node, glm::mat4 transform);
        void parse_scene(const tinygltf::Scene& gltf_scene);

        void load_textures();
    };
}
