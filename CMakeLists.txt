cmake_minimum_required(VERSION 3.25)

set(CMAKE_CUDA_ARCHITECTURES 75)

# Important: nvcc requires GNU version <= 12
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -ccbin ${CMAKE_CXX_COMPILER}")

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
#   set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -G -g")
endif()

set(CMAKE_CXX_STANDARD 20)

project(lego_builder LANGUAGES C CXX CUDA)

# -----------------------------------------------------------------------------------------------
# External libraries
# -----------------------------------------------------------------------------------------------

# bvh
add_subdirectory(external/bvh)

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

# GLM
add_library(glm INTERFACE)
target_include_directories(glm INTERFACE external/glm)

# raylib
set(BUILD_EXAMPLES OFF)
add_subdirectory(external/raylib)

# stb
add_library(stb INTERFACE)
target_include_directories(stb INTERFACE external/stb)

# tinygltf
option(TINYGLTF_BUILD_LOADER_EXAMPLE  OFF)
option(TINYGLTF_BUILD_GL_EXAMPLES OFF)
option(TINYGLTF_BUILD_VALIDATOR_EXAMPLE OFF)
option(TINYGLTF_BUILD_BUILDER_EXAMPLE OFF)
option(TINYGLTF_HEADER_ONLY OFF)
option(TINYGLTF_INSTALL OFF)
add_subdirectory(external/tinygltf)

# -----------------------------------------------------------------------------------------------
# Targets
# -----------------------------------------------------------------------------------------------

# lego_builder_lib
add_library(lego_builder_lib INTERFACE
        src/bricks.cuh
        src/DeviceImage.cuh
        src/misc.cuh
        src/primitives.cuh
)

target_link_libraries(lego_builder_lib INTERFACE CCCL::CCCL)
target_link_libraries(lego_builder_lib INTERFACE glm)
target_link_libraries(lego_builder_lib INTERFACE raylib)
target_link_libraries(lego_builder_lib INTERFACE stb)

# lego_builder
add_executable(lego_builder
        src/App.cu
        src/App.cuh
        src/main.cu
        src/StopWatch.hpp)

target_link_libraries(lego_builder PRIVATE lego_builder_lib)

# lego_builder_test
add_executable(lego_builder_test
        test/main.cu
)

target_include_directories(lego_builder_test PRIVATE ./src)
target_link_libraries(lego_builder_test PRIVATE lego_builder_lib)

# slicer
add_subdirectory(src/slicer)
