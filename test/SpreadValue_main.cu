#include <stb_image.h>
#include <stb_image_write.h>

#include "PlacementSolver.cuh"
#include "SpreadValue.cuh"
#include "resources.hpp"

// TODO Use Catch2

using namespace lego_builder;

template<uint32_t FORMAT, typename DATA_TYPE>
void write_image_to_png(const char* filename, const DeviceImage<FORMAT, DATA_TYPE>& image)
{
    std::vector<uint8_t> data(image.data_size());
    CHECK_CU(cudaMemcpy(data.data(), image.m_data, image.data_size(), cudaMemcpyKind::cudaMemcpyDeviceToHost));
    stbi_write_png(filename, image.width(), image.height(), FORMAT, data.data(), 0 /* Tightly packed */);
}

void test_color_map_coverage_kernel()
{
    using namespace internal;

    // TODO Make a RAII wrapper for Device objects?

    ColorMapT color_map = ColorMapT::create(16, 16, resources::g_color_map1);
    ColorMapT* color_map_d = to_device(color_map);
    ColorMapCoverageResult* color_map_coverage_d{};
    CHECK_CU(cudaMalloc(&color_map_coverage_d, sizeof(ColorMapCoverageResult)));
    Placement* placement_d{};
    CHECK_CU(cudaMalloc(&placement_d, sizeof(Placement)));
    Placement placement{};
    ColorMapCoverageResult color_map_coverage{};

    /* Test 1 */
    placement.m_bid = 1;
    placement.m_x = 0;
    placement.m_y = 0;
    CHECK_CU(cudaMemcpy(placement_d, &placement, sizeof(Placement), cudaMemcpyHostToDevice));
    internal::eval_color_map_coverage_kernel<<<1, 32>>>(placement_d, 1, color_map_d, color_map_coverage_d);
    CHECK_CU(cudaDeviceSynchronize());
    color_map_coverage = to_host(color_map_coverage_d);
    CHECK_STATE(color_map_coverage.num_covered_cells == 2);
    CHECK_STATE(color_map_coverage.color_distance == 155);

    /* Test 2 */
    placement.m_bid = 1;
    placement.m_x = 1;
    placement.m_y = 0;
    CHECK_CU(cudaMemcpy(placement_d, &placement, sizeof(Placement), cudaMemcpyHostToDevice));
    internal::eval_color_map_coverage_kernel<<<1, 32>>>(placement_d, 1, color_map_d, color_map_coverage_d);
    CHECK_CU(cudaDeviceSynchronize());
    color_map_coverage = to_host(color_map_coverage_d);
    CHECK_STATE(color_map_coverage.num_covered_cells == 1);
    CHECK_STATE(color_map_coverage.color_distance == 0);

    /* Test 3 */
    placement.m_bid = 16;
    placement.m_x = 6;
    placement.m_y = 6;
    CHECK_CU(cudaMemcpy(placement_d, &placement, sizeof(Placement), cudaMemcpyHostToDevice));
    internal::eval_color_map_coverage_kernel<<<1, 32>>>(placement_d, 1, color_map_d, color_map_coverage_d);
    CHECK_CU(cudaDeviceSynchronize());
    color_map_coverage = to_host(color_map_coverage_d);
    CHECK_STATE(color_map_coverage.num_covered_cells == 6);
    CHECK_STATE(color_map_coverage.color_distance == 123);

    CHECK_CU(cudaFree(color_map_coverage_d));
    CHECK_CU(cudaFree(color_map_d));
    CHECK_CU(cudaFree(placement_d));
}

int main(int argc, char* argv[])
{
    SpreadValue spread_value;

    DeviceImage<1, uint8_t> image1 = DeviceImage<1, uint8_t>::create(512, 512, nullptr);
    image1.write_pixel(128, 128, glm::vec<1, uint8_t>(64));
    image1.write_pixel(32, 32, glm::vec<1, uint8_t>(128));
    spread_value.spread(image1, 128);
    write_image_to_png("image1.png", image1);

    test_color_map_coverage_kernel();

    return 0;
}
