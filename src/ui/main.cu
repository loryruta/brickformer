#include "App.h"

#include <nfd.h>

#include "video/gl_helpers.hpp"

using namespace lego_builder;

int main(int argc, char* argv[])
{
    NFD_Init();

    // Initialize GLFW
    if (!glfwInit()) {
        fprintf(stderr, "Couldn't initialize GLFW\n");
        exit(1);
    }

    Window window = Window::create_fullscreen("BrickFormer");

    // Initialize GL
    int version = gladLoadGL(glfwGetProcAddress);
    if (version <= 0) {
        fprintf(stderr, "Couldn't initialize GL\n");
        exit(1);
    }

    enable_gl_debug_output();
    // Increase printf buffer size for debugging purposes (CUDA)
    CHECK_CU(cudaDeviceSetLimit(cudaLimitPrintfFifoSize, size_t(1) << 30 /* 1GB */));
    printf("[DEBUG] Device capabilities:\n");
    size_t printf_buffer_size{};
    CHECK_CU(cudaDeviceGetLimit(&printf_buffer_size, cudaLimitPrintfFifoSize));
    printf("[DEBUG]   cudaLimitPrintfFifoSize: %zu KB\n", printf_buffer_size >> 10);

    // Start the app
    std::unique_ptr<App> app = std::make_unique<App>(window);
    app->start();

    //
    app.reset();

    glfwTerminate();

    NFD_Quit();

    return 0;
}
