#include "DeviceModel.cuh"

#include "util/misc.cuh"

using namespace lego_builder;

const DeviceModel* lego_builder::upload_model(const Model& model)
{
    std::vector<cudaTextureObject_t> d_textures;
    std::vector<DeviceMesh> d_meshes;

    for (const Texture& texture : model.m_textures)
    {
        // Reference:
        // https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#texture-object-api

        cudaChannelFormatDesc channel_desc = cudaCreateChannelDesc(8, 8, 8, 8, cudaChannelFormatKindUnsigned);

        cudaArray_t tex_array{};
        CHECK_CU(cudaMallocArray(&tex_array, &channel_desc, texture.m_width, texture.m_height));

        const size_t spitch = texture.m_width * 4 * sizeof(uint8_t);  // Tightly packed (no padding)
        CHECK_CU(cudaMemcpy2DToArray(
                tex_array,
                0, 0,
                texture.m_image_data.data(),
                spitch,
                texture.m_width * 4 * sizeof(uint8_t), texture.m_height,
                cudaMemcpyHostToDevice));

        cudaResourceDesc res_desc{};
        res_desc.resType = cudaResourceTypeArray;
        res_desc.res.array.array = tex_array;

        cudaTextureDesc tex_desc{};
        tex_desc.addressMode[0] = cudaAddressModeWrap;
        tex_desc.addressMode[1] = cudaAddressModeWrap;
        tex_desc.filterMode = cudaFilterModePoint;  // Use this if uint8_t pixels (otherwise cudaErrorInvalidFilterSetting)
        tex_desc.readMode = cudaReadModeNormalizedFloat;
        tex_desc.normalizedCoords = true;

        cudaTextureObject_t d_texture{};
        CHECK_CU(cudaCreateTextureObject(&d_texture, &res_desc, &tex_desc, nullptr));

        d_textures.emplace_back(d_texture);
    }

    for (const Mesh& mesh : model.m_meshes)
    {
        DeviceMesh d_mesh{};

        d_mesh.m_vertices = to_device(mesh.vertices.data(), mesh.vertices.size());
        d_mesh.m_indices = to_device(mesh.indices.data(), mesh.indices.size());

        d_mesh.m_color = mesh.m_color;
        d_mesh.m_texture_idx = mesh.m_texture_idx;

        d_meshes.emplace_back(d_mesh);
    }

    DeviceModel d_model{};
    d_model.m_textures = to_device(d_textures.data(), d_textures.size());
    d_model.m_meshes = to_device(d_meshes.data(), d_meshes.size());
    return to_device(d_model);
}
