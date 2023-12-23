#include "ViewModelApp.hpp"

#include <glm/gtc/matrix_transform.hpp>

using namespace lego_builder;

ViewModelApp::ViewModelApp(Window& window, const Model& model) :
    m_window(window)
{
    m_baked_model = std::make_unique<BakedModel>(m_model_renderer.bake_model(model));

    glm::vec3 model_size = model.m_transformed_max - model.m_transformed_min;
    float max_side = glm::max(model_size.x, glm::max(model_size.y, model_size.z));

    // Matrix to fit the model within (-0.5, -0.5, -0.5) to (0.5, 0.5, 0.5)
    m_model_norm_transform = glm::identity<glm::mat4>();
    m_model_norm_transform = glm::scale(m_model_norm_transform, glm::vec3(1.0f / max_side));
    m_model_norm_transform = glm::translate(m_model_norm_transform, -model.m_transformed_min - model_size / 2.0f);

    m_camera.m_position = glm::vec3(0.0f, 0.45f, -1.8f);
    m_camera.look_at(glm::vec3(0));
}

bool ViewModelApp::run()
{
    float prev_t = glfwGetTime();

    while (!m_window.should_close())
    {
        m_window.begin_frame();

        float now_t = glfwGetTime();
        float dt = now_t - prev_t;
        prev_t = now_t;

        const float k_camera_speed = 2.4f;

        m_camera.m_position += m_camera.right() * dt * k_camera_speed;
        m_camera.look_at(glm::vec3(0));

        glClearColor(0, 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        m_model_renderer.render(*m_baked_model, m_camera, m_model_norm_transform);

        m_window.end_frame();
    }

    return m_window.should_close();
}
