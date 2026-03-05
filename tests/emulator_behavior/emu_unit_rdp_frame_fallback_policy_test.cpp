#include "mupen64plus-video-paraLLEl/rdp_frame_fallback_policy.hpp"

#include <cstdlib>
#include <iostream>
#include <vector>

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

static void test_frontend_available_bypasses_fallback_path()
{
	unsigned error_calls = 0;
	unsigned next_calls = 0;

	const bool used_fallback = handle_complete_frame_fallback(
			true,
			true,
			[&]() {
				error_calls++;
			},
			[&]() {
				next_calls++;
			});

	check(!used_fallback, "frontend-available path should bypass fallback");
	check(error_calls == 0, "error frame should not run when frontend is available");
	check(next_calls == 0, "next-frame context should not advance on bypass path");
}

static void test_frontend_missing_runs_error_then_next_context()
{
	std::vector<int> order;

	const bool used_fallback = handle_complete_frame_fallback(
			false,
			true,
			[&]() {
				order.push_back(1);
			},
			[&]() {
				order.push_back(2);
			});

	check(used_fallback, "frontend-missing path should be handled by fallback");
	check(order.size() == 2, "frontend-missing path should execute two fallback steps");
	check(order[0] == 1 && order[1] == 2, "fallback ordering should be error frame then next-context");
}

static void test_frontend_missing_with_no_device_short_circuits_safely()
{
	unsigned error_calls = 0;
	unsigned next_calls = 0;

	const bool used_fallback = handle_complete_frame_fallback(
			false,
			false,
			[&]() {
				error_calls++;
			},
			[&]() {
				next_calls++;
			});

	check(used_fallback, "frontend-missing path should still be consumed even without device");
	check(error_calls == 0, "error frame should not run without a device");
	check(next_calls == 0, "next-frame context should not run without a device");
}
}

int main()
{
	test_frontend_available_bypasses_fallback_path();
	test_frontend_missing_runs_error_then_next_context();
	test_frontend_missing_with_no_device_short_circuits_safely();
	std::cout << "emu_unit_rdp_frame_fallback_policy_test: PASS" << std::endl;
	return 0;
}
