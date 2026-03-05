#pragma once

#include "rdp_common.hpp"
#include "rdp_data_structures.hpp"

namespace RDP::detail
{
template <typename FlagT, typename MaskT>
inline void update_masked_flag(FlagT &flags, bool enabled, MaskT mask)
{
	const FlagT mask_bits = static_cast<FlagT>(mask);
	flags &= ~mask_bits;
	if (enabled)
		flags |= mask_bits;
}

inline bool apply_set_other_modes_words(StaticRasterizationState &static_state,
                                        DepthBlendState &depth_blend,
                                        uint32_t word0,
                                        uint32_t word1)
{
	update_masked_flag(static_state.flags, bool(word0 & (1u << 19)), RASTERIZATION_PERSPECTIVE_CORRECT_BIT);
	update_masked_flag(static_state.flags, bool(word0 & (1u << 18)), RASTERIZATION_DETAIL_LOD_ENABLE_BIT);
	update_masked_flag(static_state.flags, bool(word0 & (1u << 17)), RASTERIZATION_SHARPEN_LOD_ENABLE_BIT);
	update_masked_flag(static_state.flags, bool(word0 & (1u << 16)), RASTERIZATION_TEX_LOD_ENABLE_BIT);
	update_masked_flag(static_state.flags, bool(word0 & (1u << 15)), RASTERIZATION_TLUT_BIT);
	update_masked_flag(static_state.flags, bool(word0 & (1u << 14)), RASTERIZATION_TLUT_TYPE_BIT);
	update_masked_flag(static_state.flags, bool(word0 & (1u << 13)), RASTERIZATION_SAMPLE_MODE_BIT);
	update_masked_flag(static_state.flags, bool(word0 & (1u << 12)), RASTERIZATION_SAMPLE_MID_TEXEL_BIT);
	update_masked_flag(static_state.flags, bool(word0 & (1u << 11)), RASTERIZATION_BILERP_0_BIT);
	update_masked_flag(static_state.flags, bool(word0 & (1u << 10)), RASTERIZATION_BILERP_1_BIT);
	update_masked_flag(static_state.flags, bool(word0 & (1u << 9)), RASTERIZATION_CONVERT_ONE_BIT);

	update_masked_flag(depth_blend.flags, bool(word1 & (1u << 14)), DEPTH_BLEND_FORCE_BLEND_BIT);
	update_masked_flag(static_state.flags, bool(word1 & (1u << 13)), RASTERIZATION_ALPHA_CVG_SELECT_BIT);
	update_masked_flag(static_state.flags, bool(word1 & (1u << 12)), RASTERIZATION_CVG_TIMES_ALPHA_BIT);
	update_masked_flag(depth_blend.flags, bool(word1 & (1u << 7)), DEPTH_BLEND_COLOR_ON_COVERAGE_BIT);
	update_masked_flag(depth_blend.flags, bool(word1 & (1u << 6)), DEPTH_BLEND_IMAGE_READ_ENABLE_BIT);
	update_masked_flag(depth_blend.flags, bool(word1 & (1u << 5)), DEPTH_BLEND_DEPTH_UPDATE_BIT);
	update_masked_flag(depth_blend.flags, bool(word1 & (1u << 4)), DEPTH_BLEND_DEPTH_TEST_BIT);
	update_masked_flag(static_state.flags, bool(word1 & (1u << 3)), RASTERIZATION_AA_BIT);
	update_masked_flag(depth_blend.flags, bool(word1 & (1u << 3)), DEPTH_BLEND_AA_BIT);
	update_masked_flag(static_state.flags, bool(word1 & (1u << 1)), RASTERIZATION_ALPHA_TEST_DITHER_BIT);
	update_masked_flag(static_state.flags, bool(word1 & (1u << 0)), RASTERIZATION_ALPHA_TEST_BIT);

	static_state.dither = (word0 >> 4) & 0x0fu;
	update_masked_flag(depth_blend.flags,
	                   RGBDitherMode(static_state.dither >> 2) != RGBDitherMode::Off,
	                   DEPTH_BLEND_DITHER_ENABLE_BIT);
	depth_blend.coverage_mode = static_cast<CoverageMode>((word1 >> 8) & 3);
	depth_blend.z_mode = static_cast<ZMode>((word1 >> 10) & 3);

	static_state.flags &= ~(RASTERIZATION_MULTI_CYCLE_BIT |
	                        RASTERIZATION_FILL_BIT |
	                        RASTERIZATION_COPY_BIT);
	depth_blend.flags &= ~DEPTH_BLEND_MULTI_CYCLE_BIT;

	switch (CycleType((word0 >> 20) & 3))
	{
	case CycleType::Cycle2:
		static_state.flags |= RASTERIZATION_MULTI_CYCLE_BIT;
		depth_blend.flags |= DEPTH_BLEND_MULTI_CYCLE_BIT;
		break;

	case CycleType::Fill:
		static_state.flags |= RASTERIZATION_FILL_BIT;
		break;

	case CycleType::Copy:
		static_state.flags |= RASTERIZATION_COPY_BIT;
		break;

	default:
		break;
	}

	depth_blend.blend_cycles[0].blend_1a = static_cast<BlendMode1A>((word1 >> 30) & 3);
	depth_blend.blend_cycles[1].blend_1a = static_cast<BlendMode1A>((word1 >> 28) & 3);
	depth_blend.blend_cycles[0].blend_1b = static_cast<BlendMode1B>((word1 >> 26) & 3);
	depth_blend.blend_cycles[1].blend_1b = static_cast<BlendMode1B>((word1 >> 24) & 3);
	depth_blend.blend_cycles[0].blend_2a = static_cast<BlendMode2A>((word1 >> 22) & 3);
	depth_blend.blend_cycles[1].blend_2a = static_cast<BlendMode2A>((word1 >> 20) & 3);
	depth_blend.blend_cycles[0].blend_2b = static_cast<BlendMode2B>((word1 >> 18) & 3);
	depth_blend.blend_cycles[1].blend_2b = static_cast<BlendMode2B>((word1 >> 16) & 3);

	return bool(word1 & (1u << 2));
}
}
