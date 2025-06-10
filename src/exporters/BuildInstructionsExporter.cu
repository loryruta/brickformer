#include "BuildInstructionsExporter.h"

#include "bricks.hpp"

#include <stb_image_write.h>
#include <tinyformat.h>

using namespace lego_builder;

namespace
{
__global__ void
write_out_image_kernel(int pid_map_resolution, const uint16_t* pid_map, int image_resolution, uint8_t* out_image)
{
    int x = (int) (blockIdx.x * blockDim.x + threadIdx.x);
    int y = (int) (blockIdx.y * blockDim.y + threadIdx.y);
    if (x >= image_resolution || y >= image_resolution) return;
    int pmx = (int) (float(x) / float(image_resolution) * pid_map_resolution);
    int pmy = (int) (float(y) / float(image_resolution) * pid_map_resolution);
    uint16_t pid = pid_map[pmy * pid_map_resolution + pmx];
    if (pid != UINT16_MAX) {
        int out_idx = (y * image_resolution + x) * 4;
        out_image[out_idx + 0] = 255; // R
        out_image[out_idx + 1] = 255; // G
        out_image[out_idx + 2] = 0;   // B
        out_image[out_idx + 3] = 255; // A
    }
}
} // namespace

BuildInstructionsExporter::BuildInstructionsExporter(int resolution,
                                                     int image_resolution,
                                                     const std::filesystem::path& output_dir)
    : m_resolution(resolution), m_image_resolution(image_resolution), m_output_dir(output_dir)
{
    CHECK_STATE(m_resolution <= m_image_resolution);

    size_t pid_map_size = m_resolution * m_resolution;
    size_t out_image_bytesize = m_image_resolution * m_image_resolution * 4 * sizeof(uint8_t); // RGBA

    m_subslice0_pid_map.resize(pid_map_size);
    m_subslice1_pid_map.resize(pid_map_size);
    m_subslice2_pid_map.resize(pid_map_size);
    m_full_pid_map.resize(pid_map_size);

    CHECK_CU(cudaMalloc(&m_pid_map_d, pid_map_size * sizeof(uint16_t)));
    CHECK_CU(cudaMalloc(&m_out_image_d, out_image_bytesize));
}

BuildInstructionsExporter::~BuildInstructionsExporter() {}

void BuildInstructionsExporter::on_model_load(const Model& model) {}

void BuildInstructionsExporter::put_in_pid_map(uint16_t pid, const Placement& placement)
{
    auto brick = k_bricks[placement.bid];
    for (int by = 0; by < BRICK_MAX_EXTENT_Z; by++) {
        for (int bx = 0; bx < BRICK_MAX_EXTENT_X; bx++) {
            int px = placement.x + bx;
            int py = placement.z + by;
            if (brick[by][bx]) {
                CHECK_STATE(px >= 0 && px < m_resolution && py >= 0 && py < m_resolution); // No out-of-bounds
                int i = py * m_resolution + px;
                if (placement.subslice_mask == 0x7) {
                    m_full_pid_map[i] = pid;
                } else {
                    if (placement.subslice_mask & 1) m_subslice0_pid_map[i] = pid;
                    if (placement.subslice_mask & 2) m_subslice1_pid_map[i] = pid;
                    if (placement.subslice_mask & 4) m_subslice2_pid_map[i] = pid;
                }
            }
        }
    }
}

void BuildInstructionsExporter::create_and_save_instruction_image(const uint16_t* pid_map,
                                                                  const std::string& out_image_filename)
{
    size_t pid_map_bytesize = m_resolution * m_resolution * sizeof(uint16_t);
    size_t out_image_bytesize = m_image_resolution * m_image_resolution * 4 * sizeof(uint8_t); // RGBA
    // Initialize PID map and out_image on device
    CHECK_CU(cudaMemcpy(m_pid_map_d, pid_map, pid_map_bytesize, cudaMemcpyHostToDevice));
    CHECK_CU(cudaMemset(m_out_image_d, 0, out_image_bytesize));
    // Fill out_image
    dim3 num_blocks;
    num_blocks.x = div_ceil(m_image_resolution, 16);
    num_blocks.y = div_ceil(m_image_resolution, 16);
    dim3 block_dims(16, 16);
    write_out_image_kernel<<<num_blocks, block_dims>>>(m_resolution, m_pid_map_d, m_image_resolution, m_out_image_d);
    // CHECK_CU(cudaDeviceSynchronize()); // TODO NOT
    // Write out_image to the file specified
    std::vector<uint8_t> out_image(m_image_resolution * m_image_resolution * 4);
    CHECK_CU(cudaMemcpy(out_image.data(), m_out_image_d, out_image_bytesize, cudaMemcpyDeviceToHost));
    if (!std::filesystem::exists(m_output_dir)) {
        bool dir_created = std::filesystem::create_directory(m_output_dir);
        CHECK_STATE(dir_created, "Couldn't create output directory: %s", m_output_dir.string().c_str());
    }
    std::filesystem::path image_filepath = m_output_dir / out_image_filename;
    int write_result = stbi_write_png(
        image_filepath.c_str(), m_image_resolution, m_image_resolution, 4, out_image.data(), 0 /* Tightly packed */);
    CHECK_STATE(write_result, "stbi_write_png failed");
    printf("[DEBUG] [BuildInstructionsExporter] Image written %s\n", image_filepath.c_str());
}

void BuildInstructionsExporter::on_placement_begin(uint32_t y) { m_current_pid = 0; }

void BuildInstructionsExporter::on_placement_end(uint32_t slice_y, const std::vector<Placement>& placements)
{
    // Clear PID maps
    size_t pid_map_bytesize = m_resolution * m_resolution * sizeof(uint16_t);
    memset(m_subslice0_pid_map.data(), ~0, pid_map_bytesize);
    memset(m_subslice1_pid_map.data(), ~0, pid_map_bytesize);
    memset(m_subslice2_pid_map.data(), ~0, pid_map_bytesize);
    memset(m_full_pid_map.data(), ~0, pid_map_bytesize);

    // Fill PID maps
    for (const Placement& placement : placements) {
        put_in_pid_map(m_current_pid, placement);
        ++m_current_pid;
        CHECK_STATE(m_current_pid <= UINT16_MAX);
    }

    // Create & save instruction images
    create_and_save_instruction_image(m_subslice0_pid_map.data(), tfm::format("%05d_a_subslice0.png", slice_y));
    create_and_save_instruction_image(m_subslice1_pid_map.data(), tfm::format("%05d_b_subslice1.png", slice_y));
    create_and_save_instruction_image(m_subslice2_pid_map.data(), tfm::format("%05d_c_subslice2.png", slice_y));
    create_and_save_instruction_image(m_full_pid_map.data(), tfm::format("%05d_d_full.png", slice_y));

    // TODO update PDF
}
