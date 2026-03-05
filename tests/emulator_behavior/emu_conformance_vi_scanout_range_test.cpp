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
	unsigned offset = 0;
	unsigned length = 0;

	regs[unsigned(VIRegister::Control)] = VI_CONTROL_TYPE_RGBA5551_BIT;
	regs[unsigned(VIRegister::Origin)] = 0;
	regs[unsigned(VIRegister::Width)] = 320;
	regs[unsigned(VIRegister::VSync)] = VI_V_SYNC_NTSC;
	regs[unsigned(VIRegister::HStart)] = make_vi_start_register(VI_H_OFFSET_NTSC, VI_H_OFFSET_NTSC + 320u);
	regs[unsigned(VIRegister::VStart)] = make_vi_start_register(VI_V_OFFSET_NTSC, VI_V_OFFSET_NTSC + 480u);
	regs[unsigned(VIRegister::XScale)] = make_vi_scale_register(1024u, 0u);
	regs[unsigned(VIRegister::YScale)] = make_vi_scale_register(1024u, 0u);

	auto decoded = decode_vi_registers(regs.data());
	compute_scanout_memory_range(decoded, offset, length);
	check(offset == 0u && length == 0u, "zero origin must produce empty scanout range");

	regs[unsigned(VIRegister::Origin)] = 0x1000u;
	decoded = decode_vi_registers(regs.data());
	compute_scanout_memory_range(decoded, offset, length);
	check(decoded.h_start == 0 && decoded.v_start == 0, "default NTSC start offsets mismatch");
	check(decoded.max_x == 320 && decoded.max_y == 240, "default NTSC max dimensions mismatch");
	check(offset == 2812u, "16-bit scanout offset mismatch");
	check(length == 157452u, "16-bit scanout length mismatch");
	check(!need_fetch_bug_emulation(decoded, 1u), "fetch bug must be disabled when y_add >= 1024");

	regs[unsigned(VIRegister::Control)] = VI_CONTROL_TYPE_RGBA8888_BIT | VI_CONTROL_DIVOT_ENABLE_BIT;
	regs[unsigned(VIRegister::Origin)] = 0x10003u;
	regs[unsigned(VIRegister::Width)] = 640u;
	regs[unsigned(VIRegister::HStart)] = make_vi_start_register(VI_H_OFFSET_NTSC, VI_H_OFFSET_NTSC + 640u);
	regs[unsigned(VIRegister::VStart)] = make_vi_start_register(VI_V_OFFSET_NTSC, VI_V_OFFSET_NTSC + 960u);
	decoded = decode_vi_registers(regs.data());
	compute_scanout_memory_range(decoded, offset, length);
	check(decoded.max_x == 640 && decoded.max_y == 480, "RGBA8888 max dimensions mismatch");
	check(offset == 60404u, "32-bit divot scanout offset mismatch");
	check(length == 1244192u, "32-bit divot scanout length mismatch");

	regs[unsigned(VIRegister::YScale)] = make_vi_scale_register(1000u, 0u);
	decoded = decode_vi_registers(regs.data());
	check(need_fetch_bug_emulation(decoded, 1u), "fetch bug must be enabled when y_add < 1024 at native scale");
	check(!need_fetch_bug_emulation(decoded, 2u), "fetch bug must be disabled when scaling > 1");

	// Origin alignment should follow pixel size (16-bit => 2-byte, 32-bit => 4-byte alignment).
	regs[unsigned(VIRegister::Control)] = VI_CONTROL_TYPE_RGBA5551_BIT;
	regs[unsigned(VIRegister::Origin)] = 0x1001u;
	regs[unsigned(VIRegister::Width)] = 320u;
	regs[unsigned(VIRegister::HStart)] = make_vi_start_register(VI_H_OFFSET_NTSC, VI_H_OFFSET_NTSC + 320u);
	regs[unsigned(VIRegister::VStart)] = make_vi_start_register(VI_V_OFFSET_NTSC, VI_V_OFFSET_NTSC + 480u);
	regs[unsigned(VIRegister::XScale)] = make_vi_scale_register(1024u, 0u);
	regs[unsigned(VIRegister::YScale)] = make_vi_scale_register(1024u, 0u);
	decoded = decode_vi_registers(regs.data());
	compute_scanout_memory_range(decoded, offset, length);
	check(offset != 0u && length != 0u, "16-bit alignment case should produce a non-empty range");
	check((offset & 1u) == 0u, "16-bit scanout offset should be 2-byte aligned");

	regs[unsigned(VIRegister::Control)] = VI_CONTROL_TYPE_RGBA8888_BIT;
	regs[unsigned(VIRegister::Origin)] = 0x1003u;
	decoded = decode_vi_registers(regs.data());
	compute_scanout_memory_range(decoded, offset, length);
	check(offset != 0u && length != 0u, "32-bit alignment case should produce a non-empty range");
	check((offset & 3u) == 0u, "32-bit scanout offset should be 4-byte aligned");

	std::cout << "emu_conformance_vi_scanout_range_test: PASS" << std::endl;
	return 0;
}
