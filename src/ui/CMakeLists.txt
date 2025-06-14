
add_executable(arpenteur_ui
        App.cu
        App.h
        AuthScreen.cu
        AuthScreen.h
        MainScreen.cu
        MainScreen.h
        Queue.h
        BrickModelBuilder.cu
        BrickModelBuilder.h
        ConversionWindow.cu
        ConversionWindow.h
        ConverterVisualizationBridge.cu
        ConverterVisualizationBridge.h
        main.cu
        Screen.h
        View3dWindow.cpp
        View3dWindow.h
        ViewConversionWindow.cu
        ViewConversionWindow.h
)
target_link_libraries(arpenteur_ui PRIVATE arpenteur arpenteur_video nfd)
