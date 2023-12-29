

add_library(arpenteur STATIC
    model/DeviceModel.cu
    model/DeviceModel.cuh
    model/GltfLoader.cpp
    model/GltfLoader.hpp
    model/Model.cpp
    model/Model.hpp

    util/intersections.cuh
    util/StopWatch.hpp

    Arpenteur.cu
    Arpenteur.cuh
    ArpenteurListener.hpp
    bricks.cuh
    DeviceImage.cuh
    misc.cuh
    primitives.cuh
    reward_func.cuh
    Slicer.cu
    Slicer.cuh
    SpreadValue.cu
    SpreadValue.cuh
    types.hpp
    )

target_include_directories(arpenteur PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(arpenteur PUBLIC CCCL::CCCL)
target_link_libraries(arpenteur PUBLIC glm)
target_link_libraries(arpenteur PUBLIC stb)
target_link_libraries(arpenteur PUBLIC tinygltf)

add_subdirectory(ui)
