#pragma once

#include <memory>

#include "ModelRenderer.hpp"
#include "Window.hpp"

namespace lego_builder
{
    class ViewModelApp
    {
    private:
        Window& m_window;

        std::unique_ptr<BakedModel> m_baked_model;
        ModelRenderer m_model_renderer;

        glm::vec3 m_orbit_center;
        float m_cam_speed;

        Camera m_camera;

    public:
        explicit ViewModelApp(Window& window, const Model& model, const glm::vec3& orbit_center, const glm::vec3& cam_position, float cam_speed);
        ~ViewModelApp() = default;

        bool run();
    };
}
