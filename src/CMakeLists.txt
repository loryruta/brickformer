

add_library(arpenteur STATIC
        AssignPlacementColor.cu
        AssignPlacementColor.h
        io/BrickModelIO.cu
        io/BrickModelIO.h
        BrickColors.cu
        BrickColors.h
        Converter.cu
        Converter.h
        ConverterListener.h
        model/DeviceModel.cu
        model/GltfLoader.cpp
        model/Model.cpp
        PlacementSolver.cu
        Slicer.cu
        SpreadValue.cu
        User.cu
        User.h
)

target_include_directories(arpenteur PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(arpenteur PUBLIC CCCL::CCCL glm stb tinyformat tinygltf)
# It's important for the Firebase dependencies to be in this order!
target_link_libraries(arpenteur PUBLIC
        firebase_firestore
        firebase_auth
        firebase_app
        pugixml
        secret-1
        staticZipper
        tbb # To use e.g. std parallel foreach
)

if (NOT LEGO_BUILDER_NO_VIDEO)
    add_subdirectory(ui)
    add_subdirectory(video)
endif ()

add_subdirectory(voxel)
add_subdirectory(headless)
