#pragma once

#include <glm/glm.hpp>
#include <imgui.h>

namespace lego_builder
{
class BrickColorsWindow
{
public:
    /* Similarity test */
    glm::vec3 query_color = glm::vec3(0);
    int closest_cid = -1;

    bool is_opened = false;

    explicit BrickColorsWindow();
    ~BrickColorsWindow() = default;

    void ui_color_list();
    void ui_color_similarity_test();
    void ui();
};
} // namespace lego_builder
