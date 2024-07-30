

add_library(arpenteur STATIC
    exporters/OutputToGltf.cu
    model/DeviceModel.cu
    model/GltfLoader.cpp
    model/Model.cpp
    Arpenteur.cu
    Slicer.cu
    SpreadValue.cu
)

target_include_directories(arpenteur PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(arpenteur PUBLIC CCCL::CCCL)
target_link_libraries(arpenteur PUBLIC glm)
target_link_libraries(arpenteur PUBLIC stb)
target_link_libraries(arpenteur PUBLIC tinygltf)

if (NOT LEGO_BUILDER_NO_VIDEO)
    add_subdirectory(ui)
    add_subdirectory(video)
endif()

add_subdirectory(voxel)
add_subdirectory(headless)
