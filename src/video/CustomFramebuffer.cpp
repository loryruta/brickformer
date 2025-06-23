#include "CustomFramebuffer.hpp"

#include <cassert>

using namespace lego_builder;

CustomFramebuffer::CustomFramebuffer(int width, int height)
    : m_width(width), m_height(height), m_aspect_ratio(float(width) / float(height))
{
    // Generate framebuffer
    glGenFramebuffers(1, &m_framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, m_framebuffer);

    // Generate texture
    glGenTextures(1, &m_texture);
    glBindTexture(GL_TEXTURE_2D, m_texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, m_width, m_height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);

    // Generate renderbuffer (for depth)
    glGenRenderbuffers(1, &m_renderbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, m_renderbuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT, m_width, m_height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, m_renderbuffer);

    //
    glFramebufferTexture(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, m_texture, 0);

    GLenum draw_buffers[]{GL_COLOR_ATTACHMENT0};
    glDrawBuffers(1, draw_buffers);

    GLenum framebuffer_status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    assert(framebuffer_status == GL_FRAMEBUFFER_COMPLETE);
}

CustomFramebuffer::~CustomFramebuffer()
{
    glDeleteTextures(1, &m_texture);
    glDeleteRenderbuffers(1, &m_renderbuffer);
    glDeleteFramebuffers(1, &m_framebuffer);
}

void CustomFramebuffer::render(const RenderFuncT& render_func) const
{
    // Save current state
    GLint old_framebuffer;
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &old_framebuffer);
    GLint old_viewport[4];
    glGetIntegerv(GL_VIEWPORT, old_viewport);

    //
    glBindFramebuffer(GL_FRAMEBUFFER, m_framebuffer);
    glViewport(0, 0, m_width, m_height);

    render_func();

    // Restore old state
    glBindFramebuffer(GL_FRAMEBUFFER, old_framebuffer);
    glViewport(old_viewport[0], old_viewport[1], old_viewport[2], old_viewport[3]);
}
