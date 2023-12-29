
add_executable(arpenteur_ui
    video/Camera.cpp
    video/Camera.hpp
    video/cuda_interop_helpers.cu
    video/cuda_interop_helpers.cuh
    video/gl_helpers.cpp
    video/gl_helpers.hpp
    video/ModelRenderer.cpp
    video/ModelRenderer.hpp
    video/TextureRenderer.cpp
    video/TextureRenderer.hpp
    video/ViewModelApp.cpp
    video/ViewModelApp.hpp
    video/Window.cpp
    video/Window.hpp

    main.cu
        App.cuh
        App.cu
        Queue.hpp
        video/CustomFramebuffer.hpp
        video/CustomFramebuffer.cpp
)

target_link_libraries(arpenteur_ui PRIVATE arpenteur)

target_link_libraries(arpenteur_ui PRIVATE glad)
target_link_libraries(arpenteur_ui PRIVATE glfw)
target_link_libraries(arpenteur_ui PRIVATE imgui)
target_link_libraries(arpenteur_ui PRIVATE imgui_backend_opengl3_glfw)

