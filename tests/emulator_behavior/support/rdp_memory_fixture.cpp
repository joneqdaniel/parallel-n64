#include "rdp_memory_fixture.hpp"
#include <algorithm>

namespace EmuBehaviorTest
{
RdpMemoryFixture *RdpMemoryFixture::active_fixture = nullptr;

namespace
{
static uint32_t xorshift32(uint32_t &state)
{
	state ^= state << 13;
	state ^= state >> 17;
	state ^= state << 5;
	return state;
}

template <typename Container>
static void fill_bytes(Container &container, uint32_t &state)
{
	for (auto &v : container)
		v = static_cast<uint8_t>(xorshift32(state) & 0xffu);
}

static uint64_t fnv1a64_mix(uint64_t hash, uint8_t byte)
{
	constexpr uint64_t prime = 1099511628211ull;
	hash ^= uint64_t(byte);
	hash *= prime;
	return hash;
}
}

RdpMemoryFixture::RdpMemoryFixture(uint32_t seed_)
    : rdram(RDRAM_SIZE), seed(seed_)
{
	reseed(seed_);
}

void RdpMemoryFixture::reseed(uint32_t seed_)
{
	seed = seed_;
	uint32_t state = seed;
	fill_bytes(header, state);
	fill_bytes(rdram, state);
	fill_bytes(dmem, state);
	fill_bytes(imem, state);

	auto next32 = [&]() -> uint32_t { return xorshift32(state); };
	mi_intr_reg = next32();
	dpc_start_reg = next32();
	dpc_end_reg = next32();
	dpc_current_reg = next32();
	dpc_status_reg = next32();
	dpc_clock_reg = next32();
	dpc_bufbusy_reg = next32();
	dpc_pipebusy_reg = next32();
	dpc_tmem_reg = next32();

	vi_status_reg = next32();
	vi_origin_reg = next32();
	vi_width_reg = next32();
	vi_intr_reg = next32();
	vi_v_current_line_reg = next32();
	vi_timing_reg = next32();
	vi_v_sync_reg = next32();
	vi_h_sync_reg = next32();
	vi_leap_reg = next32();
	vi_h_start_reg = next32();
	vi_v_start_reg = next32();
	vi_v_burst_reg = next32();
	vi_x_scale_reg = next32();
	vi_y_scale_reg = next32();

	interrupts = 0;
}

GFX_INFO RdpMemoryFixture::to_gfx_info()
{
	active_fixture = this;
	GFX_INFO info = {};
	info.HEADER = header.data();
	info.RDRAM = rdram.data();
	info.DMEM = dmem.data();
	info.IMEM = imem.data();

	info.MI_INTR_REG = &mi_intr_reg;
	info.DPC_START_REG = &dpc_start_reg;
	info.DPC_END_REG = &dpc_end_reg;
	info.DPC_CURRENT_REG = &dpc_current_reg;
	info.DPC_STATUS_REG = &dpc_status_reg;
	info.DPC_CLOCK_REG = &dpc_clock_reg;
	info.DPC_BUFBUSY_REG = &dpc_bufbusy_reg;
	info.DPC_PIPEBUSY_REG = &dpc_pipebusy_reg;
	info.DPC_TMEM_REG = &dpc_tmem_reg;

	info.VI_STATUS_REG = &vi_status_reg;
	info.VI_ORIGIN_REG = &vi_origin_reg;
	info.VI_WIDTH_REG = &vi_width_reg;
	info.VI_INTR_REG = &vi_intr_reg;
	info.VI_V_CURRENT_LINE_REG = &vi_v_current_line_reg;
	info.VI_TIMING_REG = &vi_timing_reg;
	info.VI_V_SYNC_REG = &vi_v_sync_reg;
	info.VI_H_SYNC_REG = &vi_h_sync_reg;
	info.VI_LEAP_REG = &vi_leap_reg;
	info.VI_H_START_REG = &vi_h_start_reg;
	info.VI_V_START_REG = &vi_v_start_reg;
	info.VI_V_BURST_REG = &vi_v_burst_reg;
	info.VI_X_SCALE_REG = &vi_x_scale_reg;
	info.VI_Y_SCALE_REG = &vi_y_scale_reg;

	info.CheckInterrupts = &RdpMemoryFixture::interrupt_trampoline;
	return info;
}

uint64_t RdpMemoryFixture::digest() const
{
	uint64_t hash = 1469598103934665603ull;

	auto mix_u32 = [&](uint32_t value) {
		for (unsigned i = 0; i < 4; i++)
			hash = fnv1a64_mix(hash, uint8_t((value >> (i * 8)) & 0xffu));
	};

	for (uint8_t v : header)
		hash = fnv1a64_mix(hash, v);

	const size_t sample_count = 1024;
	for (size_t i = 0; i < sample_count; i++)
	{
		size_t index = (i * 7919u) % rdram.size();
		hash = fnv1a64_mix(hash, rdram[index]);
	}

	for (uint8_t v : dmem)
		hash = fnv1a64_mix(hash, v);
	for (uint8_t v : imem)
		hash = fnv1a64_mix(hash, v);

	mix_u32(mi_intr_reg);
	mix_u32(dpc_start_reg);
	mix_u32(dpc_end_reg);
	mix_u32(dpc_current_reg);
	mix_u32(dpc_status_reg);
	mix_u32(dpc_clock_reg);
	mix_u32(dpc_bufbusy_reg);
	mix_u32(dpc_pipebusy_reg);
	mix_u32(dpc_tmem_reg);
	mix_u32(vi_status_reg);
	mix_u32(vi_origin_reg);
	mix_u32(vi_width_reg);
	mix_u32(vi_intr_reg);
	mix_u32(vi_v_current_line_reg);
	mix_u32(vi_timing_reg);
	mix_u32(vi_v_sync_reg);
	mix_u32(vi_h_sync_reg);
	mix_u32(vi_leap_reg);
	mix_u32(vi_h_start_reg);
	mix_u32(vi_v_start_reg);
	mix_u32(vi_v_burst_reg);
	mix_u32(vi_x_scale_reg);
	mix_u32(vi_y_scale_reg);
	return hash;
}

void RdpMemoryFixture::reset_interrupt_counter()
{
	interrupts = 0;
}

unsigned RdpMemoryFixture::interrupt_counter() const
{
	return interrupts;
}

void RdpMemoryFixture::interrupt_trampoline()
{
	if (active_fixture)
		active_fixture->interrupts++;
}
}
