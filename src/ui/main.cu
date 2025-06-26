#include "App.h"

#include <nfd.h>

#include "log.h"
#include "video/gl_helpers.hpp"

#define ARP_LOG_CONTEXT "main"

using namespace bf;

int main(int argc, char* argv[])
{
    ARP_INFO("BrickFormer build information:");
    ARP_INFO("  Git version:          %s", BF_GIT_VERSION);
    ARP_INFO("  Git version full:     %s", BF_GIT_VERSION_FULL);
    ARP_INFO("  Git commit hash:      %s", BF_GIT_COMMIT_HASH);
    ARP_INFO("  Git commit timestamp: %s", BF_GIT_COMMIT_TIMESTAMP);

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
    ARP_DEBUG("Device capabilities:");
    size_t printf_buffer_size{};
    CHECK_CU(cudaDeviceGetLimit(&printf_buffer_size, cudaLimitPrintfFifoSize));
    ARP_DEBUG("  cudaLimitPrintfFifoSize: %zu KB", printf_buffer_size >> 10);

    // Start the app
    try {
        std::unique_ptr<App> app = std::make_unique<App>(window);
        app->start();
        app.reset();
    } catch (std::exception& exception) {
        fprintf(stderr, "BrickFormer thrown an exception:\n%s", exception.what());
        exit(100);
    }

    glfwTerminate();

    NFD_Quit();

    return 0;
}
