#include "fake_rdp_seams.hpp"
#include "rdp_memory_fixture.hpp"
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <vector>

using namespace EmuBehaviorTest;

static void check(bool condition, const char *message)
{
	if (!condition)
	{
		std::cerr << "FAIL: " << message << std::endl;
		std::exit(1);
	}
}

int main()
{
	RdpMemoryFixture fixture_a(0xdeadbeefu);
	RdpMemoryFixture fixture_b(0xdeadbeefu);
	RdpMemoryFixture fixture_c(0x12345678u);

	check(fixture_a.digest() == fixture_b.digest(), "fixtures with same seed should match");
	check(fixture_a.digest() != fixture_c.digest(), "fixtures with different seeds should differ");

	GFX_INFO info = fixture_a.to_gfx_info();
	check(info.RDRAM == fixture_a.rdram.data(), "RDRAM pointer mismatch");
	check(info.DMEM == fixture_a.dmem.data(), "DMEM pointer mismatch");
	check(info.IMEM == fixture_a.imem.data(), "IMEM pointer mismatch");
	check(info.DPC_STATUS_REG == &fixture_a.dpc_status_reg, "DPC status pointer mismatch");
	check(info.VI_X_SCALE_REG == &fixture_a.vi_x_scale_reg, "VI X scale pointer mismatch");

	fixture_a.reset_interrupt_counter();
	check(fixture_a.interrupt_counter() == 0, "interrupt counter reset failed");
	check(info.CheckInterrupts != nullptr, "interrupt callback should be set");
	info.CheckInterrupts();
	check(fixture_a.interrupt_counter() == 1, "interrupt callback did not increment");

	FakeVulkanFrontend vulkan = {};
	vulkan.sync_mask = 0x5;
	vulkan.sync_index = 2;
	check(vulkan.get_sync_index_mask() == 0x5, "sync mask mismatch");
	check(vulkan.get_sync_index() == 2, "sync index mismatch");
	vulkan.wait_sync_index();
	vulkan.lock_queue();
	vulkan.unlock_queue();
	vulkan.set_image();
	check(vulkan.wait_sync_calls == 1, "wait_sync count mismatch");
	check(vulkan.lock_calls == 1 && vulkan.unlock_calls == 1, "queue lock/unlock count mismatch");
	check(vulkan.set_image_calls == 1, "set_image count mismatch");

	FakeDeviceBackend device = {};
	device.init_frame_contexts(3);
	const uint64_t t0 = device.write_calibrated_timestamp();
	const uint64_t t1 = device.write_calibrated_timestamp();
	device.register_time_interval("Emulation", t0, t1, "frame");
	device.flush_frame();
	device.next_frame_context();
	check(device.init_frame_context_calls == 1, "init_frame_contexts count mismatch");
	check(device.last_frame_context_count == 3, "frame context count mismatch");
	check(device.write_timestamp_calls == 2, "timestamp call count mismatch");
	check(device.register_interval_calls == 1, "register interval count mismatch");
	check(t1 > t0, "timestamps should be monotonic");

	FakeCommandProcessor frontend = {};
	const std::vector<uint32_t> cmd = {0x29000000u, 0x00000000u};
	frontend.enqueue_command(static_cast<unsigned>(cmd.size()), cmd.data());
	const uint64_t timeline = frontend.signal_timeline();
	frontend.wait_for_timeline(timeline);
	frontend.set_vi_register(13, 0x1234u);
	frontend.begin_frame_context();
	check(frontend.enqueue_calls == 1, "enqueue count mismatch");
	check(frontend.enqueues.size() == 1 && frontend.enqueues[0].payload == cmd, "enqueue payload mismatch");
	check(frontend.signal_calls == 1 && frontend.wait_calls == 1, "timeline call mismatch");
	check(frontend.last_waited_timeline == timeline, "timeline wait value mismatch");
	check(frontend.vi_writes.size() == 1, "VI write count mismatch");
	check(frontend.begin_frame_calls == 1, "begin_frame_context count mismatch");

	std::cout << "emu_unit_smoke_test: PASS" << std::endl;
	return 0;
}
