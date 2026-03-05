#include "mupen64plus-video-paraLLEl/rdp_command_ingest.hpp"

#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <vector>

using namespace RDP::detail;

namespace
{
struct HookState
{
	std::vector<unsigned> enqueued_words;
	std::vector<uint32_t> enqueued_opcodes;
	unsigned interrupt_count = 0;
};

static void check(bool condition, const char *message)
{
	if (!condition)
	{
		std::cerr << "FAIL: " << message << std::endl;
		std::exit(1);
	}
}

static void enqueue_cb(void *userdata, unsigned num_words, const uint32_t *words)
{
	auto *state = static_cast<HookState *>(userdata);
	state->enqueued_words.push_back(num_words);
	state->enqueued_opcodes.push_back((words[0] >> 24) & 63u);
}

static void interrupt_cb(void *userdata)
{
	auto *state = static_cast<HookState *>(userdata);
	state->interrupt_count++;
}

static void write_command_pair(std::array<uint8_t, 2048> &memory, size_t pair_index, uint32_t w0, uint32_t w1)
{
	uint32_t words[2] = { w0, w1 };
	std::memcpy(memory.data() + pair_index * sizeof(uint64_t), words, sizeof(words));
}

static void write_command(std::array<uint8_t, 2048> &memory,
                          size_t &pair_index,
                          uint32_t opcode,
                          unsigned pair_count,
                          uint32_t seed)
{
	write_command_pair(memory, pair_index, opcode << 24, seed);
	pair_index++;
	for (unsigned i = 1; i < pair_count; i++, pair_index++)
		write_command_pair(memory, pair_index, seed + i, seed + 0x100u + i);
}
}

int main()
{
	std::array<uint8_t, 2048> dram = {};
	std::array<uint8_t, 2048> sp_dmem = {};
	std::array<uint32_t, 1024> cmd_data = {};
	size_t pair_index = 0;

	write_command(dram, pair_index, 0x08u, 4u, 0x1000u);  // FillTriangle
	write_command(dram, pair_index, 0x24u, 2u, 0x2000u);  // TextureRectangle
	write_command(dram, pair_index, 0x0fu, 22u, 0x3000u); // ShadeTextureZBufferTriangle
	write_command(dram, pair_index, 0x29u, 1u, 0x4000u);  // SyncFull
	write_command(dram, pair_index, 0x36u, 1u, 0x5000u);  // FillRectangle

	CommandIngestState ingest = {};
	ingest.cmd_data = cmd_data.data();

	uint32_t dpc_start = 0;
	uint32_t dpc_current = 0;
	uint32_t dpc_end = static_cast<uint32_t>(pair_index * sizeof(uint64_t));
	uint32_t dpc_status = 0;

	HookState hook_state;
	CommandIngestHooks hooks = {};
	hooks.frontend_available = true;
	hooks.synchronous = false;
	hooks.userdata = &hook_state;
	hooks.enqueue_command = enqueue_cb;
	hooks.raise_dp_interrupt = interrupt_cb;

	process_command_ingest(ingest,
	                       dram.data(),
	                       sp_dmem.data(),
	                       dpc_start,
	                       dpc_end,
	                       dpc_current,
	                       dpc_status,
	                       hooks);

	const std::array<uint32_t, 5> expected_opcodes = { 0x08u, 0x24u, 0x0fu, 0x29u, 0x36u };
	const std::array<unsigned, 5> expected_words = { 8u, 4u, 44u, 2u, 2u };

	check(hook_state.enqueued_opcodes.size() == expected_opcodes.size(), "command count mismatch");
	for (size_t i = 0; i < expected_opcodes.size(); i++)
	{
		check(hook_state.enqueued_opcodes[i] == expected_opcodes[i], "opcode decode/ordering mismatch");
		check(hook_state.enqueued_words[i] == expected_words[i], "command length decode mismatch");
	}

	check(hook_state.interrupt_count == 1u, "SyncFull interrupt count mismatch");
	check(dpc_start == dpc_end && dpc_current == dpc_end, "DPC reset-to-END mismatch");

	std::cout << "emu_conformance_rdp_command_lengths_test: PASS" << std::endl;
	return 0;
}
