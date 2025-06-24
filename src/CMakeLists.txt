

add_executable(BrickFormer
        io/BrickModelIO.cu
        io/BrickModelIO.h

        model/DeviceModel.cu
        model/GltfLoader.cpp
        model/Model.cpp

        ui/App.cu
        ui/App.h
        ui/AuthScreen.cu
        ui/AuthScreen.h
        ui/BrickColorsWindow.cu
        ui/BrickColorsWindow.h
        ui/MainScreen.cu
        ui/MainScreen.h
        ui/Queue.h
        ui/BrickModelBuilder.cu
        ui/BrickModelBuilder.h
        ui/ConversionWindow.cu
        ui/ConversionWindow.h
        ui/ConverterVisualizationBridge.cu
        ui/ConverterVisualizationBridge.h
        ui/InputWindow.cu
        ui/InputWindow.h
        ui/main.cu
        ui/Screen.h
        ui/UIStyle.cpp
        ui/UIStyle.h
        ui/UserWindow.cu
        ui/UserWindow.h
        ui/View3dWindow.cpp
        ui/View3dWindow.h
        ui/BrickModelWindow.cu
        ui/BrickModelWindow.h

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
        Converter.cu
        Converter.h
        ConverterListener.h
        PlacementSolver.cu
        Slicer.cu
        SpreadValue.cu
        User.cu
        User.cu
        UserSyncDaemon.cu
        UserSyncDaemon.h
)

target_include_directories(BrickFormer PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

# It's important for the Firebase dependencies to be in this order!
target_link_libraries(BrickFormer PUBLIC
        CCCL::CCCL
        firebase_firestore
        firebase_auth
        firebase_app
        glad
        glfw
        glm
        imgui
        imgui_backend_opengl3_glfw
        nfd
        pugixml
        secret-1
        staticZipper
        stb
        tbb # To use e.g. std parallel foreach
        tinyformat
        tinygltf
)
