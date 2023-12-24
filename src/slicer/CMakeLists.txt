

add_executable(slicer main.cu
        Model.hpp
        GltfLoader.cpp
        GltfLoader.hpp
        video/ModelRenderer.cpp
        video/ModelRenderer.hpp
        video/Camera.hpp
        video/ViewModelApp.hpp
        video/ViewModelApp.cpp
        video/Window.hpp
        video/Window.cpp
        video/Camera.cpp
        video/gl_helpers.cpp
        video/gl_helpers.hpp
        DeviceModel.cuh
        DeviceModel.cu
        intersections.cuh
        video/TextureRenderer.hpp
        video/TextureRenderer.cpp

        Slicer.cu
        Slicer.cuh
        Model.cpp
        video/cuda_interop_helpers.cuh
        video/cuda_interop_helpers.cu

)

target_include_directories(slicer PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(slicer PRIVATE glad)
target_link_libraries(slicer PRIVATE glfw)
target_link_libraries(slicer PRIVATE glm)
target_link_libraries(slicer PRIVATE CCCL::CCCL)
target_link_libraries(slicer PRIVATE tinygltf)
