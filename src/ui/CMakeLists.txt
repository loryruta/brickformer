
add_executable(arpenteur_ui
    main.cu
    App.cu
    BrickModelBuilder.cpp
    ui.cpp
    View3dWindow.cpp
    )

target_link_libraries(arpenteur_ui PRIVATE nfd)

target_link_libraries(arpenteur_ui PRIVATE arpenteur)
target_link_libraries(arpenteur_ui PRIVATE arpenteur_video)
