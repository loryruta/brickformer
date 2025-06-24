#pragma once

#include <filesystem>
#include <string>

#include <glm/glm.hpp>

namespace bf
{
// Forward decl
class MainScreen;

class InputWindow
{
private:
    MainScreen& m_parent;

public:
    std::filesystem::path model_path{};
    int resolution = 40;
    bool flip_x = false;
    bool flip_y = false;
    bool flip_z = false;
    int up_axis = 1; ///< 0 = +X, 1 = +Y, 2 = +Z
    float alpha_test_threshold = 0.7f;
    bool auto_proximity = true;
    int proximity_threshold = UINT8_MAX;
    int proximity_max_value = 1;

    explicit InputWindow(MainScreen& parent) : m_parent(parent) {}
    ~InputWindow() = default;

    void ui();

    [[nodiscard]] glm::mat4 model_orientation() const;

    void browse_model();
    void import_brickformer_construction();
};
} // namespace bf