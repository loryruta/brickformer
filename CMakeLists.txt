cmake_minimum_required(VERSION 3.25)

set(CMAKE_CUDA_ARCHITECTURES 75)

# Important: nvcc 12.3 requires GNU version <= 12
# There could be situations where the system's default compiler has an incompatible version, in such cases the developer
# might explicit the compiler to use by setting CXX env variable
if (CMAKE_CXX_COMPILER)
    set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -ccbin \"${CMAKE_CXX_COMPILER}\"")
endif ()

project(BrickFormer LANGUAGES C CXX CUDA)

set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} --expt-extended-lambda")

# Allow calling __host__ constexpr functions from __device__ code
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} --expt-relaxed-constexpr")

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
    # Can't debug because compute-sanitizer says:
    # Program hit cudaErrorLaunchOutOfResources (error 701) due to "too many resources requested for launch" on CUDA API call to cudaGetLastError
    set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -lineinfo")
endif ()

set(CMAKE_CXX_STANDARD 20)

if (MSVC)
    # To make preprocessing work the same way as in GCC/Clang
    add_compile_options(-Zc:preprocessor)
endif ()

# ------------------------------------------------------------------------------------------------
# External libraries
# ------------------------------------------------------------------------------------------------

# cccl
#set(CCCL_ENABLE_LIBCUDACXX OFF)
#set(CCCL_ENABLE_CUB ON)
#set(CCCL_ENABLE_THRUST OFF)
#set(CCCL_ENABLE_TESTING OFF)
#set(CCCL_ENABLE_EXAMPLES OFF)
#set(CCCL_ENABLE_BENCHMARKS OFF)
#add_subdirectory(external/cccl)

# glad
add_library(glad STATIC external/glad/src/gl.c)
target_include_directories(glad PUBLIC external/glad/include/)

# glfw3
find_package(glfw3 CONFIG REQUIRED)

# Firebase SDK
#
# Reference:
# https://github.com/firebase/quickstart-cpp/
#
# Windows runtime mode, either MD or MT depending on whether you are using
# /MD or /MT. For more information see:
# https://msdn.microsoft.com/en-us/library/2kzt1wy3.aspx
#
if (MSVC)
    set(MSVC_RUNTIME_MODE MD)
endif ()
set(FIREBASE_CPP_SDK_DIR ${CMAKE_CURRENT_SOURCE_DIR}/external/firebase_cpp_sdk)
add_subdirectory(${FIREBASE_CPP_SDK_DIR} bin/ EXCLUDE_FROM_ALL)

# GLM
find_package(glm CONFIG REQUIRED)
add_compile_definitions(-DGLM_ENABLE_EXPERIMENTAL)
# Suppress the warning:
# warning #20012-D: __host__ annotation is ignored on a function("vec") that is explicitly defaulted on its first declaration
#  		__declspec(__device__) __declspec(__host__)  vec() = default ;
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -diag-suppress 20012")

# zlib
find_package(ZLIB REQUIRED)

# imgui
find_package(imgui CONFIG REQUIRED)

# nativefiledialog-extended
find_package(nfd CONFIG REQUIRED)

# pugixml
find_package(pugixml CONFIG REQUIRED)

# stb
find_package(Stb REQUIRED)

# tinyformat
add_library(tinyformat INTERFACE)
target_include_directories(tinyformat INTERFACE external/tinyformat)

# tinygltf
find_path(TINYGLTF_INCLUDE_DIRS "tiny_gltf.h")

# Zipper
add_subdirectory(external/zipper)

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
#add_subdirectory(test)
