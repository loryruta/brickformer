#pragma once

// Auto-generated file

namespace lego_builder
{
struct BrickColor
{
    int bl_id;
    char const* name;
    int rgb;

    __host__ __device__
    inline glm::vec<4, uint8_t> color_u8() const
    {
        glm::vec<4, uint8_t> result{};
        result.r = (rgb >> 16) & 0xFF;
        result.g = (rgb >> 8) & 0xFF;
        result.b = rgb & 0xFF;
        result.a = 0xFF;
        return result;
    } 
};

// Reference:
// https://www.bricklink.com/catalogColors.asp?v=1&itemType=P&itemNo=

__constant__
const BrickColor k_brick_colors[] = {
BrickColor{.bl_id = 1, .name = "White", .rgb = 0xFFFFFF},
BrickColor{.bl_id = 49, .name = "Very Light Gray", .rgb = 0xE8E8E8},
BrickColor{.bl_id = 99, .name = "Very Light Bluish Gray", .rgb = 0xE4E8E8},
BrickColor{.bl_id = 86, .name = "Light Bluish Gray", .rgb = 0xAFB5C7},
BrickColor{.bl_id = 9, .name = "Light Gray", .rgb = 0x9C9C9C},
BrickColor{.bl_id = 10, .name = "Dark Gray", .rgb = 0x6B5A5A},
BrickColor{.bl_id = 85, .name = "Dark Bluish Gray", .rgb = 0x595D60},
BrickColor{.bl_id = 11, .name = "Black", .rgb = 0x212121},
BrickColor{.bl_id = 59, .name = "Dark Red", .rgb = 0x6A0E15},
BrickColor{.bl_id = 5, .name = "Red", .rgb = 0xB30006},
BrickColor{.bl_id = 167, .name = "Reddish Orange", .rgb = 0xFF5500},
BrickColor{.bl_id = 231, .name = "Dark Salmon", .rgb = 0xFF6326},
BrickColor{.bl_id = 25, .name = "Salmon", .rgb = 0xFF7D5D},
BrickColor{.bl_id = 220, .name = "Coral", .rgb = 0xFF8172},
BrickColor{.bl_id = 26, .name = "Light Salmon", .rgb = 0xFCC7B7},
BrickColor{.bl_id = 58, .name = "Sand Red", .rgb = 0xC58D80},
BrickColor{.bl_id = 120, .name = "Dark Brown", .rgb = 0x50372F},
BrickColor{.bl_id = 168, .name = "Umber", .rgb = 0x735442},
BrickColor{.bl_id = 8, .name = "Brown", .rgb = 0x6B3F22},
BrickColor{.bl_id = 88, .name = "Reddish Brown", .rgb = 0x82422A},
BrickColor{.bl_id = 91, .name = "Light Brown", .rgb = 0x99663E},
BrickColor{.bl_id = 240, .name = "Medium Brown", .rgb = 0xA16C42},
BrickColor{.bl_id = 106, .name = "Fabuland Brown", .rgb = 0xB3694E},
BrickColor{.bl_id = 69, .name = "Dark Tan", .rgb = 0xB89869},
BrickColor{.bl_id = 2, .name = "Tan", .rgb = 0xEED9A4},
BrickColor{.bl_id = 90, .name = "Light Nougat", .rgb = 0xFECCB0},
BrickColor{.bl_id = 241, .name = "Medium Tan", .rgb = 0xFBC685},
BrickColor{.bl_id = 28, .name = "Nougat", .rgb = 0xFFAF7D},
BrickColor{.bl_id = 150, .name = "Medium Nougat", .rgb = 0xE3A05B},
BrickColor{.bl_id = 225, .name = "Dark Nougat", .rgb = 0xCE7942},
BrickColor{.bl_id = 169, .name = "Sienna", .rgb = 0xEA8339},
BrickColor{.bl_id = 160, .name = "Fabuland Orange", .rgb = 0xEF9121},
BrickColor{.bl_id = 29, .name = "Earth Orange", .rgb = 0xE6881D},
BrickColor{.bl_id = 68, .name = "Dark Orange", .rgb = 0xB35408},
BrickColor{.bl_id = 27, .name = "Rust", .rgb = 0xB24817},
BrickColor{.bl_id = 165, .name = "Neon Orange", .rgb = 0xFA5947},
BrickColor{.bl_id = 4, .name = "Orange", .rgb = 0xFF7E14},
BrickColor{.bl_id = 31, .name = "Medium Orange", .rgb = 0xFFA531},
BrickColor{.bl_id = 32, .name = "Light Orange", .rgb = 0xFFBC36},
BrickColor{.bl_id = 110, .name = "Bright Light Orange", .rgb = 0xFFC700},
BrickColor{.bl_id = 96, .name = "Very Light Orange", .rgb = 0xFFDCA4},
BrickColor{.bl_id = 161, .name = "Dark Yellow", .rgb = 0xDD982E},
BrickColor{.bl_id = 3, .name = "Yellow", .rgb = 0xFFE001},
BrickColor{.bl_id = 33, .name = "Light Yellow", .rgb = 0xFEE89F},
BrickColor{.bl_id = 103, .name = "Bright Light Yellow", .rgb = 0xFFF08C},
BrickColor{.bl_id = 236, .name = "Neon Yellow", .rgb = 0xFFFC00},
BrickColor{.bl_id = 166, .name = "Neon Green", .rgb = 0xDBF355},
BrickColor{.bl_id = 35, .name = "Light Lime", .rgb = 0xECEEBD},
BrickColor{.bl_id = 158, .name = "Yellowish Green", .rgb = 0xE7F2A7},
BrickColor{.bl_id = 76, .name = "Medium Lime", .rgb = 0xDFE000},
BrickColor{.bl_id = 34, .name = "Lime", .rgb = 0xC4E000},
BrickColor{.bl_id = 248, .name = "Fabuland Lime", .rgb = 0xADD237},
BrickColor{.bl_id = 155, .name = "Olive Green", .rgb = 0xABA953},
BrickColor{.bl_id = 242, .name = "Dark Olive Green", .rgb = 0x76753F},
BrickColor{.bl_id = 80, .name = "Dark Green", .rgb = 0x2E5543},
BrickColor{.bl_id = 6, .name = "Green", .rgb = 0x00923D},
BrickColor{.bl_id = 36, .name = "Bright Green", .rgb = 0x10CB31},
BrickColor{.bl_id = 37, .name = "Medium Green", .rgb = 0x91DF8C},
BrickColor{.bl_id = 38, .name = "Light Green", .rgb = 0xD7EED1},
BrickColor{.bl_id = 48, .name = "Sand Green", .rgb = 0xA2BFA3},
BrickColor{.bl_id = 39, .name = "Dark Turquoise", .rgb = 0x00A29F},
BrickColor{.bl_id = 40, .name = "Light Turquoise", .rgb = 0x00C5BC},
BrickColor{.bl_id = 41, .name = "Aqua", .rgb = 0xBCE5DC},
BrickColor{.bl_id = 152, .name = "Light Aqua", .rgb = 0xCFEFEA},
BrickColor{.bl_id = 63, .name = "Dark Blue", .rgb = 0x243757},
BrickColor{.bl_id = 7, .name = "Blue", .rgb = 0x0057A6},
BrickColor{.bl_id = 153, .name = "Dark Azure", .rgb = 0x009FE0},
BrickColor{.bl_id = 247, .name = "Little Robots Blue", .rgb = 0x5DBFE4},
BrickColor{.bl_id = 72, .name = "Maersk Blue", .rgb = 0x7DC1D8},
BrickColor{.bl_id = 156, .name = "Medium Azure", .rgb = 0x6ACEE0},
BrickColor{.bl_id = 87, .name = "Sky Blue", .rgb = 0x8AD4E1},
BrickColor{.bl_id = 42, .name = "Medium Blue", .rgb = 0x82ADD8},
BrickColor{.bl_id = 105, .name = "Bright Light Blue", .rgb = 0xBCD1ED},
BrickColor{.bl_id = 62, .name = "Light Blue", .rgb = 0xC8D9E1},
BrickColor{.bl_id = 55, .name = "Sand Blue", .rgb = 0x8899AB},
BrickColor{.bl_id = 109, .name = "Dark Blue-Violet", .rgb = 0x2032B0},
BrickColor{.bl_id = 43, .name = "Violet", .rgb = 0x3448A4},
BrickColor{.bl_id = 97, .name = "Blue-Violet", .rgb = 0x506CEF},
BrickColor{.bl_id = 245, .name = "Lilac", .rgb = 0x7862CE},
BrickColor{.bl_id = 73, .name = "Medium Violet", .rgb = 0x9391E4},
BrickColor{.bl_id = 246, .name = "Light Lilac", .rgb = 0xCDCCEE},
BrickColor{.bl_id = 44, .name = "Light Violet", .rgb = 0xC9CAE2},
BrickColor{.bl_id = 89, .name = "Dark Purple", .rgb = 0x5F2683},
BrickColor{.bl_id = 24, .name = "Purple", .rgb = 0x7A238D},
BrickColor{.bl_id = 93, .name = "Light Purple", .rgb = 0xAF3195},
BrickColor{.bl_id = 157, .name = "Medium Lavender", .rgb = 0xC689D9},
BrickColor{.bl_id = 154, .name = "Lavender", .rgb = 0xD3BDE3},
BrickColor{.bl_id = 227, .name = "Clikits Lavender", .rgb = 0xE0AAD9},
BrickColor{.bl_id = 54, .name = "Sand Purple", .rgb = 0xB57DA5},
BrickColor{.bl_id = 71, .name = "Magenta", .rgb = 0xB72276},
BrickColor{.bl_id = 47, .name = "Dark Pink", .rgb = 0xEF5BB3},
BrickColor{.bl_id = 94, .name = "Medium Dark Pink", .rgb = 0xF785B1},
BrickColor{.bl_id = 104, .name = "Bright Pink", .rgb = 0xF7BCDA},
BrickColor{.bl_id = 23, .name = "Pink", .rgb = 0xF5CDD6},
BrickColor{.bl_id = 56, .name = "Light Pink", .rgb = 0xF2D3D1},
};
}
    