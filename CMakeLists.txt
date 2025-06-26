cmake_minimum_required(VERSION 3.25)

set(CMAKE_CUDA_ARCHITECTURES 75)

# Important: nvcc 12.3 requires GNU version <= 12
# There could be situations where the system's default compiler has an incompatible version, in such cases the developer
# might explicit the compiler to use by setting CXX env variable
if (CMAKE_CXX_COMPILER)
    set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -ccbin ${CMAKE_CXX_COMPILER}")
endif ()

set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} --expt-extended-lambda")

# Allow calling __host__ constexpr functions from __device__ code
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} --expt-relaxed-constexpr")

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
    # Can't debug because compute-sanitizer says:
    # Program hit cudaErrorLaunchOutOfResources (error 701) due to "too many resources requested for launch" on CUDA API call to cudaGetLastError
    set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -lineinfo")
endif ()

set(CMAKE_CXX_STANDARD 20)

project(BrickFormer LANGUAGES C CXX CUDA)

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

# Firebase SDK
set(FIREBASE_CPP_SDK_DIR ${CMAKE_CURRENT_SOURCE_DIR}/external/firebase_cpp_sdk)
add_subdirectory(${FIREBASE_CPP_SDK_DIR} bin/ EXCLUDE_FROM_ALL)

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

# pugixml
add_subdirectory(external/pugixml)

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

# Zipper
add_subdirectory(external/zipper)

# imgui backend OpenGL3+GLFW
add_library(imgui_backend_opengl3_glfw STATIC
        external/imgui/backends/imgui_impl_opengl3.cpp
        external/imgui/backends/imgui_impl_glfw.cpp
)

target_include_directories(imgui_backend_opengl3_glfw PUBLIC external/imgui/backends)
target_link_libraries(imgui_backend_opengl3_glfw PRIVATE glfw imgui)

# ------------------------------------------------------------------------------------------------
# Compile definitions
# ------------------------------------------------------------------------------------------------

# BF_GIT_VERSION
execute_process(
        COMMAND git describe --tags --abbrev=0
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE BF_GIT_VERSION
        OUTPUT_STRIP_TRAILING_WHITESPACE
)
# BF_GIT_VERSION_FULL
execute_process(
        COMMAND git describe --tags
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE BF_GIT_VERSION_FULL
        OUTPUT_STRIP_TRAILING_WHITESPACE
)
# BF_GIT_COMMIT_HASH
execute_process(
        COMMAND git rev-parse HEAD
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE BF_GIT_COMMIT_HASH
        OUTPUT_STRIP_TRAILING_WHITESPACE
)
# BF_GIT_COMMIT_TIMESTAMP
execute_process(
        COMMAND git show -s --format=%at
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE BF_GIT_COMMIT_TIMESTAMP
        OUTPUT_STRIP_TRAILING_WHITESPACE
)

add_compile_definitions(
        -DBF_GIT_VERSION="${BF_GIT_VERSION}"
        -DBF_GIT_VERSION_FULL="${BF_GIT_VERSION_FULL}"
        -DBF_GIT_COMMIT_HASH="${BF_GIT_COMMIT_HASH}"
        -DBF_GIT_COMMIT_TIMESTAMP="${BF_GIT_COMMIT_TIMESTAMP}")

# ------------------------------------------------------------------------------------------------

add_subdirectory(src)
add_subdirectory(test)
