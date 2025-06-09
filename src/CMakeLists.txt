

add_library(arpenteur STATIC
        exporters/BuildInstructionsExporter.cu
        exporters/GltfExporter.cu
        model/DeviceModel.cu
        model/GltfLoader.cpp
        model/Model.cpp
        Arpenteur.cu
        PlacementSolver.cu
        Slicer.cu
        SpreadValue.cu
)

target_include_directories(arpenteur PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(arpenteur PUBLIC CCCL::CCCL glm stb tinyformat tinygltf)
# It's important for the Firebase dependencies to be in this order!
target_link_libraries(arpenteur PUBLIC
        firebase_firestore
        firebase_auth
        firebase_app
        secret-1)

if (NOT LEGO_BUILDER_NO_VIDEO)
    add_subdirectory(ui)
    add_subdirectory(video)
endif ()

add_subdirectory(voxel)
add_subdirectory(headless)
