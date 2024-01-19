

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
    bricks.hpp
    DeviceImage.cuh
    util/misc.cuh
    primitives.cuh
    reward_func.cuh
    voxel/Slicer.cu
    voxel/Slicer.cuh
    SpreadValue.cu
    SpreadValue.cuh
    types.cuh
    ui/BrickModelBuilder.hpp
    util/misc.hpp
    colorize_placements.cuh
    util/StaticVector.cuh
)

target_include_directories(arpenteur PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(arpenteur PUBLIC CCCL::CCCL)
target_link_libraries(arpenteur PUBLIC glm)
target_link_libraries(arpenteur PUBLIC stb)
target_link_libraries(arpenteur PUBLIC tinygltf)

add_subdirectory(ui)
add_subdirectory(video)
add_subdirectory(voxel)
