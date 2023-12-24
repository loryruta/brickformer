#include "cuda_interop_helpers.cuh"

using namespace lego_builder;

CudaMappedGlTexture::CudaMappedGlTexture(CudaMappedGlTexture&& other) noexcept :
    m_gl_texture(other.m_gl_texture),
    m_resource(other.m_resource),
    m_mapped_ptr(other.m_mapped_ptr)
{
    other.m_gl_texture = 0;
    other.m_resource = nullptr;
    other.m_mapped_ptr = nullptr;
}

CudaMappedGlTexture::~CudaMappedGlTexture()
{
    if (m_resource != nullptr)
    {
        CHECK_CU(cudaGraphicsUnmapResources(1, &m_resource));
        CHECK_CU(cudaGraphicsUnregisterResource(m_resource));

        m_mapped_ptr = nullptr;
        m_resource = nullptr;
    }

    if (m_gl_texture != 0)
    {
        glDeleteTextures(1, &m_gl_texture);

        m_gl_texture = 0;
    }
}

GLuint create_gl_texture(uint32_t width, uint32_t height)
{
    GLuint gl_texture;
    glGenTextures(1, &gl_texture);
    glBindTexture(GL_TEXTURE_2D, gl_texture);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, GL_NONE, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);

    glBindTexture(GL_TEXTURE_2D, 0);

    return gl_texture;
}

void CudaMappedGlTexture::copy_from(const DeviceImage<4, uint8_t>& image)
{
    CHECK_CU(cudaMemcpy2DToArray(
            m_mapped_ptr, 0, 0,
            image.m_data,
            image.m_width * image.pixel_size(),  // spitch (tightly packed)
            image.m_width * image.pixel_size(),  // width
            image.m_height,
            cudaMemcpyDeviceToDevice));
    CHECK_CU(cudaDeviceSynchronize());
}

CudaMappedGlTexture CudaMappedGlTexture::create(uint32_t width, uint32_t height)
{
    GLuint gl_texture = create_gl_texture(width, height);

    cudaGraphicsResource* resource;
    CHECK_CU(cudaGraphicsGLRegisterImage(
            &resource,
            gl_texture,
            GL_TEXTURE_2D,
            cudaGraphicsRegisterFlagsWriteDiscard  // CUDA only writes to the resource
    ));

    cudaArray_t mapped_ptr;
    CHECK_CU(cudaGraphicsMapResources(1, &resource));
    CHECK_CU(cudaGraphicsSubResourceGetMappedArray(&mapped_ptr, resource, 0 /* arrayIndex */, 0 /* mipLevel */));

    CudaMappedGlTexture result{};
    result.m_gl_texture = gl_texture;
    result.m_resource = resource;
    result.m_mapped_ptr = mapped_ptr;
    return result;
}



