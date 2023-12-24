#include "ViewModelApp.hpp"

#include <glm/gtc/matrix_transform.hpp>

using namespace lego_builder;

ViewModelApp::ViewModelApp(Window& window, const Model& model, const glm::vec3& orbit_center, const glm::vec3& cam_position, float cam_speed) :
    m_window(window)
{
    m_baked_model = std::make_unique<BakedModel>(m_model_renderer.bake_model(model));

    m_orbit_center = orbit_center;
    m_cam_speed = cam_speed;

    m_camera.m_position = cam_position;
    m_camera.look_at(m_orbit_center);
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

        m_camera.m_position += m_camera.right() * dt * m_cam_speed;
        m_camera.look_at(m_orbit_center);

        glClearColor(0, 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        m_model_renderer.render(*m_baked_model, m_camera, glm::identity<glm::mat4>());

        m_window.end_frame();
    }

    return m_window.should_close();
}
