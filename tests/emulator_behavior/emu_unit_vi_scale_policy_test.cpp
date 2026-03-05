#include "mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/vi_scale_policy.hpp"

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

static VIScalePolicyInput make_default_input()
{
	VIScalePolicyInput in = {};
	in.is_pal = false;
	in.status = VI_CONTROL_TYPE_RGBA5551_BIT;
	in.v_start = 10;
	in.v_res = 120;
	in.v_current_line = 0;
	in.crop_overscan_pixels = 0;
	in.scaling_factor = 1;
	in.upscale_deinterlacing = true;
	return in;
}

static void test_serrate_disabled_when_upscale_deinterlacing_is_enabled()
{
	auto in = make_default_input();
	in.status |= VI_CONTROL_SERRATE_BIT;
	in.crop_overscan_pixels = 3;
	in.scaling_factor = 4;
	in.upscale_deinterlacing = true;

	auto policy = derive_vi_scale_policy(in);
	check(!policy.serrate, "serrate should be disabled when upscale deinterlacing is enabled");
	check(policy.crop_pixels_x == 12u, "crop_pixels_x mismatch when serrate is disabled");
	check(policy.crop_pixels_y == 12u, "crop_pixels_y mismatch when serrate is disabled");
	check(policy.render_target_width == 2536u, "render target width mismatch for non-serrate path");
	check(policy.render_target_height == 936u, "render target height mismatch for non-serrate path");
	check(policy.adjusted_v_start == in.v_start, "v_start should remain unchanged without serrate");
	check(policy.adjusted_v_res == in.v_res, "v_res should remain unchanged without serrate");
	check(policy.serrate_shift == 0u && policy.serrate_mask == 0u && policy.serrate_select == 0u,
	      "serrate push fields should be zero when serrate is disabled");
}

static void test_serrate_enabled_doubles_vertical_domain_and_selects_even_field()
{
	auto in = make_default_input();
	in.status |= VI_CONTROL_SERRATE_BIT;
	in.crop_overscan_pixels = 2;
	in.scaling_factor = 2;
	in.upscale_deinterlacing = false;
	in.v_current_line = 0;

	auto policy = derive_vi_scale_policy(in);
	check(policy.serrate, "serrate should be enabled when VI bit is set and deinterlacing is disabled");
	check(policy.crop_pixels_x == 4u, "crop_pixels_x mismatch for serrate path");
	check(policy.crop_pixels_y == 8u, "crop_pixels_y should double in serrate path");
	check(policy.render_target_width == 1272u, "render target width mismatch for serrate path");
	check(policy.render_target_height == 944u, "render target height mismatch for serrate path");
	check(policy.adjusted_v_start == 20, "v_start should double when serrate is enabled");
	check(policy.adjusted_v_res == 240, "v_res should double when serrate is enabled");
	check(policy.serrate_shift == 1u && policy.serrate_mask == 1u,
	      "serrate push fields shift/mask mismatch");
	check(policy.serrate_select == 1u, "serrate select should target even field when VCurrentLine parity is zero");
}

static void test_serrate_select_switches_with_vcurrent_line_parity()
{
	auto in = make_default_input();
	in.status |= VI_CONTROL_SERRATE_BIT;
	in.upscale_deinterlacing = false;
	in.v_current_line = 1;

	auto policy = derive_vi_scale_policy(in);
	check(policy.serrate, "serrate should be enabled for parity test");
	check(policy.serrate_select == 0u,
	      "serrate select should target odd field when VCurrentLine parity is one");
}

static void test_pal_non_serrate_uses_pal_vertical_resolution()
{
	auto in = make_default_input();
	in.is_pal = true;
	in.crop_overscan_pixels = 1;
	in.scaling_factor = 2;
	in.upscale_deinterlacing = false;
	in.status &= ~VI_CONTROL_SERRATE_BIT;

	auto policy = derive_vi_scale_policy(in);
	check(!policy.serrate, "serrate should remain disabled when VI bit is clear");
	check(policy.crop_pixels_x == 2u && policy.crop_pixels_y == 2u,
	      "PAL non-serrate crop pixels mismatch");
	check(policy.render_target_width == 1276u, "PAL non-serrate width mismatch");
	check(policy.render_target_height == 572u, "PAL non-serrate height mismatch");
}
}

int main()
{
	test_serrate_disabled_when_upscale_deinterlacing_is_enabled();
	test_serrate_enabled_doubles_vertical_domain_and_selects_even_field();
	test_serrate_select_switches_with_vcurrent_line_parity();
	test_pal_non_serrate_uses_pal_vertical_resolution();
	std::cout << "emu_unit_vi_scale_policy_test: PASS" << std::endl;
	return 0;
}
