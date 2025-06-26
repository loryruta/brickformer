from os import path
import json

#
# Download colors.csv from here:
# https://rebrickable.com/colors/
# https://rebrickable.com/downloads/ -> colors.csv
#

SCRIPT_DIR = path.dirname(path.realpath(__file__))

"""Design IDs mapping to BIDs used by BrickFormer.
Some design IDs are repeated because they map to different rotations of the same LEGO brick."""
DESIGN_IDS = [
    3005,  # 1x1
    3004,  # 1x2
    3004,  # 1x2
    2357,  # 2x2 corner
    2357,  # 2x2 corner
    2357,  # 2x2 corner
    2357,  # 2x2 corner
    3003,  # 2x2
    3622,  # 1x3
    3622,  # 1x3
    3002,  # 2x3
    3002,  # 2x3
    3010,  # 1x4
    3010,  # 1x4
    3001,  # 2x4
    3001,  # 2x4
    3009,  # 1x6
    3009,  # 1x6
    44237,  # 2x6
    44237,  # 2x6
    3007,  # 2x8
    3007,  # 2x8
]

EXCLUDED_COLOR_IDS = {
    9, 11, 12, 17, 21, 23, 60, 61, 62, 63, 64, 75, 76, 77, 79, 80, 81, 82, 100, 110, 115, 120, 132, 133, 134, 137, 142,
    148, 150, 178, 183, 216, 232, 297, 313, 366, 373, 383, 450, 503, 1000, 1001, 1007, 1008, 1009, 1010, 1011, 1012,
    1013, 1014, 1015, 1016, 1017, 1018, 1019, 1020, 1021, 1022, 1023, 1024, 1025, 1026, 1027, 1028, 1029, 1030, 1031,
    1032, 1033, 1034, 1035, 1036, 1037, 1038, 1039, 1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049, 1063,
    1064, 1065, 1066, 1067, 1068, 1069, 1070, 1071, 1072, 1073, 1074, 1075, 1076, 1077, 1078, 1079, 1080, 1081, 1082,
    1083, 1084, 1085, 1086, 1087, 1088, 1089, 1090, 1092, 1093, 1094, 1100, 1101, 1103, 1104, 1105, 1106, 1107, 1108,
    1109, 1110, 1111, 1112, 1113, 1114, 1115, 1116, 1117, 1118, 1119, 1120, 1121, 1122, 1123, 1124, 1125, 1126, 1127,
    1128, 1129, 1130, 1131, 1132, 1133, 1134, 1135, 1137, 1138, 1140, 1141, 1142, 1143, 1144, 1145
}


def parse_colors_csv():
    colors_filepath = path.join(SCRIPT_DIR, "colors.csv")
    with open(colors_filepath) as f:
        headers = f.readline().strip().split(",")
        assert headers == ['id', 'name', 'rgb', 'is_trans', 'num_parts', 'num_sets', 'y1', 'y2']
        colors = {}
        while True:
            line = f.readline().strip()
            if not line:
                break
            tokens = line.split(",")
            id_ = int(tokens[0])
            if id_ == -1 or id_ == 9999 or (id_ in EXCLUDED_COLOR_IDS):  # 9999 = No Color/Any Color
                continue
            name = tokens[1]
            rgb = int(tokens[2], 16)
            is_trans = tokens[3] == 'True'
            # num_parts = int(tokens[4])
            # num_sets = int(tokens[5])
            y1 = int(tokens[6]) if tokens[6] else None
            y2 = int(tokens[7]) if tokens[7] else None
            if is_trans or (y1 is None) or (y2 is None) or (y2 < 2018):
                continue
            colors[id_] = (name, rgb, y1, y2)
    return colors


def parse_colors_json():
    colors_filepath = path.join(SCRIPT_DIR, "colors.json")
    colors = {}
    with open(colors_filepath) as f:
        content = json.load(f)
        for i, color in enumerate(content["results"]):
            if color["is_trans"]:
                continue
            id_ = color["id"]
            if (id_ == -1) or (id_ == 9999) or (id_ in EXCLUDED_COLOR_IDS):
                continue
            name = color["name"]
            entry = {
                "id": id_,
                "name": name,
                "rgb": int(color["rgb"], 16)
            }
            external_ids = color["external_ids"]
            if "LEGO" in external_ids:
                lego = external_ids["LEGO"]
                entry["lego_id"] = lego["ext_ids"][0]
                entry["lego_name"] = lego["ext_descrs"][0][0]
            else:
                entry["lego_id"] = id_
                entry["lego_name"] = name
            colors[id_] = entry
    return colors


def parse_elements():
    elements_filepath = path.join(SCRIPT_DIR, "elements.csv")
    with open(elements_filepath) as f:
        headers = f.readline().strip().split(",")
        assert headers == ['element_id', 'part_num', 'color_id', 'design_id']
        elements = {}
        while True:
            line = f.readline().strip()
            if not line:
                break
            tokens = line.split(",")
            element_id = int(tokens[0])
            part_num = tokens[1]
            color_id = int(tokens[2])
            if tokens[3].isnumeric():
                design_id = int(tokens[3])
            elif part_num.isnumeric():
                # Recover Design ID from part_num
                design_id = int(part_num)
            else:
                continue
            if design_id not in DESIGN_IDS:
                continue
            elements[(design_id, color_id)] = element_id
    return elements


def generate_header_file():
    colors = parse_colors_json()
    elements = parse_elements()

    content = """#pragma once
    
// Auto-generated file. Do not edit!

#include <cinttypes>
#include <cstdint>

#include <glm/glm.hpp>

namespace bf
{
struct BrickColor {
    uint32_t id;
    const char* name;
    uint32_t rgb;
    uint32_t lego_id;
    const char* lego_name;
};

const BrickColor k_brick_colors[] = {\n"""
    for _, color in colors.items():
        content += "    BrickColor{{.id = {}, .name = \"{}\", .rgb = 0x{:06X}, .lego_id = {}, .lego_name = \"{}\"}},\n".format(
            color["id"], color["name"], color["rgb"], color["lego_id"], color["lego_name"]
        )
    content += "};\n"

    content += f"constexpr std::size_t k_num_brick_colors = {len(colors)};\n\n"

    # Write k_brick_colors_data
    def write_brick_colors(var_name: str, var_type: str, out_content: str):
        out_content += f"const {var_type} {var_name}[] = {{\n"
        for _, color in colors.items():
            rgb = color["rgb"]
            r_float = float((rgb >> 16) & 0xFF)
            g_float = float((rgb >> 8) & 0xFF)
            b_float = float(rgb & 0xFF)
            out_content += f"   {{{r_float}f, {g_float}f, {b_float}f}},\n"
        out_content += "};\n\n"
        return out_content

    # For GPU
    content += "__constant__\n"
    content = write_brick_colors("k_brick_colors_rgb_d", "float3", content)
    # For host
    content = write_brick_colors("k_brick_colors_rgb", "glm::vec3", content)

    design_ids_set = set(DESIGN_IDS)
    design_id_color_ids = {}
    for (design_id, color_id) in elements.keys():
        if design_id in design_ids_set:
            if design_id not in design_id_color_ids:
                design_id_color_ids[design_id] = set({})
            design_id_color_ids[design_id].add(color_id)

    # Count how many bricks have the color ID
    color_id_count = {}
    for color_id, color in colors.items():
        color_id_count[color_id] = 0
        for design_id, color_ids in design_id_color_ids.items():
            if color_id in color_ids:
                color_id_count[color_id] += 1

    # Warn about colors that have zero or very few bricks
    unpopular_color_ids = []
    for color_id, count in color_id_count.items():
        color_name = colors[color_id]["name"]
        if count == 0 or count == 1:
            unpopular_color_ids.append(color_id)
            print(f"[WARN ] Color {color_name} #{color_id} is present in _only_ {count}/{len(design_ids_set)} bricks")
    # print(sorted(unpopular_color_ids))

    # ----------------------------------------------------------------
    # Write k_lego_element_ids
    content += f"const uint64_t k_lego_element_ids[{len(DESIGN_IDS)} /* k_num_bricks */][k_num_brick_colors] = {{\n"
    for design_id in DESIGN_IDS:
        content += "    {"
        for i, (color_id, _) in enumerate(colors.items()):
            if (design_id, color_id) in elements:
                content += (str(elements[(design_id, color_id)]) + "ull").rjust(15) + ","
            else:
                content += "UINT64_MAX".rjust(15) + ","
        content += "},\n"
    content += "};\n"

    # ----------------------------------------------------------------
    # Write k_brick_colors_mask
    content += f"const bool k_brick_colors_mask[{len(DESIGN_IDS)} /* k_num_bricks */][k_num_brick_colors] = {{\n"
    for design_id in DESIGN_IDS:
        content += "    {"
        for i, (color_id, _) in enumerate(colors.items()):
            if (design_id, color_id) in elements:
                content += " true,"
            else:
                content += "false,"
        content += "},\n"
    content += "};\n"

    content += "}\n"

    return content


def _main():
    header_file_content = generate_header_file()
    header_filepath = path.join(SCRIPT_DIR, "lego_dataset.h")
    with open(header_filepath, "w") as f:
        f.write(header_file_content)


if __name__ == "__main__":
    _main()
