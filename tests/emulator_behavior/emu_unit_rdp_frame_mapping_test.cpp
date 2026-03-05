#include "rdp_memory_fixture.hpp"
#include "mupen64plus-video-paraLLEl/rdp_frame_mapping.hpp"

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <utility>
#include <vector>

using namespace EmuBehaviorTest;
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

static void test_sync_mask_to_num_frames()
{
	check(detail::sync_mask_to_num_frames(0x0u) == 0u, "mask=0 should produce 0 frames");
	check(detail::sync_mask_to_num_frames(0x1u) == 1u, "mask=1 should produce 1 frame");
	check(detail::sync_mask_to_num_frames(0x5u) == 3u, "mask=0b101 should produce 3 frames");
	check(detail::sync_mask_to_num_frames(0x80000000u) == 32u, "highest-bit mask should produce 32 frames");
}

static void test_vi_register_forwarding_table()
{
	RdpMemoryFixture fixture(0x10293847u);
	fixture.vi_status_reg = 0x11u;
	fixture.vi_origin_reg = 0x22u;
	fixture.vi_width_reg = 0x33u;
	fixture.vi_intr_reg = 0x44u;
	fixture.vi_v_current_line_reg = 0x55u;
	fixture.vi_timing_reg = 0x66u;
	fixture.vi_v_sync_reg = 0x77u;
	fixture.vi_h_sync_reg = 0x88u;
	fixture.vi_leap_reg = 0x99u;
	fixture.vi_h_start_reg = 0xaau;
	fixture.vi_v_start_reg = 0xbbu;
	fixture.vi_v_burst_reg = 0xccu;
	fixture.vi_x_scale_reg = 0xddu;
	fixture.vi_y_scale_reg = 0xeeu;

	const GFX_INFO info = fixture.to_gfx_info();

	std::vector<std::pair<VIRegister, uint32_t>> writes;
	detail::forward_vi_registers(
			[&](VIRegister reg, uint32_t value) {
				writes.emplace_back(reg, value);
			},
			info);

	check(writes.size() == 14, "expected 14 VI writes");
	check(writes[0] == std::make_pair(VIRegister::Control, 0x11u), "Control mapping mismatch");
	check(writes[1] == std::make_pair(VIRegister::Origin, 0x22u), "Origin mapping mismatch");
	check(writes[2] == std::make_pair(VIRegister::Width, 0x33u), "Width mapping mismatch");
	check(writes[3] == std::make_pair(VIRegister::Intr, 0x44u), "Intr mapping mismatch");
	check(writes[4] == std::make_pair(VIRegister::VCurrentLine, 0x55u), "VCurrentLine mapping mismatch");
	check(writes[5] == std::make_pair(VIRegister::Timing, 0xccu), "Timing mapping mismatch");
	check(writes[6] == std::make_pair(VIRegister::VSync, 0x77u), "VSync mapping mismatch");
	check(writes[7] == std::make_pair(VIRegister::HSync, 0x88u), "HSync mapping mismatch");
	check(writes[8] == std::make_pair(VIRegister::Leap, 0x99u), "Leap mapping mismatch");
	check(writes[9] == std::make_pair(VIRegister::HStart, 0xaau), "HStart mapping mismatch");
	check(writes[10] == std::make_pair(VIRegister::VStart, 0xbbu), "VStart mapping mismatch");
	check(writes[11] == std::make_pair(VIRegister::VBurst, 0xccu), "VBurst mapping mismatch");
	check(writes[12] == std::make_pair(VIRegister::XScale, 0xddu), "XScale mapping mismatch");
	check(writes[13] == std::make_pair(VIRegister::YScale, 0xeeu), "YScale mapping mismatch");
}

static void test_scanout_options_mapping()
{
	const ScanoutOptions opts = detail::make_scanout_options(
			true, false, true, false, true, 3u, 24u);

	check(opts.persist_frame_on_invalid_input, "persist_frame_on_invalid_input should be true");
	check(opts.vi.aa == true, "vi.aa mismatch");
	check(opts.vi.scale == false, "vi.scale mismatch");
	check(opts.vi.dither_filter == true, "vi.dither_filter mismatch");
	check(opts.vi.divot_filter == false, "vi.divot_filter mismatch");
	check(opts.vi.gamma_dither == true, "vi.gamma_dither mismatch");
	check(opts.downscale_steps == 3u, "downscale_steps mismatch");
	check(opts.crop_overscan_pixels == 24u, "crop_overscan_pixels mismatch");
}
}

int main()
{
	test_sync_mask_to_num_frames();
	test_vi_register_forwarding_table();
	test_scanout_options_mapping();
	std::cout << "emu_unit_rdp_frame_mapping_test: PASS" << std::endl;
	return 0;
}
