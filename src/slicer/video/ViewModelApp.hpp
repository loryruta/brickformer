#pragma once

#include <memory>

#include "Window.hpp"
#include "ModelRenderer.hpp"

namespace lego_builder
{
    class ViewModelApp
    {
    private:
        Window& m_window;

        std::unique_ptr<BakedModel> m_baked_model;
        ModelRenderer m_model_renderer;

        /// Matrix used to scale the model to a fixed size (e.g. (0,0,0) and (1,1,1)).
        glm::mat4 m_model_norm_transform;

        Camera m_camera;

    public:
        explicit ViewModelApp(Window& window, const Model& model);
        ~ViewModelApp() = default;

        bool run();
    };
}
