#include <stb_image_write.h>
#include "SpreadValue.cuh"

using namespace lego_builder;

template<uint32_t FORMAT, typename DATA_TYPE>
void write_image_to_png(const char* filename, const DeviceImage<FORMAT, DATA_TYPE>& image)
{
    std::vector<uint8_t> data(image.data_size());
    CHECK_CU(cudaMemcpy(data.data(), image.m_data, image.data_size(), cudaMemcpyKind::cudaMemcpyDeviceToHost));
    stbi_write_png(filename, image.width(), image.height(), FORMAT, data.data(), 0 /* Tightly packed */);
}

int main(int argc, char* argv[]) {
    SpreadValue spread_value;

    DeviceImage<1, uint8_t> image1 = DeviceImage<1, uint8_t>::create(512, 512, nullptr);
    image1.write_pixel(128, 128, glm::vec<1, uint8_t>(64));
    image1.write_pixel(32, 32, glm::vec<1, uint8_t>(128));
    spread_value.spread(image1, 128);
    write_image_to_png("image1.png", image1);

    return 0;
}
