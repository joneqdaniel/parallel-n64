#include "mupen64plus-video-paraLLEl/rdp_scanout_fallback.hpp"

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <vector>

using namespace RDP;

namespace
{
struct FakeImageHandle
{
	int id = 0;
	explicit operator bool() const
	{
		return id != 0;
	}
};

struct FakeCommandBuffer
{
	std::vector<int> *order = nullptr;
};

static void check(bool condition, const char *message)
{
	if (!condition)
	{
		std::cerr << "FAIL: " << message << std::endl;
		std::exit(1);
	}
}

static void test_make_null_scanout_image_info()
{
	const auto info = detail::make_null_scanout_image_info();
	check(info.width == 1u && info.height == 1u, "fallback image size should be 1x1");
	check(info.format == VK_FORMAT_R8G8B8A8_UNORM, "fallback format mismatch");
	check((info.usage & VK_IMAGE_USAGE_SAMPLED_BIT) != 0, "fallback usage missing SAMPLED");
	check((info.usage & VK_IMAGE_USAGE_TRANSFER_SRC_BIT) != 0, "fallback usage missing TRANSFER_SRC");
	check((info.usage & VK_IMAGE_USAGE_TRANSFER_DST_BIT) != 0, "fallback usage missing TRANSFER_DST");
	check((info.misc & Vulkan::IMAGE_MISC_MUTABLE_SRGB_BIT) != 0, "fallback misc missing mutable sRGB");
	check(info.initial_layout == VK_IMAGE_LAYOUT_UNDEFINED, "fallback initial layout mismatch");
}

static void test_existing_scanout_image_is_preserved()
{
	FakeImageHandle image = { 5 };
	unsigned create_calls = 0;
	unsigned request_calls = 0;
	unsigned submit_calls = 0;

	const FakeImageHandle result = detail::ensure_scanout_image(
			image,
			[&]() {
				create_calls++;
				return FakeImageHandle{7};
			},
			[&]() {
				request_calls++;
				return FakeCommandBuffer{};
			},
			[&](auto &, auto &) {},
			[&](auto &, auto &) {},
			[&](auto &, auto &) {},
			[&](auto &) {
				submit_calls++;
			});

	check(result.id == 5, "existing image should be returned unchanged");
	check(create_calls == 0, "create should not run when image exists");
	check(request_calls == 0, "request_command_buffer should not run when image exists");
	check(submit_calls == 0, "submit should not run when image exists");
}

static void test_missing_scanout_image_executes_fallback_sequence()
{
	FakeImageHandle image = {};
	std::vector<int> order;

	const FakeImageHandle result = detail::ensure_scanout_image(
			image,
			[&]() {
				order.push_back(1); // create
				return FakeImageHandle{7};
			},
			[&]() {
				order.push_back(2); // request cmd
				return FakeCommandBuffer{ &order };
			},
			[&](auto &cmd, auto &target_image) {
				check(cmd.order != nullptr, "cmd should be initialized");
				check(target_image.id == 7, "target image id mismatch in barrier_to_transfer");
				cmd.order->push_back(3);
			},
			[&](auto &cmd, auto &target_image) {
				check(cmd.order != nullptr, "cmd should be initialized");
				check(target_image.id == 7, "target image id mismatch in clear");
				cmd.order->push_back(4);
			},
			[&](auto &cmd, auto &target_image) {
				check(cmd.order != nullptr, "cmd should be initialized");
				check(target_image.id == 7, "target image id mismatch in barrier_to_shader_read");
				cmd.order->push_back(5);
			},
			[&](auto &cmd) {
				check(cmd.order != nullptr, "cmd should be initialized");
				cmd.order->push_back(6); // submit
			});

	check(result.id == 7, "fallback image should be returned");
	check(order.size() == 6, "unexpected fallback sequence length");
	for (int i = 0; i < 6; i++)
		check(order[size_t(i)] == i + 1, "unexpected fallback sequence order");
}
}

int main()
{
	test_make_null_scanout_image_info();
	test_existing_scanout_image_is_preserved();
	test_missing_scanout_image_executes_fallback_sequence();
	std::cout << "emu_unit_rdp_scanout_fallback_test: PASS" << std::endl;
	return 0;
}
