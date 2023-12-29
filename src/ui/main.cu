#include "App.cuh"

#include "video/gl_helpers.hpp"

using namespace lego_builder;

int main(int argc, char* argv[])
{
    // Initialize GLFW
    if (!glfwInit())
    {
        fprintf(stderr, "Couldn't initialize GLFW\n");
        exit(1);
    }

    Window window(500, 500, "l'Arpenteur");

    // Initialize GL
    int version = gladLoadGL(glfwGetProcAddress);
    if (version <= 0)
    {
        fprintf(stderr, "Couldn't initialize GL\n");
        exit(1);
    }

    enable_gl_debug_output();

    // Start the app
    std::unique_ptr<App> app = std::make_unique<App>(window);
    app->run();

    //
    app.reset();

    glfwTerminate();

    return 0;
}
