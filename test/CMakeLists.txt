

add_executable(arpenteur_test main.cu)

add_executable(arpenteur_spreadvalue SpreadValue_main.cu)
target_link_libraries(arpenteur_spreadvalue PRIVATE arpenteur)
