#ifndef PARALLEL_RDP_COMMAND_INGEST_HPP
#define PARALLEL_RDP_COMMAND_INGEST_HPP

#include "z64.h"
#include <cstdint>

namespace RDP
{
namespace detail
{
struct CommandIngestState
{
	int cmd_cur = 0;
	int cmd_ptr = 0;
	uint32_t *cmd_data = nullptr;
};

struct CommandIngestHooks
{
	bool frontend_available = false;
	bool synchronous = false;
	void *userdata = nullptr;

	void (*enqueue_command)(void *userdata, unsigned num_words, const uint32_t *words) = nullptr;
	uint64_t (*signal_timeline)(void *userdata) = nullptr;
	void (*wait_for_timeline)(void *userdata, uint64_t timeline) = nullptr;
	void (*raise_dp_interrupt)(void *userdata) = nullptr;
};

inline void process_command_ingest(CommandIngestState &state,
                                   const uint8_t *dram,
                                   const uint8_t *sp_dmem,
                                   uint32_t &dpc_start_reg,
                                   uint32_t &dpc_end_reg,
                                   uint32_t &dpc_current_reg,
                                   uint32_t &dpc_status_reg,
                                   const CommandIngestHooks &hooks)
{
	static const unsigned cmd_len_lut[64] = {
		1, 1, 1, 1, 1, 1, 1, 1, 4, 6, 12, 14, 12, 14, 20, 22,
		1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  1,  1,  1,  1,  1,
		1, 1, 1, 1, 2, 2, 1, 1, 1, 1, 1,  1,  1,  1,  1,  1,
		1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  1,  1,  1,  1,  1,
	};

	const uint32_t DP_CURRENT = dpc_current_reg & 0x00FFFFF8;
	const uint32_t DP_END = dpc_end_reg & 0x00FFFFF8;
	dpc_status_reg &= ~DP_STATUS_FREEZE;

	int length = DP_END - DP_CURRENT;
	if (length <= 0)
		return;

	length = unsigned(length) >> 3;
	if ((state.cmd_ptr + length) & ~(0x0003FFFF >> 3))
		return;

	uint32_t offset = DP_CURRENT;
	if (dpc_status_reg & DP_STATUS_XBUS_DMA)
	{
		do
		{
			offset &= 0xFF8;
			state.cmd_data[2 * state.cmd_ptr + 0] = *reinterpret_cast<const uint32_t *>(sp_dmem + offset);
			state.cmd_data[2 * state.cmd_ptr + 1] = *reinterpret_cast<const uint32_t *>(sp_dmem + offset + 4);
			offset += sizeof(uint64_t);
			state.cmd_ptr++;
		} while (--length > 0);
	}
	else
	{
		if (DP_END > 0x7ffffff || DP_CURRENT > 0x7ffffff)
		{
			return;
		}
		else
		{
			do
			{
				offset &= 0xFFFFF8;
				state.cmd_data[2 * state.cmd_ptr + 0] = *reinterpret_cast<const uint32_t *>(dram + offset);
				state.cmd_data[2 * state.cmd_ptr + 1] = *reinterpret_cast<const uint32_t *>(dram + offset + 4);
				offset += sizeof(uint64_t);
				state.cmd_ptr++;
			} while (--length > 0);
		}
	}

	while (state.cmd_cur - state.cmd_ptr < 0)
	{
		uint32_t w1 = state.cmd_data[2 * state.cmd_cur];
		uint32_t command = (w1 >> 24) & 63;
		int cmd_length = cmd_len_lut[command];

		if (state.cmd_ptr - state.cmd_cur - cmd_length < 0)
		{
			dpc_start_reg = dpc_current_reg = dpc_end_reg;
			return;
		}

		if (command >= 8 && hooks.frontend_available && hooks.enqueue_command)
			hooks.enqueue_command(hooks.userdata, cmd_length * 2, &state.cmd_data[2 * state.cmd_cur]);

		// SyncFull (opcode 0x29).
		if (command == 0x29)
		{
			if (hooks.synchronous && hooks.frontend_available && hooks.signal_timeline && hooks.wait_for_timeline)
				hooks.wait_for_timeline(hooks.userdata, hooks.signal_timeline(hooks.userdata));
			if (hooks.raise_dp_interrupt)
				hooks.raise_dp_interrupt(hooks.userdata);
		}

		state.cmd_cur += cmd_length;
	}

	state.cmd_ptr = 0;
	state.cmd_cur = 0;
	dpc_start_reg = dpc_current_reg = dpc_end_reg;
}
}
}

#endif
