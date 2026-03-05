#include "mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_hires_lookup_policy.hpp"

#include <cstdint>
#include <cstdlib>
#include <iostream>

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

static void test_hires_rdram_view_valid_matrix()
{
	const uint8_t backing[8] = {};
	check(!hires_rdram_view_valid(nullptr, 8), "null rdram pointer should be invalid");
	check(!hires_rdram_view_valid(backing, 0), "zero rdram size should be invalid");
	check(!hires_rdram_view_valid(backing, 3), "non-power-of-two rdram size should be invalid");
	check(hires_rdram_view_valid(backing, 8), "power-of-two rdram view should be valid");
}

static void test_tlut_shadow_gate()
{
	check(should_update_tlut_shadow(true, true), "tlut shadow should run when rdram view is valid and mode is TLUT");
	check(!should_update_tlut_shadow(false, true), "tlut shadow should not run with invalid rdram view");
	check(!should_update_tlut_shadow(true, false), "tlut shadow should not run outside TLUT mode");
}

static void test_hires_lookup_fast_path_gate()
{
	check(!should_run_hires_lookup(false, true, false, 64, 64), "lookup should not run with invalid rdram view");
	check(!should_run_hires_lookup(true, false, false, 64, 64), "lookup should not run when provider is unavailable");
	check(!should_run_hires_lookup(true, true, true, 64, 64), "lookup should not run in TLUT mode");
	check(!should_run_hires_lookup(true, true, false, 0, 64), "lookup should not run with zero width");
	check(!should_run_hires_lookup(true, true, false, 64, 0), "lookup should not run with zero height");
	check(should_run_hires_lookup(true, true, false, 64, 64), "lookup should run when all prerequisites are met");
}

static void test_lookup_counter_updates()
{
	uint64_t total = 10;
	uint64_t hits = 4;
	uint64_t misses = 6;

	record_hires_lookup_result(true, total, hits, misses);
	check(total == 11 && hits == 5 && misses == 6, "hit counter update mismatch");

	record_hires_lookup_result(false, total, hits, misses);
	check(total == 12 && hits == 5 && misses == 7, "miss counter update mismatch");
}
}

int main()
{
	test_hires_rdram_view_valid_matrix();
	test_tlut_shadow_gate();
	test_hires_lookup_fast_path_gate();
	test_lookup_counter_updates();

	std::cout << "emu_unit_hires_lookup_policy_test: PASS" << std::endl;
	return 0;
}
