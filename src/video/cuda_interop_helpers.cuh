#pragma once

#include <cstdint>

#include "glad/gl.h"
#include <cuda_gl_interop.h>

#include "DeviceImage.cuh"
#include "util/misc.cuh"

namespace lego_builder
{

/// A RAII wrapper for cudaGraphicsResource that represents a GL texture.
class CUDAMappedGLTexture
{
private:
    GLuint m_texture;  // Not owned!
    cudaGraphicsResource* m_resource;
    cudaArray_t m_mapped_ptr;

public:
    explicit CUDAMappedGLTexture(GLuint texture);
    CUDAMappedGLTexture(const CUDAMappedGLTexture&) = delete;
    CUDAMappedGLTexture(CUDAMappedGLTexture&& other) noexcept;
    ~CUDAMappedGLTexture();

    [[nodiscard]] GLuint texture() const { return m_texture; }

    void copy_from(DeviceImage<4, uint8_t>& image);
};
}