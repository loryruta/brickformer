
add_executable(arpenteur_ui
    main.cu
    App.cuh
    App.cu
    Queue.hpp
    BrickModelBuilder.cpp
    brick_models.hpp
    )

target_link_libraries(arpenteur_ui PRIVATE arpenteur)
target_link_libraries(arpenteur_ui PRIVATE arpenteur_video)
