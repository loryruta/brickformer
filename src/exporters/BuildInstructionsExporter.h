#pragma once

#include "ArpenteurListener.hpp"

#include <filesystem>

namespace lego_builder
{
class BuildInstructionsExporter : public ArpenteurListener
{
private:
    const int m_resolution;
    const int m_image_resolution;
    const std::filesystem::path m_output_dir;

    std::vector<uint16_t> m_full_pid_map;
    std::vector<uint16_t> m_subslice0_pid_map;
    std::vector<uint16_t> m_subslice1_pid_map;
    std::vector<uint16_t> m_subslice2_pid_map;

    uint16_t* m_pid_map_d;
    uint8_t* m_out_image_d;

    std::vector<Placement> m_current_subslice_placements;
    std::vector<Placement> m_full_placements;

    size_t m_current_pid = 0;

public:
    explicit BuildInstructionsExporter(int resolution, int image_resolution, const std::filesystem::path& output_dir);
    ~BuildInstructionsExporter();

    void on_model_load(const Model& model) override;
    void on_placement_begin(uint32_t slice_y) override;
    void on_placement_end(uint32_t slice_y, const std::vector<Placement>& placements) override;

    void put_in_pid_map(uint16_t pid, const Placement& placement);
    void create_and_save_instruction_image(const uint16_t* pid_map, const std::string& out_image_filename);
};
} // namespace lego_builder
