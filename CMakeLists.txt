cmake_minimum_required(VERSION 3.25)

set(CMAKE_CUDA_ARCHITECTURES 75)

# Important: nvcc 12.3 requires GNU version <= 12
# There could be situations where the system's default compiler has an incompatible version, in such cases the developer
# might explicit the compiler to use by setting CXX env variable
if (CMAKE_CXX_COMPILER)
    set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -ccbin ${CMAKE_CXX_COMPILER}")
endif()

set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} --expt-extended-lambda")

# Allow calling __host__ constexpr functions from __device__ code
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} --expt-relaxed-constexpr")

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
    # Can't debug because compute-sanitizer says:
    # Program hit cudaErrorLaunchOutOfResources (error 701) due to "too many resources requested for launch" on CUDA API call to cudaGetLastError
    set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -lineinfo")
endif()

set(CMAKE_CXX_STANDARD 20)

project(arpenteur LANGUAGES C CXX CUDA)

if (NOT LEGO_BUILDER_NO_VIDEO)
    message(STATUS "Video support is enabled")
else()
    message(STATUS "Video support is disabled (only headless target defined)")
endif()

# ------------------------------------------------------------------------------------------------
# External libraries
# ------------------------------------------------------------------------------------------------

# cccl
set(CCCL_ENABLE_LIBCUDACXX OFF)
set(CCCL_ENABLE_CUB ON)
set(CCCL_ENABLE_THRUST OFF)
set(CCCL_ENABLE_TESTING OFF)
set(CCCL_ENABLE_EXAMPLES OFF)
set(CCCL_ENABLE_BENCHMARKS OFF)
add_subdirectory(external/cccl)

if (NOT LEGO_BUILDER_NO_VIDEO)
    # glad
    add_library(glad STATIC external/glad/src/gl.c)
    target_include_directories(glad PUBLIC external/glad/include/)

    # glfw
    set(BUILD_SHARED_LIBS OFF)
    set(GLFW_BUILD_EXAMPLES OFF)
    set(GLFW_BUILD_TESTS OFF)
    set(GLFW_BUILD_DOCS OFF)
    set(GLFW_INSTALL OFF)
    add_subdirectory(external/glfw)
endif ()

# GLM
add_library(glm INTERFACE)
target_include_directories(glm INTERFACE external/glm)

# imgui
add_library(imgui STATIC
    external/imgui/imgui.cpp
    external/imgui/imgui_demo.cpp
    external/imgui/imgui_draw.cpp
    external/imgui/imgui_tables.cpp
    external/imgui/imgui_widgets.cpp
    )

target_include_directories(imgui PUBLIC external/imgui)

# nativefiledialog-extended
add_subdirectory(external/nativefiledialog-extended)

# stb
add_library(stb INTERFACE)
target_include_directories(stb INTERFACE external/stb)

# tinyformat
add_library(tinyformat INTERFACE)
target_include_directories(tinyformat INTERFACE external/tinyformat)

# tinygltf
set(TINYGLTF_BUILD_LOADER_EXAMPLE OFF)
set(TINYGLTF_BUILD_GL_EXAMPLES OFF)
set(TINYGLTF_BUILD_VALIDATOR_EXAMPLE OFF)
set(TINYGLTF_BUILD_BUILDER_EXAMPLE OFF)
set(TINYGLTF_HEADER_ONLY OFF)
set(TINYGLTF_INSTALL OFF)
add_subdirectory(external/tinygltf)

if (NOT LEGO_BUILDER_NO_VIDEO)
    # imgui backend OpenGL3+GLFW
    add_library(imgui_backend_opengl3_glfw STATIC
        external/imgui/backends/imgui_impl_opengl3.cpp
        external/imgui/backends/imgui_impl_glfw.cpp
        )

    target_include_directories(imgui_backend_opengl3_glfw PUBLIC external/imgui/backends)

    target_link_libraries(imgui_backend_opengl3_glfw PRIVATE glfw)
    target_link_libraries(imgui_backend_opengl3_glfw PRIVATE imgui)
endif ()

# ------------------------------------------------------------------------------------------------

add_subdirectory(src)
add_subdirectory(test)
