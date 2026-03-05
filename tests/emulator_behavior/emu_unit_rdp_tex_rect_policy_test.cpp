#include "mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_tex_rect_policy.hpp"

#include <cstdlib>
#include <iostream>

using namespace RDP;
using namespace RDP::detail;

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

static TextureRectanglePolicyInput make_default_input()
{
	TextureRectanglePolicyInput in = {};
	in.rect.xl = 10;
	in.rect.yl = 20;
	in.rect.xh = 30;
	in.rect.yh = 40;
	in.word1 = 0;
	in.word2 = 0;
	in.word3 = 0;
	in.raster_flags = 0;
	in.flip = false;
	in.native_resolution_tex_rect = false;
	in.native_texture_lod = false;
	return in;
}

static void test_non_flip_policy_sets_standard_gradients_and_copy_flag()
{
	auto in = make_default_input();
	in.word1 = 0xfu << 24; // tile should mask to 3 bits.
	in.word2 = (0x0002u << 16) | 0x0003u;
	in.word3 = (0x0004u << 16) | 0xfffcu; // dsdx = +4, dtdy = -4
	in.raster_flags = RASTERIZATION_COPY_BIT;

	auto out = build_texture_rectangle_policy(in);
	check(out.setup.xh == (30u << 13) && out.setup.xl == (10u << 13) && out.setup.xm == (10u << 13),
	      "non-flip setup coordinate packing mismatch");
	check(out.setup.ym == 20u && out.setup.yl == 20u && out.setup.yh == 40u,
	      "non-flip setup y packing mismatch");
	check((out.setup.flags & TRIANGLE_SETUP_FLIP_BIT) != 0u, "flip bit must always be set");
	check((out.setup.flags & TRIANGLE_SETUP_SKIP_XFRAC_BIT) != 0u,
	      "copy mode should set skip-xfrac bit");
	check((out.setup.flags & TRIANGLE_SETUP_DISABLE_UPSCALING_BIT) == 0u,
	      "non-flip setup should not force disable-upscaling without native tex-rect");
	check((out.setup.flags & TRIANGLE_SETUP_NATIVE_LOD_BIT) == 0u,
	      "native lod bit should be clear by default");
	check(out.setup.tile == 0x7u, "tile index should decode from 3-bit field");

	check(out.attr.s == (2 << 16) && out.attr.t == (3 << 16),
	      "non-flip texture coordinate packing mismatch");
	check(out.attr.dsdx == (4 << 11), "non-flip dsdx gradient mismatch");
	check(out.attr.dtde == (-4 << 11), "non-flip dtde gradient mismatch");
	check(out.attr.dtdy == (-4 << 11), "non-flip dtdy gradient mismatch");
}

static void test_flip_policy_forces_disable_upscaling_and_swaps_gradients()
{
	auto in = make_default_input();
	in.flip = true;
	in.native_texture_lod = true;
	in.word2 = (0x0040u << 16) | 0x0080u;
	in.word3 = (0xfffeu << 16) | 0x0007u; // dsdx = -2, dtdy = +7

	auto out = build_texture_rectangle_policy(in);
	check((out.setup.flags & TRIANGLE_SETUP_FLIP_BIT) != 0u, "flip path must set flip bit");
	check((out.setup.flags & TRIANGLE_SETUP_DISABLE_UPSCALING_BIT) != 0u,
	      "flip path must force disable-upscaling");
	check((out.setup.flags & TRIANGLE_SETUP_NATIVE_LOD_BIT) != 0u,
	      "native texture lod flag should propagate");
	check((out.setup.flags & TRIANGLE_SETUP_SKIP_XFRAC_BIT) == 0u,
	      "skip-xfrac should remain clear when copy bit is unset");

	check(out.attr.dtdx == (7 << 11), "flip dtdx gradient mismatch");
	check(out.attr.dsde == (-2 << 11), "flip dsde gradient mismatch");
	check(out.attr.dsdy == (-2 << 11), "flip dsdy gradient mismatch");
}

static void test_native_tex_rect_enables_disable_upscaling_without_flip()
{
	auto in = make_default_input();
	in.flip = false;
	in.native_resolution_tex_rect = true;

	auto out = build_texture_rectangle_policy(in);
	check((out.setup.flags & TRIANGLE_SETUP_DISABLE_UPSCALING_BIT) != 0u,
	      "native-resolution tex-rect option should disable upscaling in non-flip mode");
}
}

int main()
{
	test_non_flip_policy_sets_standard_gradients_and_copy_flag();
	test_flip_policy_forces_disable_upscaling_and_swaps_gradients();
	test_native_tex_rect_enables_disable_upscaling_without_flip();
	std::cout << "emu_unit_rdp_tex_rect_policy_test: PASS" << std::endl;
	return 0;
}
