#include "mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_rect_setup_policy.hpp"

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

static void test_decode_rectangle_coordinates_masks_to_12_bits()
{
	const uint32_t word0 = (0x123u << 12) | 0x456u;
	const uint32_t word1 = (0xabcdu << 12) | 0x789u;

	auto rect = decode_rectangle_coordinates(word0, word1);
	check(rect.xl == 0x123u, "xl decode mismatch");
	check(rect.yl == 0x456u, "yl decode mismatch");
	check(rect.xh == 0xbcdu, "xh decode should use low 12 bits");
	check(rect.yh == 0x789u, "yh decode mismatch");
}

static void test_copy_fill_adjust_only_applies_when_mode_bits_are_set()
{
	RectangleCoordinates rect = {};
	rect.yl = 0x120u;

	auto unchanged = apply_copy_fill_y_adjust(rect, 0u);
	check(unchanged.yl == 0x120u, "yl should be unchanged when copy/fill bits are clear");

	auto copy_adjusted = apply_copy_fill_y_adjust(rect, RASTERIZATION_COPY_BIT);
	check(copy_adjusted.yl == 0x123u, "yl low bits should be forced for copy mode");

	auto fill_adjusted = apply_copy_fill_y_adjust(rect, RASTERIZATION_FILL_BIT);
	check(fill_adjusted.yl == 0x123u, "yl low bits should be forced for fill mode");
}

static void test_fill_rectangle_setup_packs_triangle_state()
{
	RectangleCoordinates rect = {};
	rect.xl = 40;
	rect.yl = 84;
	rect.xh = 120;
	rect.yh = 200;

	auto setup = build_fill_rectangle_setup(rect);
	check(setup.xh == (120u << 13), "fill setup xh packing mismatch");
	check(setup.xl == (40u << 13), "fill setup xl packing mismatch");
	check(setup.xm == (40u << 13), "fill setup xm packing mismatch");
	check(setup.ym == 84u && setup.yl == 84u && setup.yh == 200u,
	      "fill setup y coordinate packing mismatch");
	check((setup.flags & TRIANGLE_SETUP_FLIP_BIT) != 0u,
	      "fill setup should enable triangle flip bit");
	check((setup.flags & TRIANGLE_SETUP_DISABLE_UPSCALING_BIT) != 0u,
	      "fill setup should disable upscaling");
	check(setup.flags == (TRIANGLE_SETUP_FLIP_BIT | TRIANGLE_SETUP_DISABLE_UPSCALING_BIT),
	      "fill setup flags should not include unexpected bits");
}
}

int main()
{
	test_decode_rectangle_coordinates_masks_to_12_bits();
	test_copy_fill_adjust_only_applies_when_mode_bits_are_set();
	test_fill_rectangle_setup_packs_triangle_state();
	std::cout << "emu_unit_rdp_rect_setup_policy_test: PASS" << std::endl;
	return 0;
}
