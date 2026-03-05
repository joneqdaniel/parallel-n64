#include "vi_scanout_policy.hpp"

#include <array>
#include <cstdint>
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
}

int main()
{
	std::array<uint32_t, unsigned(VIRegister::Count)> regs = {};

	regs[unsigned(VIRegister::Control)] = VI_CONTROL_TYPE_RGBA5551_BIT;
	regs[unsigned(VIRegister::Origin)] = 0x2000u;
	regs[unsigned(VIRegister::Width)] = 320u;
	regs[unsigned(VIRegister::VSync)] = VI_V_SYNC_PAL;
	regs[unsigned(VIRegister::HStart)] = make_vi_start_register(100u, 900u);
	regs[unsigned(VIRegister::VStart)] = make_vi_start_register(30u, 500u);
	regs[unsigned(VIRegister::XScale)] = make_vi_scale_register(512u, 50u);
	regs[unsigned(VIRegister::YScale)] = make_vi_scale_register(768u, 80u);

	auto decoded = decode_vi_registers(regs.data());
	check(decoded.is_pal, "PAL detection mismatch");
	check(decoded.left_clamp, "left clamp should trigger when HSTART is below PAL offset");
	check(decoded.right_clamp, "right clamp should trigger when width exceeds VI scanout width");
	check(decoded.h_start == 0, "clamped h_start mismatch");
	check(decoded.h_res == VI_SCANOUT_WIDTH, "clamped h_res mismatch");
	check(decoded.v_start == 0, "clamped v_start mismatch");
	check(decoded.x_start == 14386, "x_start after clamp mismatch");
	check(decoded.y_start == 5456, "y_start after clamp mismatch");
	check(decoded.max_x == 334, "max_x mismatch");
	check(decoded.max_y == 181, "max_y mismatch");

	unsigned offset = 0;
	unsigned length = 0;
	compute_scanout_memory_range(decoded, offset, length);
	check(offset == 6908u, "PAL clamped scanout offset mismatch");
	check(length == 119720u, "PAL clamped scanout length mismatch");

	// Verify right-clamp behavior when start is positive but range exceeds visible width.
	regs[unsigned(VIRegister::VSync)] = VI_V_SYNC_NTSC;
	regs[unsigned(VIRegister::HStart)] = make_vi_start_register(VI_H_OFFSET_NTSC + 600u, VI_H_OFFSET_NTSC + 900u);
	regs[unsigned(VIRegister::VStart)] = make_vi_start_register(VI_V_OFFSET_NTSC + 20u, VI_V_OFFSET_NTSC + 220u);
	regs[unsigned(VIRegister::XScale)] = make_vi_scale_register(1024u, 0u);
	regs[unsigned(VIRegister::YScale)] = make_vi_scale_register(1024u, 0u);
	regs[unsigned(VIRegister::Width)] = 640u;
	regs[unsigned(VIRegister::Origin)] = 0x18000u;

	decoded = decode_vi_registers(regs.data());
	check(!decoded.left_clamp, "left clamp should not trigger in right-clamp-only case");
	check(decoded.right_clamp, "right clamp expected in right-clamp-only case");
	check(decoded.h_start == 600, "right-clamp h_start mismatch");
	check(decoded.h_res == 40, "right-clamp h_res mismatch");
	check(decoded.max_x == 40, "right-clamp max_x mismatch");
	check(decoded.max_y == 100, "right-clamp max_y mismatch");

	compute_scanout_memory_range(decoded, offset, length);
	check(offset == 95740u, "right-clamp scanout offset mismatch");
	check(length == 134492u, "right-clamp scanout length mismatch");

	std::cout << "emu_conformance_vi_scaling_crop_test: PASS" << std::endl;
	return 0;
}
