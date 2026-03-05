#include "mupen64plus-video-paraLLEl/rdp_command_ingest.hpp"
#include "mupen64plus-video-paraLLEl/z64.h"

#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <vector>

using namespace RDP::detail;

namespace
{
struct CallbackHarness
{
	unsigned enqueue_calls = 0;
	unsigned interrupt_calls = 0;
	unsigned signal_calls = 0;
	unsigned wait_calls = 0;
	unsigned last_num_words = 0;
	uint64_t signal_value = 0x1234u;
	uint64_t waited_timeline = 0;
	bool wait_timeline_matches_signal = false;
	std::vector<uint32_t> last_words;
	std::vector<int> order;
};

static void check(bool condition, const char *message)
{
	if (!condition)
	{
		std::cerr << "FAIL: " << message << std::endl;
		std::exit(1);
	}
}

static void write_u32(uint8_t *base, uint32_t offset, uint32_t value)
{
	std::memcpy(base + offset, &value, sizeof(value));
}

static void cb_enqueue(void *userdata, unsigned num_words, const uint32_t *words)
{
	auto *h = static_cast<CallbackHarness *>(userdata);
	h->enqueue_calls++;
	h->last_num_words = num_words;
	h->last_words.assign(words, words + num_words);
}

static uint64_t cb_signal(void *userdata)
{
	auto *h = static_cast<CallbackHarness *>(userdata);
	h->signal_calls++;
	h->order.push_back(1);
	return h->signal_value;
}

static void cb_wait(void *userdata, uint64_t timeline)
{
	auto *h = static_cast<CallbackHarness *>(userdata);
	h->wait_calls++;
	h->order.push_back(2);
	h->waited_timeline = timeline;
	h->wait_timeline_matches_signal = (timeline == h->signal_value);
}

static void cb_interrupt(void *userdata)
{
	auto *h = static_cast<CallbackHarness *>(userdata);
	h->interrupt_calls++;
	h->order.push_back(3);
}

static CommandIngestHooks make_hooks(CallbackHarness &h, bool frontend, bool synchronous)
{
	CommandIngestHooks hooks = {};
	hooks.frontend_available = frontend;
	hooks.synchronous = synchronous;
	hooks.userdata = &h;
	hooks.enqueue_command = &cb_enqueue;
	hooks.signal_timeline = &cb_signal;
	hooks.wait_for_timeline = &cb_wait;
	hooks.raise_dp_interrupt = &cb_interrupt;
	return hooks;
}

static void test_dram_path_alignment_and_enqueue()
{
	std::vector<uint32_t> dram_words(0x2000 / 4, 0);
	std::vector<uint32_t> dmem_words(0x1000 / 4, 0);
	uint8_t *dram = reinterpret_cast<uint8_t *>(dram_words.data());
	uint8_t *dmem = reinterpret_cast<uint8_t *>(dmem_words.data());

	write_u32(dram, 0x00, 0x08000000u); // opcode 8, length 4.
	write_u32(dram, 0x04, 0x11111111u);
	write_u32(dram, 0x08, 0x22222222u);
	write_u32(dram, 0x0c, 0x33333333u);
	write_u32(dram, 0x10, 0x44444444u);
	write_u32(dram, 0x14, 0x55555555u);
	write_u32(dram, 0x18, 0x66666666u);
	write_u32(dram, 0x1c, 0x77777777u);

	std::array<uint32_t, 64> cmd_data = {};
	CommandIngestState state = {};
	state.cmd_data = cmd_data.data();

	uint32_t dpc_start = 0x111u;
	uint32_t dpc_end = 0x25u;
	uint32_t dpc_current = 0x5u;
	uint32_t dpc_status = DP_STATUS_FREEZE;
	CallbackHarness h = {};
	CommandIngestHooks hooks = make_hooks(h, true, false);

	process_command_ingest(state, dram, dmem, dpc_start, dpc_end, dpc_current, dpc_status, hooks);

	check((dpc_status & DP_STATUS_FREEZE) == 0, "DP_STATUS_FREEZE should be cleared");
	check(h.enqueue_calls == 1, "expected one enqueue call for opcode 8");
	check(h.last_num_words == 8, "unexpected enqueue word count");
	check(h.last_words.size() == 8, "unexpected payload length");
	check(h.last_words[0] == 0x08000000u, "unexpected payload word 0");
	check(h.last_words[1] == 0x11111111u, "unexpected payload word 1");
	check(h.interrupt_calls == 0, "unexpected interrupt call");
	check(state.cmd_cur == 0 && state.cmd_ptr == 0, "state should reset after complete parse");
	check(dpc_start == dpc_end && dpc_current == dpc_end, "DPC start/current should reset to end");
}

static void test_xbus_path_alignment_and_syncfull_interrupt()
{
	std::vector<uint32_t> dram_words(0x2000 / 4, 0);
	std::vector<uint32_t> dmem_words(0x1000 / 4, 0);
	uint8_t *dram = reinterpret_cast<uint8_t *>(dram_words.data());
	uint8_t *dmem = reinterpret_cast<uint8_t *>(dmem_words.data());

	write_u32(dmem, 0x00, 0x07000000u); // ignored if alignment works.
	write_u32(dmem, 0x04, 0xaaaaaaaau);
	write_u32(dmem, 0x08, 0x29000000u); // SyncFull at aligned offset 8.
	write_u32(dmem, 0x0c, 0xbbbbbbbbu);

	std::array<uint32_t, 64> cmd_data = {};
	CommandIngestState state = {};
	state.cmd_data = cmd_data.data();

	uint32_t dpc_start = 0;
	uint32_t dpc_end = 0x11u;
	uint32_t dpc_current = 0x9u;
	uint32_t dpc_status = DP_STATUS_FREEZE | DP_STATUS_XBUS_DMA;
	CallbackHarness h = {};
	CommandIngestHooks hooks = make_hooks(h, false, false);

	process_command_ingest(state, dram, dmem, dpc_start, dpc_end, dpc_current, dpc_status, hooks);

	check(h.enqueue_calls == 0, "frontend disabled should skip enqueue");
	check(h.interrupt_calls == 1, "SyncFull should raise one interrupt");
	check(h.signal_calls == 0 && h.wait_calls == 0, "async mode should not signal/wait");
	check(dpc_start == dpc_end && dpc_current == dpc_end, "DPC start/current should reset to end");
}

static void test_command_buffer_overflow_guard()
{
	std::vector<uint32_t> dram_words(0x2000 / 4, 0);
	std::vector<uint32_t> dmem_words(0x1000 / 4, 0);
	uint8_t *dram = reinterpret_cast<uint8_t *>(dram_words.data());
	uint8_t *dmem = reinterpret_cast<uint8_t *>(dmem_words.data());

	write_u32(dram, 0x00, 0x29000000u);
	write_u32(dram, 0x04, 0);

	std::array<uint32_t, 64> cmd_data = {};
	CommandIngestState state = {};
	state.cmd_data = cmd_data.data();
	state.cmd_ptr = (0x0003FFFF >> 3);

	uint32_t dpc_start = 0x10u;
	uint32_t dpc_end = 0x08u;
	uint32_t dpc_current = 0x00u;
	uint32_t dpc_status = DP_STATUS_FREEZE;
	CallbackHarness h = {};
	CommandIngestHooks hooks = make_hooks(h, true, true);

	process_command_ingest(state, dram, dmem, dpc_start, dpc_end, dpc_current, dpc_status, hooks);

	check(h.enqueue_calls == 0, "overflow guard should bypass enqueue");
	check(h.interrupt_calls == 0, "overflow guard should bypass interrupt");
	check(state.cmd_ptr == int(0x0003FFFF >> 3), "overflow guard should keep cmd_ptr unchanged");
	check(state.cmd_cur == 0, "overflow guard should keep cmd_cur unchanged");
	check(dpc_start == 0x10u && dpc_current == 0x00u, "overflow guard should not reset DPC regs");
	check((dpc_status & DP_STATUS_FREEZE) == 0, "DP_STATUS_FREEZE should still be cleared");
}

static void test_incomplete_command_tail_behavior()
{
	std::vector<uint32_t> dram_words(0x2000 / 4, 0);
	std::vector<uint32_t> dmem_words(0x1000 / 4, 0);
	uint8_t *dram = reinterpret_cast<uint8_t *>(dram_words.data());
	uint8_t *dmem = reinterpret_cast<uint8_t *>(dmem_words.data());

	write_u32(dram, 0x00, 0x08000000u); // opcode 8 requires 4 qwords, but we only provide 1.
	write_u32(dram, 0x04, 0x11111111u);

	std::array<uint32_t, 64> cmd_data = {};
	CommandIngestState state = {};
	state.cmd_data = cmd_data.data();

	uint32_t dpc_start = 0x500u;
	uint32_t dpc_end = 0x08u;
	uint32_t dpc_current = 0x00u;
	uint32_t dpc_status = 0;
	CallbackHarness h = {};
	CommandIngestHooks hooks = make_hooks(h, true, false);

	process_command_ingest(state, dram, dmem, dpc_start, dpc_end, dpc_current, dpc_status, hooks);

	check(h.enqueue_calls == 0, "incomplete tail should not enqueue");
	check(h.interrupt_calls == 0, "incomplete tail should not interrupt");
	check(state.cmd_ptr == 1 && state.cmd_cur == 0, "incomplete tail should keep parser state pending");
	check(dpc_start == dpc_end && dpc_current == dpc_end, "incomplete tail should set DPC start/current to end");
}

static void test_syncfull_synchronous_ordering()
{
	std::vector<uint32_t> dram_words(0x2000 / 4, 0);
	std::vector<uint32_t> dmem_words(0x1000 / 4, 0);
	uint8_t *dram = reinterpret_cast<uint8_t *>(dram_words.data());
	uint8_t *dmem = reinterpret_cast<uint8_t *>(dmem_words.data());

	write_u32(dram, 0x00, 0x29000000u);
	write_u32(dram, 0x04, 0xfeedfaceu);

	std::array<uint32_t, 64> cmd_data = {};
	CommandIngestState state = {};
	state.cmd_data = cmd_data.data();

	uint32_t dpc_start = 0;
	uint32_t dpc_end = 0x08u;
	uint32_t dpc_current = 0x00u;
	uint32_t dpc_status = 0;
	CallbackHarness h = {};
	CommandIngestHooks hooks = make_hooks(h, true, true);

	process_command_ingest(state, dram, dmem, dpc_start, dpc_end, dpc_current, dpc_status, hooks);

	check(h.enqueue_calls == 1, "SyncFull should enqueue when frontend is present");
	check(h.signal_calls == 1, "synchronous SyncFull should signal once");
	check(h.wait_calls == 1, "synchronous SyncFull should wait once");
	check(h.wait_timeline_matches_signal, "wait should use signaled timeline value");
	check(h.interrupt_calls == 1, "SyncFull should raise interrupt");
	check(h.order.size() == 3, "unexpected callback ordering length");
	check(h.order[0] == 1 && h.order[1] == 2 && h.order[2] == 3,
	      "expected callback ordering signal->wait->interrupt");
}

static void test_commands_below_8_do_not_enqueue()
{
	std::vector<uint32_t> dram_words(0x2000 / 4, 0);
	std::vector<uint32_t> dmem_words(0x1000 / 4, 0);
	uint8_t *dram = reinterpret_cast<uint8_t *>(dram_words.data());
	uint8_t *dmem = reinterpret_cast<uint8_t *>(dmem_words.data());

	write_u32(dram, 0x00, 0x07000000u);
	write_u32(dram, 0x04, 0x12345678u);

	std::array<uint32_t, 64> cmd_data = {};
	CommandIngestState state = {};
	state.cmd_data = cmd_data.data();

	uint32_t dpc_start = 0;
	uint32_t dpc_end = 0x08u;
	uint32_t dpc_current = 0x00u;
	uint32_t dpc_status = 0;
	CallbackHarness h = {};
	CommandIngestHooks hooks = make_hooks(h, true, false);

	process_command_ingest(state, dram, dmem, dpc_start, dpc_end, dpc_current, dpc_status, hooks);

	check(h.enqueue_calls == 0, "opcode < 8 should not enqueue");
	check(h.interrupt_calls == 0, "opcode < 8 should not interrupt");
}

static void test_high_address_bits_are_masked_before_dram_guard()
{
	std::vector<uint32_t> dram_words(0x2000 / 4, 0);
	std::vector<uint32_t> dmem_words(0x1000 / 4, 0);
	uint8_t *dram = reinterpret_cast<uint8_t *>(dram_words.data());
	uint8_t *dmem = reinterpret_cast<uint8_t *>(dmem_words.data());

	write_u32(dram, 0x00, 0x29000000u);
	write_u32(dram, 0x04, 0xdecafbad);

	std::array<uint32_t, 64> cmd_data = {};
	CommandIngestState state = {};
	state.cmd_data = cmd_data.data();

	uint32_t dpc_start = 0;
	uint32_t dpc_end = 0x81000008u;
	uint32_t dpc_current = 0x81000000u;
	uint32_t dpc_status = 0;
	CallbackHarness h = {};
	CommandIngestHooks hooks = make_hooks(h, false, false);

	process_command_ingest(state, dram, dmem, dpc_start, dpc_end, dpc_current, dpc_status, hooks);

	check(h.interrupt_calls == 1, "high address bits should be masked, allowing command decode");
	check(dpc_start == dpc_end && dpc_current == dpc_end, "DPC start/current should reset to end");
}
}

int main()
{
	test_dram_path_alignment_and_enqueue();
	test_xbus_path_alignment_and_syncfull_interrupt();
	test_command_buffer_overflow_guard();
	test_incomplete_command_tail_behavior();
	test_syncfull_synchronous_ordering();
	test_commands_below_8_do_not_enqueue();
	test_high_address_bits_are_masked_before_dram_guard();
	std::cout << "emu_unit_rdp_command_ingest_test: PASS" << std::endl;
	return 0;
}
