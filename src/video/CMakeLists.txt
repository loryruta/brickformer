add_library(arpenteur_video STATIC
    Camera.cpp
    cuda_interop_helpers.cu
    gl_helpers.cpp
    ModelRenderer.cpp
    TextureRenderer.cpp
    Window.cpp
    CustomFramebuffer.cpp
    VoxelModelBuilder.cpp
    )

# TODO objective is to make this a self-contained module that can potentially be used in other projects.
#  TODO Now this is not possible due to Model class (that is outside)
target_link_libraries(arpenteur_video PUBLIC arpenteur)

target_link_libraries(arpenteur_video PUBLIC glad)
target_link_libraries(arpenteur_video PUBLIC glfw)
target_link_libraries(arpenteur_video PUBLIC imgui)
target_link_libraries(arpenteur_video PUBLIC imgui_backend_opengl3_glfw)
