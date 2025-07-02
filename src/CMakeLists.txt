

add_executable(BrickFormer
        io/BrickModelIO.cu
        io/BrickModelIO.h

        model/DeviceModel.cu
        model/DeviceModel.h
        model/GltfLoader.cpp
        model/GltfLoader.h
        model/Model.cpp
        model/Model.h

        ui/windows/BrickColorsWindow.cu
        ui/windows/BrickColorsWindow.h
        ui/windows/BrickModelWindow.cu
        ui/windows/BrickModelWindow.h
        ui/windows/ConversionWindow.cu
        ui/windows/ConversionWindow.h
        ui/windows/InputWindow.cu
        ui/windows/InputWindow.h
        ui/windows/UserWindow.cu
        ui/windows/UserWindow.h
        ui/windows/View3dWindow.cpp
        ui/windows/View3dWindow.h
        ui/App.cu
        ui/App.h
        ui/AuthScreen.cu
        ui/AuthScreen.h
        ui/MainScreen.cu
        ui/MainScreen.h
        ui/ConverterVisualizationBridge.cu
        ui/ConverterVisualizationBridge.h
        ui/main.cu
        ui/Screen.h
        ui/UIStyle.cpp
        ui/UIStyle.h

        util/exceptions.h
        util/external_libs.cpp
        util/intersections.h
        util/json.hpp
        util/misc.h
        util/misc_cuda.h
        util/Queue.h
        util/StaticVector.h
        util/StopWatch.h
        util/str_utils.h

        video/BoxFilter.cpp
        video/BoxFilter.hpp
        video/BrickPlaneRenderer.cpp
        video/BrickPlaneRenderer.h
        video/BrickRenderer.cpp
        video/BrickRenderer.h
        video/Camera.cpp
        video/Camera.hpp
        video/cuda_interop_helpers.cu
        video/gl_helpers.cpp
        video/GridRenderer.cpp
        video/ModelRenderer.cpp
        video/TextureRenderer.cpp
        video/Window.cpp
        video/CustomFramebuffer.cpp
        video/GBuffer.cpp
        video/ScreenQuad.cpp
        video/SSAOPass.cpp
        video/VoxelModelBuilder.cpp

        AssignPlacementColor.cu
        AssignPlacementColor.h
        BrickColors.cu
        BrickColors.h
        BrickFormerAPI.cu
        BrickFormerAPI.h
        BrickModel.cu
        BrickModel.h
        bricks.h
        Converter.cu
        Converter.h
        ConverterListener.h
        DeviceImage.h
        lego_dataset.h
        log.h
        PaidPlan.h
        PlacementSolver.cu
        PlacementSolver.h
        primitives.h
        Slicer.cu
        Slicer.h
        SpreadValue.cu
        SpreadValue.h
        User.cu
        User.h
        SyncDaemon.cu
        SyncDaemon.h
        util/external_libs.cpp
)

target_include_directories(BrickFormer PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${Stb_INCLUDE_DIR}
        ${TINYGLTF_INCLUDE_DIRS}
)
target_link_libraries(BrickFormer PUBLIC
        # It's important for the Firebase dependencies to be in this order!
        CURL::libcurl
        firebase_auth
        firebase_app
        glad
        glfw
        glm::glm
        ZLIB::ZLIB
        imgui::imgui
        nfd::nfd
        pugixml::pugixml
        staticZipper
        tinyformat
)

if (UNIX)
    # Firebase dependencies in Linux
    target_link_libraries(BrickFormer PRIVATE secret-1)
    # To use e.g. std parallel foreach
    target_link_libraries(BrickFormer PRIVATE tbb)
elseif (MSVC)
    # Firebase dependencies in Windows
    target_link_libraries(BrickFormer PRIVATE advapi32 ws2_32 crypt32 iphlpapi psapi userenv dbghelp bcrypt)
endif ()

# ----------------------------------------------------------------
# Copy assets
# ----------------------------------------------------------------

set(BF_ASSETS_DIR ${CMAKE_SOURCE_DIR}/assets)
add_custom_command(
        TARGET BrickFormer
        POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory ${BF_ASSETS_DIR} $<TARGET_FILE_DIR:BrickFormer>/assets
        COMMENT "Copying assets folder"
)
add_custom_target(BrickFormer_copy_assets ALL DEPENDS ${ASSETS_DST_DIR})
add_dependencies(BrickFormer BrickFormer_copy_assets)
