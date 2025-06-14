#pragma once

namespace lego_builder
{
// Forward decl
class MainScreen;

class ViewConversionWindow
{
private:
    MainScreen& m_parent;

public:
    /// The last subslice displayed (bottom-up).
    int current_subslice = 0;
    /// If the conversion is running, the current subslice will automatically update to catch the conversion.
    bool current_subslice_catch_conversion = true;

    explicit ViewConversionWindow(MainScreen& parent);
    ~ViewConversionWindow() = default;

    void ui();
};
} // namespace lego_builder
