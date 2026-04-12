from dotenv import load_dotenv

load_dotenv()

import json
import os
from os import path
import requests
from requests_oauthlib import OAuth1


SCRIPT_DIR = path.dirname(path.realpath(__file__))
ROOT_DIR = path.abspath(path.join(SCRIPT_DIR, os.pardir))


def generate_header_file(color_list) -> str:
    content = """#pragma once

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
        // result.a = 0;
        return result;
    } 
};

// Reference:
// https://www.bricklink.com/catalogColors.asp?v=1&itemType=P&itemNo=

__constant__
const BrickColor k_brick_colors[] = {
"""
    color_list = [color for color in color_list if color['color_type'] in ['Solid']]
    for color in color_list:
        content += "BrickColor{.bl_id = %d, .name = \"%s\", .rgb = 0x%s},\n" % (
            color['color_id'], color['color_name'], color['color_code']
        )
    print(f"Number of colors found: {len(color_list)}")
    content += """};
}
    """
    return content


def _main():
    auth = OAuth1(
        os.environ["BRICKLINK_CONSUMER_KEY"],
        os.environ["BRICKLINK_CONSUMER_SECRET"],
        os.environ["BRICKLINK_TOKEN_VALUE"],
        os.environ["BRICKLINK_TOKEN_SECRET"],
    )
    endpoint = os.environ["BRICKLINK_ENDPOINT"]
    response = requests.request("GET", f"{endpoint}/colors", auth=auth)
    if response.status_code != 200:
        raise Exception(f"HTTP request failed with status code: {response.status_code}")
    response_json = json.loads(response.content)
    assert 'meta' in response_json
    assert response_json['meta']['code'] == 200

    with open(path.join(ROOT_DIR, "./src/brick_colors.hpp"), "wt") as f:
        color_list = response_json['data']
        f.write(generate_header_file(color_list))


if __name__ == "__main__":
    _main()
