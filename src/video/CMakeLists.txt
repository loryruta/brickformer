add_library(arpenteur_video STATIC
    Camera.cpp
    Camera.hpp
    cuda_interop_helpers.cu
    cuda_interop_helpers.cuh
    gl_helpers.cpp
    gl_helpers.hpp
    ModelRenderer.cpp
    ModelRenderer.hpp
    TextureRenderer.cpp
    TextureRenderer.hpp
    Window.cpp
    Window.hpp
    CustomFramebuffer.hpp
    CustomFramebuffer.cpp
    VoxelModelBuilder.hpp
    VoxelModelBuilder.cpp
    )

# TODO objective is to make this a self-contained module that can potentially be used in other projects.
#  TODO Now this is not possible due to Model class (that is outside)
target_link_libraries(arpenteur_video PUBLIC arpenteur)

target_link_libraries(arpenteur_video PUBLIC glad)
target_link_libraries(arpenteur_video PUBLIC glfw)
target_link_libraries(arpenteur_video PUBLIC imgui)
target_link_libraries(arpenteur_video PUBLIC imgui_backend_opengl3_glfw)
