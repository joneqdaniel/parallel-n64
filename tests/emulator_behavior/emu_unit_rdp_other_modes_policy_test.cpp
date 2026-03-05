#include "mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_other_modes_policy.hpp"

#include <cstdlib>
#include <iostream>

using namespace RDP;

namespace
{
static void check(bool condition, const char *message)
{
	if (!condition)
	{
		std::cerr << "FAIL: " << message << std::endl;
		std::exit(1);
	}
}

static void test_cycle_type_decoding_clears_previous_mode_bits()
{
	StaticRasterizationState static_state = {};
	DepthBlendState depth_blend = {};

	static_state.flags = RASTERIZATION_MULTI_CYCLE_BIT | RASTERIZATION_FILL_BIT | RASTERIZATION_COPY_BIT;
	depth_blend.flags = DEPTH_BLEND_MULTI_CYCLE_BIT;

	detail::apply_set_other_modes_words(static_state, depth_blend, 0u, 0u);
	check((static_state.flags & (RASTERIZATION_MULTI_CYCLE_BIT | RASTERIZATION_FILL_BIT | RASTERIZATION_COPY_BIT)) == 0u,
	      "Cycle1 should clear cycle/fill/copy mode bits");
	check((depth_blend.flags & DEPTH_BLEND_MULTI_CYCLE_BIT) == 0u,
	      "Cycle1 should clear depth multi-cycle bit");

	detail::apply_set_other_modes_words(static_state, depth_blend,
	                                    (uint32_t(CycleType::Cycle2) << 20), 0u);
	check((static_state.flags & RASTERIZATION_MULTI_CYCLE_BIT) != 0u,
	      "Cycle2 should enable raster multi-cycle");
	check((depth_blend.flags & DEPTH_BLEND_MULTI_CYCLE_BIT) != 0u,
	      "Cycle2 should enable depth multi-cycle");

	detail::apply_set_other_modes_words(static_state, depth_blend,
	                                    (uint32_t(CycleType::Fill) << 20), 0u);
	check((static_state.flags & RASTERIZATION_FILL_BIT) != 0u,
	      "Fill cycle should enable fill bit");
	check((static_state.flags & RASTERIZATION_COPY_BIT) == 0u,
	      "Fill cycle should clear copy bit");
	check((static_state.flags & RASTERIZATION_MULTI_CYCLE_BIT) == 0u,
	      "Fill cycle should clear multi-cycle bit");
	check((depth_blend.flags & DEPTH_BLEND_MULTI_CYCLE_BIT) == 0u,
	      "Fill cycle should clear depth multi-cycle bit");

	detail::apply_set_other_modes_words(static_state, depth_blend,
	                                    (uint32_t(CycleType::Copy) << 20), 0u);
	check((static_state.flags & RASTERIZATION_COPY_BIT) != 0u,
	      "Copy cycle should enable copy bit");
	check((static_state.flags & RASTERIZATION_FILL_BIT) == 0u,
	      "Copy cycle should clear fill bit");
}

static void test_dither_and_coverage_decode()
{
	StaticRasterizationState static_state = {};
	DepthBlendState depth_blend = {};

	uint32_t word0 = (0xcu << 4); // RGB dither mode Off (3).
	uint32_t word1 = 0;
	word1 |= (2u << 8);  // CoverageMode::Zap
	word1 |= (3u << 10); // ZMode::Decal
	word1 |= (1u << 13); // alpha_cvg_select
	word1 |= (1u << 12); // cvg_times_alpha
	word1 |= (1u << 7);  // color on coverage
	word1 |= (1u << 6);  // image read
	word1 |= (1u << 5);  // depth update
	word1 |= (1u << 4);  // depth test
	word1 |= (1u << 3);  // AA (mirrored to both states)
	word1 |= (1u << 1);  // alpha test dither
	word1 |= (1u << 0);  // alpha test

	detail::apply_set_other_modes_words(static_state, depth_blend, word0, word1);

	check(static_state.dither == 0xcu, "dither nibble decode mismatch");
	check((depth_blend.flags & DEPTH_BLEND_DITHER_ENABLE_BIT) == 0u,
	      "RGB dither Off should disable depth dither bit");
	check(depth_blend.coverage_mode == CoverageMode::Zap, "coverage mode decode mismatch");
	check(depth_blend.z_mode == ZMode::Decal, "z mode decode mismatch");
	check((static_state.flags & RASTERIZATION_ALPHA_CVG_SELECT_BIT) != 0u,
	      "alpha_cvg_select flag decode mismatch");
	check((static_state.flags & RASTERIZATION_CVG_TIMES_ALPHA_BIT) != 0u,
	      "cvg_times_alpha flag decode mismatch");
	check((static_state.flags & RASTERIZATION_AA_BIT) != 0u,
	      "AA raster flag decode mismatch");
	check((depth_blend.flags & DEPTH_BLEND_AA_BIT) != 0u,
	      "AA depth flag decode mismatch");
	check((static_state.flags & RASTERIZATION_ALPHA_TEST_DITHER_BIT) != 0u,
	      "alpha test dither flag decode mismatch");
	check((static_state.flags & RASTERIZATION_ALPHA_TEST_BIT) != 0u,
	      "alpha test flag decode mismatch");

	word0 = (0x8u << 4); // RGB dither mode Noise (2).
	detail::apply_set_other_modes_words(static_state, depth_blend, word0, 0u);
	check((depth_blend.flags & DEPTH_BLEND_DITHER_ENABLE_BIT) != 0u,
	      "non-Off dither mode should enable depth dither bit");
}

static void test_blend_cycle_decode_and_primitive_depth_enable()
{
	StaticRasterizationState static_state = {};
	DepthBlendState depth_blend = {};

	uint32_t word1 = 0;
	word1 |= (3u << 30); // blend_1a[0]
	word1 |= (2u << 28); // blend_1a[1]
	word1 |= (1u << 26); // blend_1b[0]
	word1 |= (0u << 24); // blend_1b[1]
	word1 |= (2u << 22); // blend_2a[0]
	word1 |= (1u << 20); // blend_2a[1]
	word1 |= (3u << 18); // blend_2b[0]
	word1 |= (2u << 16); // blend_2b[1]
	word1 |= (1u << 2);  // enable primitive depth

	const bool enable_primitive_depth = detail::apply_set_other_modes_words(static_state, depth_blend, 0u, word1);

	check(enable_primitive_depth, "primitive depth enable bit decode mismatch");
	check(depth_blend.blend_cycles[0].blend_1a == BlendMode1A::FogColor, "blend_1a[0] decode mismatch");
	check(depth_blend.blend_cycles[1].blend_1a == BlendMode1A::BlendColor, "blend_1a[1] decode mismatch");
	check(depth_blend.blend_cycles[0].blend_1b == BlendMode1B::FogAlpha, "blend_1b[0] decode mismatch");
	check(depth_blend.blend_cycles[1].blend_1b == BlendMode1B::PixelAlpha, "blend_1b[1] decode mismatch");
	check(depth_blend.blend_cycles[0].blend_2a == BlendMode2A::BlendColor, "blend_2a[0] decode mismatch");
	check(depth_blend.blend_cycles[1].blend_2a == BlendMode2A::MemoryColor, "blend_2a[1] decode mismatch");
	check(depth_blend.blend_cycles[0].blend_2b == BlendMode2B::Zero, "blend_2b[0] decode mismatch");
	check(depth_blend.blend_cycles[1].blend_2b == BlendMode2B::One, "blend_2b[1] decode mismatch");

	check(!detail::apply_set_other_modes_words(static_state, depth_blend, 0u, 0u),
	      "primitive depth should disable when bit is clear");
}

static void test_texture_pipeline_flag_decode()
{
	StaticRasterizationState static_state = {};
	DepthBlendState depth_blend = {};

	uint32_t word0 = 0;
	word0 |= (1u << 19); // perspective correct
	word0 |= (1u << 18); // detail lod
	word0 |= (1u << 17); // sharpen lod
	word0 |= (1u << 16); // tex lod
	word0 |= (1u << 15); // tlut
	word0 |= (1u << 14); // tlut type
	word0 |= (1u << 13); // sample mode
	word0 |= (1u << 12); // sample mid texel
	word0 |= (1u << 11); // bilerp 0
	word0 |= (1u << 10); // bilerp 1
	word0 |= (1u << 9);  // convert one

	uint32_t word1 = (1u << 14); // force blend

	detail::apply_set_other_modes_words(static_state, depth_blend, word0, word1);

	check((static_state.flags & RASTERIZATION_PERSPECTIVE_CORRECT_BIT) != 0u, "perspective flag mismatch");
	check((static_state.flags & RASTERIZATION_DETAIL_LOD_ENABLE_BIT) != 0u, "detail lod flag mismatch");
	check((static_state.flags & RASTERIZATION_SHARPEN_LOD_ENABLE_BIT) != 0u, "sharpen lod flag mismatch");
	check((static_state.flags & RASTERIZATION_TEX_LOD_ENABLE_BIT) != 0u, "tex lod flag mismatch");
	check((static_state.flags & RASTERIZATION_TLUT_BIT) != 0u, "tlut flag mismatch");
	check((static_state.flags & RASTERIZATION_TLUT_TYPE_BIT) != 0u, "tlut type flag mismatch");
	check((static_state.flags & RASTERIZATION_SAMPLE_MODE_BIT) != 0u, "sample mode flag mismatch");
	check((static_state.flags & RASTERIZATION_SAMPLE_MID_TEXEL_BIT) != 0u, "sample mid texel flag mismatch");
	check((static_state.flags & RASTERIZATION_BILERP_0_BIT) != 0u, "bilerp0 flag mismatch");
	check((static_state.flags & RASTERIZATION_BILERP_1_BIT) != 0u, "bilerp1 flag mismatch");
	check((static_state.flags & RASTERIZATION_CONVERT_ONE_BIT) != 0u, "convert-one flag mismatch");
	check((depth_blend.flags & DEPTH_BLEND_FORCE_BLEND_BIT) != 0u, "force blend flag mismatch");
}
}

int main()
{
	test_cycle_type_decoding_clears_previous_mode_bits();
	test_dither_and_coverage_decode();
	test_blend_cycle_decode_and_primitive_depth_enable();
	test_texture_pipeline_flag_decode();
	std::cout << "emu_unit_rdp_other_modes_policy_test: PASS" << std::endl;
	return 0;
}
