#include "BrickColors.h"

#include "User.h"
#include "bricks.h"
#include "lego_dataset.h"
#include "log.h"
#include "util/exceptions.h"
#include "util/misc_cuda.h"

#define ARP_LOG_CONTEXT "BrickColors"

using namespace bf;

namespace
{
std::unique_ptr<BrickColors> g_brick_colors; // Singleton, lazily initialized
} // namespace

BrickColors::BrickColors()
{
    m_enabled_colors.resize(k_num_brick_colors, true);

    m_color_mask_all_bricks.resize(k_num_brick_colors, false);
    m_color_masks.resize(k_num_bricks * k_num_brick_colors, false);

    CHECK_CU(cudaMalloc(&m_color_masks_d, m_color_masks.size() * sizeof(bool)));
}

BrickColors::~BrickColors()
{
    if (m_color_masks_d) {
        CHECK_CU(cudaFree(m_color_masks_d));
        m_color_masks_d = nullptr;
    }
}

void BrickColors::upload_colors()
{
    const PaidPlan* plan = User::get()->copy().plan();

    for (int cid = 0; cid < k_num_brick_colors; ++cid) {
        bool enabled = true;
        enabled &= m_enabled_colors.at(cid);
        enabled &= plan->is_brick_color_allowed(cid); // Allowed by the paid plan
        m_color_mask_all_bricks[cid] = enabled;
        for (int bid = 0; bid < k_num_bricks; ++bid) {
            // Check if the combination Design ID + color ID exists
            bool exists = k_brick_colors_mask[bid][cid];
            m_color_masks[bid * k_num_brick_colors + cid] = exists && enabled;
        }
    }

    // Validate before uploading
    for (int bid = 0; bid < k_num_bricks; ++bid) {
        bool at_least_one = false;
        for (int cid = 0; cid < k_num_brick_colors; ++cid) {
            if (m_color_masks[bid * k_num_brick_colors + cid]) {
                at_least_one = true;
                break;
            }
        }
        if (!at_least_one) {
            throw IllegalStateException(
                "BID %d (Design ID: %d) doesn't have any enabled color", bid, k_brick_design_ids[bid]);
        }
    }
    // Upload color masks to GPU
    CHECK_CU(
        cudaMemcpy(m_color_masks_d, m_color_masks.data(), m_color_masks.size() * sizeof(bool), cudaMemcpyHostToDevice));

    m_has_uploaded = true;
}

bool BrickColors::is_enabled(int cid) const { return m_enabled_colors.at(cid); }

void BrickColors::set_enabled(int cid, bool flag) { m_enabled_colors[cid] = flag; }

BrickColors& BrickColors::get()
{
    if (!g_brick_colors) g_brick_colors = std::make_unique<BrickColors>();
    return *g_brick_colors;
}
