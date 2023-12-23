#pragma once

#include <glm/glm.hpp>

namespace lego_builder
{
    struct Camera
    {
        glm::vec3 m_position = {0.0f, 0.0f, 0.0f};
        float m_yaw = 0.0f;
        float m_pitch = 0.0f;

        float m_fov_y = glm::radians(45.0f);
        float m_aspect_ratio = 1.0f;
        float m_near_plane = 0.01f;
        float m_far_plane = 1000.0f;

        [[nodiscard]] glm::vec3 right() const;
        [[nodiscard]] glm::vec3 up() const;
        [[nodiscard]] glm::vec3 forward() const;

        [[nodiscard]] glm::mat4 orientation() const;

        [[nodiscard]] glm::mat4 view() const;
        [[nodiscard]] glm::mat4 projection() const;
        [[nodiscard]] glm::mat4 matrix() const;

        void look_at(const glm::vec3& position);
    };
}