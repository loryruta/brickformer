#pragma once

#include <raylib.h>

#include "DeviceImage.cuh"

namespace lego_builder
{
    class App
    {
    private:
        Texture m_color_map_texture;

        // A device image that is used e.g. to temporarily store placement image before transferring to GL texture
        DeviceImage<4, uint8_t>* m_tmp_image;

        Texture m_cur_placement_map_texture;
        Texture m_prv_placement_map_texture;

    public:
        explicit App();
        ~App();

        [[nodiscard]] bool should_close() const;

        void set_color_map(const ColorMapT* d_color_map);
        void set_placement_map(const PlacementMapT* d_placement_map);

        void draw();
    };
}