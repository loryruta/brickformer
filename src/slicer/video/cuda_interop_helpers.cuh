#pragma once

#include <cstdint>

#include <glad/gl.h>
#include <cuda_gl_interop.h>

#include "../misc.cuh"
#include "../../DeviceImage.cuh"

namespace lego_builder
{
    struct CudaMappedGlTexture
    {
    private:
        cudaGraphicsResource* m_resource;
        GLuint m_gl_texture;
        cudaArray_t m_mapped_ptr;

        CudaMappedGlTexture() = default;

    public:
        CudaMappedGlTexture(const CudaMappedGlTexture& other) = delete;
        CudaMappedGlTexture(CudaMappedGlTexture&& other) noexcept;
        ~CudaMappedGlTexture();

        [[nodiscard]] GLuint gl_texture() const { return m_gl_texture; }

        void copy_from(const DeviceImage<4, uint8_t>& image);

        static CudaMappedGlTexture create(uint32_t width, uint32_t height);
    };
}