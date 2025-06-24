#include "cuda_interop_helpers.cuh"

using namespace bf;

CUDAMappedGLTexture::CUDAMappedGLTexture(GLuint texture)
{
    m_texture = texture;

    CHECK_CU(cudaGraphicsGLRegisterImage(&m_resource, m_texture, GL_TEXTURE_2D, cudaGraphicsRegisterFlagsWriteDiscard));
    CHECK_CU(cudaGraphicsMapResources(1, &m_resource));
    CHECK_CU(cudaGraphicsSubResourceGetMappedArray(&m_mapped_ptr, m_resource, 0, 0));
}

CUDAMappedGLTexture::CUDAMappedGLTexture(CUDAMappedGLTexture&& other) noexcept :
    m_texture(other.m_texture),
    m_resource(other.m_resource),
    m_mapped_ptr(other.m_mapped_ptr)
{
    other.m_texture = 0;
    other.m_resource = nullptr;
    other.m_mapped_ptr = nullptr;
}

CUDAMappedGLTexture::~CUDAMappedGLTexture()
{
    if (m_resource != nullptr)
    {
        CHECK_CU(cudaGraphicsUnmapResources(1, &m_resource));
        CHECK_CU(cudaGraphicsUnregisterResource(m_resource));

        m_texture = 0;
        m_mapped_ptr = nullptr;
        m_resource = nullptr;
    }
}

void CUDAMappedGLTexture::copy_from(DeviceImage<4, uint8_t>& image, cudaStream_t stream)
{
    CHECK_CU(cudaMemcpy2DToArrayAsync(
        m_mapped_ptr,
        0, 0,
        image.m_data,
        image.m_width * image.pixel_size(), // spitch (tightly packed)
        image.m_width * image.pixel_size(), // width
        image.m_height,
        cudaMemcpyDeviceToDevice,
        stream
    ));
}
