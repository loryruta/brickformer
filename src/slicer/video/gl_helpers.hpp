#pragma once

#include <cassert>
#include <string>

#include <glad/gl.h>

#ifdef __CUDACC__
#include "../misc.cuh"
#include "../../DeviceImage.cuh"
#include <cuda_gl_interop.h>
#endif

namespace lego_builder
{
    inline GLuint create_shader(GLenum type, const char* src)
    {
        GLuint shader = glCreateShader(type);
        glShaderSource(shader, 1, &src, nullptr);
        glCompileShader(shader);

        GLint compile_status = 0;
        glGetShaderiv(shader, GL_COMPILE_STATUS, &compile_status);
        if (!compile_status)
        {
            GLint max_log_length;
            glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &max_log_length);

            std::string log_str;
            log_str.resize(max_log_length);
            glGetShaderInfoLog(shader, max_log_length, &max_log_length, log_str.data());

            glDeleteShader(shader);

            printf("ERROR: Shader failed to compile: %s\n", log_str.c_str());
            exit(1);
        }

        return shader;
    }

    inline void link_program(GLuint program)
    {
        glLinkProgram(program);

        GLint link_status = 0;
        glGetProgramiv(program, GL_LINK_STATUS, &link_status);
        if (!link_status)
        {
            GLint max_log_length;
            glGetProgramiv(program, GL_INFO_LOG_LENGTH, &max_log_length);

            std::string log_str;
            log_str.resize(max_log_length);
            glGetProgramInfoLog(program, max_log_length, &max_log_length, &log_str[0]);

            glDeleteProgram(program);

            printf("ERROR: Shader failed to compile: %s\n", log_str.c_str());
            exit(1);
        }
    }

    inline GLint get_attrib_location(GLuint program, const char* name, bool require = true)
    {
        GLint loc = glGetAttribLocation(program, name);
        assert(!require || loc >= 0);  // TODO no assert
        return loc;
    }

    inline GLint get_uniform_location(GLuint program, const char* name, bool require = true)
    {
        GLint loc = glGetUniformLocation(program, name);
        assert(!require || loc >= 0); // TODO no assert
        return loc;
    }

    void enable_gl_debug_output();

#ifdef __CUDACC__
    /// Temporarily maps the given OpenGL texture to a CUDA cudaArray_t and invokes the given callback.
    /// On exit, the texture storage is unmapped and CUDA resource is unregistered.
    template<typename CALLBACK>
    void cuda_access_gl_texture(GLuint gl_texture, CALLBACK callback)
    {
        cudaGraphicsResource* resource;
        CHECK_CU(cudaGraphicsGLRegisterImage(&resource, gl_texture, GL_TEXTURE_2D, cudaGraphicsRegisterFlagsWriteDiscard));

        cudaArray_t texture_ptr;
        CHECK_CU(cudaGraphicsMapResources(1, &resource));
        CHECK_CU(cudaGraphicsSubResourceGetMappedArray(&texture_ptr, resource, 0, 0));

        callback(texture_ptr);

        CHECK_CU(cudaGraphicsUnmapResources(1, &resource));
        CHECK_CU(cudaGraphicsUnregisterResource(resource));
    }

    /// Copies the given DeviceImage to the target OpenGL texture.
    template<uint32_t FORMAT, typename DATA_TYPE>
    void copy_cuda_image_to_gl_texture(const DeviceImage<FORMAT, DATA_TYPE>& cu_image, GLuint gl_texture)
    {
        cuda_access_gl_texture(gl_texture, [&](cudaArray_t texture_ptr)
        {
            CHECK_CU(cudaMemcpy2DToArray(
                    texture_ptr, 0, 0,
                    cu_image.m_data,
                    cu_image.m_width * cu_image.pixel_size(),  // spitch (tightly packed)
                    cu_image.m_width * cu_image.pixel_size(),  // width
                    cu_image.m_height,
                    cudaMemcpyDeviceToDevice));
        });
    }

    template<uint32_t FORMAT, typename DATA_TYPE>
    GLuint create_gl_texture_from_cuda_image(const DeviceImage<FORMAT, DATA_TYPE>& cu_image, bool copy_content = true)
    {
        static_assert(FORMAT == 4, "Only RGBA images are supported");
        static_assert(sizeof(DATA_TYPE) == 1, "Only 8 bits per channel pixels are supported");

        GLuint gl_texture;
        glGenTextures(1, &gl_texture);
        glBindTexture(GL_TEXTURE_2D, gl_texture);

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, cu_image.m_width, cu_image.m_height, GL_NONE, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);

        glBindTexture(GL_TEXTURE_2D, 0);

        if (copy_content) copy_cuda_image_to_gl_texture(cu_image, gl_texture);

        return gl_texture;
    }
#endif
}
