#include "GBuffer.hpp"

#include <glm/glm.hpp>

#include "gl_helpers.hpp"
#include "util/exceptions.h"

using namespace lego_builder;

GBuffer::GBuffer(int width, int height) :
    m_width(width),
    m_height(height)
{
    glGenFramebuffers(1, &m_framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, m_framebuffer);

    // Position attachment
    glGenTextures(1, &m_position_texture);
    glBindTexture(GL_TEXTURE_2D, m_position_texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, m_width, m_height, 0, GL_RGBA, GL_FLOAT, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_position_texture, 0);

    // Normal attachment
    glGenTextures(1, &m_normal_texture);
    glBindTexture(GL_TEXTURE_2D, m_normal_texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, m_width, m_height, 0, GL_RGBA, GL_FLOAT, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT1, GL_TEXTURE_2D, m_normal_texture, 0);

    // Albedo attachment
    glGenTextures(1, &m_albedo_texture);
    glBindTexture(GL_TEXTURE_2D, m_albedo_texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, m_width, m_height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT2, GL_TEXTURE_2D, m_albedo_texture, 0);

    unsigned int attachments[3] = { GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1, GL_COLOR_ATTACHMENT2 };
    glDrawBuffers(3, attachments);

    // Renderbuffer
    glGenTextures(1, &m_depth_buffer);
    glBindTexture(GL_TEXTURE_2D, m_depth_buffer);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT, m_width, m_height, 0, GL_DEPTH_COMPONENT, GL_FLOAT, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, m_depth_buffer, 0);

    GLenum framebuffer_status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (framebuffer_status != GL_FRAMEBUFFER_COMPLETE)
    {
        printf("[ERROR] [GBuffer] Framebuffer not complete: %d\n", framebuffer_status);
        CHECK_STATE(!(framebuffer_status != GL_FRAMEBUFFER_COMPLETE));
    }

    printf("[DEBUG] [GBuffer] Framebuffer ready\n");

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

GBuffer::~GBuffer()
{
    glDeleteFramebuffers(1, &m_framebuffer);
    glDeleteRenderbuffers(1, &m_depth_buffer);
    glDeleteTextures(1, &m_position_texture);
    glDeleteTextures(1, &m_normal_texture);
    glDeleteTextures(1, &m_albedo_texture);
}

void GBuffer::clear()
{
    glm::vec4 value{};
    value = glm::vec4(std::numeric_limits<float>::infinity());
    glClearTexImage(m_position_texture, 0, GL_RGBA, GL_FLOAT, &value);
    glClearTexImage(m_normal_texture, 0, GL_RGBA, GL_FLOAT, nullptr);
    glClearTexImage(m_albedo_texture, 0, GL_RGBA, GL_FLOAT, nullptr);
}
