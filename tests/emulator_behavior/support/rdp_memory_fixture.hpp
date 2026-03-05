#pragma once

#include "mupen64plus-core/src/api/m64p_plugin.h"
#include <array>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace EmuBehaviorTest
{
class RdpMemoryFixture
{
public:
	static constexpr size_t RDRAM_SIZE = 8u * 1024u * 1024u;
	static constexpr size_t DMEM_SIZE = 4u * 1024u;
	static constexpr size_t IMEM_SIZE = 4u * 1024u;
	static constexpr size_t HEADER_SIZE = 0x40u;

	explicit RdpMemoryFixture(uint32_t seed = 0x12345678u);

	void reseed(uint32_t seed);
	GFX_INFO to_gfx_info();
	uint64_t digest() const;

	void reset_interrupt_counter();
	unsigned interrupt_counter() const;

	std::array<uint8_t, HEADER_SIZE> header = {};
	std::vector<uint8_t> rdram;
	std::array<uint8_t, DMEM_SIZE> dmem = {};
	std::array<uint8_t, IMEM_SIZE> imem = {};

	uint32_t mi_intr_reg = 0;
	uint32_t dpc_start_reg = 0;
	uint32_t dpc_end_reg = 0;
	uint32_t dpc_current_reg = 0;
	uint32_t dpc_status_reg = 0;
	uint32_t dpc_clock_reg = 0;
	uint32_t dpc_bufbusy_reg = 0;
	uint32_t dpc_pipebusy_reg = 0;
	uint32_t dpc_tmem_reg = 0;

	uint32_t vi_status_reg = 0;
	uint32_t vi_origin_reg = 0;
	uint32_t vi_width_reg = 0;
	uint32_t vi_intr_reg = 0;
	uint32_t vi_v_current_line_reg = 0;
	uint32_t vi_timing_reg = 0;
	uint32_t vi_v_sync_reg = 0;
	uint32_t vi_h_sync_reg = 0;
	uint32_t vi_leap_reg = 0;
	uint32_t vi_h_start_reg = 0;
	uint32_t vi_v_start_reg = 0;
	uint32_t vi_v_burst_reg = 0;
	uint32_t vi_x_scale_reg = 0;
	uint32_t vi_y_scale_reg = 0;

private:
	static void interrupt_trampoline();
	static RdpMemoryFixture *active_fixture;

	uint32_t seed = 0;
	unsigned interrupts = 0;
};
}
