cmake_minimum_required(VERSION 3.27)

set(CMAKE_CUDA_ARCHITECTURES 75)

# Important: nvcc requires GNU version <= 12
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -ccbin ${CMAKE_CXX_COMPILER}")

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -G -g")
endif()

set(CMAKE_CXX_STANDARD 20)

project(lego_builder LANGUAGES CUDA CXX)


add_executable(lego_builder
        src/main.cu
        src/bricks.cuh
        src/exceptions.hpp
        src/misc.hpp
)

target_include_directories(lego_builder PRIVATE ./external/stb)
target_include_directories(lego_builder PRIVATE ./external/glm)

set(CCCL_ENABLE_LIBCUDACXX OFF)
set(CCCL_ENABLE_CUB ON)
set(CCCL_ENABLE_THRUST OFF)
set(CCCL_ENABLE_TESTING OFF)
set(CCCL_ENABLE_EXAMPLES OFF)
set(CCCL_ENABLE_BENCHMARKS OFF)
add_subdirectory(external/cccl)

target_link_libraries(lego_builder PRIVATE CCCL::CCCL)
