#include "mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_memory_path_policy.hpp"

#include <cstdlib>
#include <iostream>

using namespace RDP;

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

static void test_env_toggle_parse()
{
	check(detail::allow_external_host_from_env(nullptr), "unset env should default to enabled");
	check(detail::allow_external_host_from_env("1"), "positive env should enable external host");
	check(!detail::allow_external_host_from_env("0"), "zero env should disable external host");
	check(!detail::allow_external_host_from_env("-1"), "negative env should disable external host");
}

static void test_imported_size_alignment()
{
	check(detail::align_imported_host_size(8 * 1024 * 1024, 1024, 64 * 1024) == 8454144u,
	      "aligned import size mismatch");
	check(detail::align_imported_host_size(4096u, 256u, 0u) == 4352u,
	      "zero-alignment path should preserve raw sum");
}

static void test_memory_path_decision_matrix()
{
	const size_t rdram_size = 8 * 1024 * 1024;
	const size_t rdram_offset = 4096;
	const size_t alignment = 64 * 1024;

	auto decision = detail::decide_rdram_memory_path(
			true, true, rdram_size, rdram_offset, alignment, nullptr);
	check(decision.use_external_host_import, "supported+enabled should choose imported host path");
	check(!decision.fallback_to_device_buffer, "supported+enabled should avoid fallback path");
	check(decision.host_coherent, "supported+enabled path should stay host coherent");
	check(decision.effective_rdram_offset == rdram_offset, "import path should preserve original offset");
	check(decision.imported_size == detail::align_imported_host_size(rdram_size, rdram_offset, alignment),
	      "import path aligned size mismatch");

	decision = detail::decide_rdram_memory_path(
			true, true, rdram_size, rdram_offset, alignment, "0");
	check(!decision.use_external_host_import, "env disable should force fallback");
	check(decision.fallback_to_device_buffer, "env disable should force fallback path");
	check(!decision.host_coherent, "fallback should mark host coherence false");
	check(decision.effective_rdram_offset == 0u, "fallback should reset effective offset to zero");
	check(decision.imported_size == rdram_size, "fallback should keep default import size sentinel");

	decision = detail::decide_rdram_memory_path(
			true, false, rdram_size, rdram_offset, alignment, "1");
	check(!decision.use_external_host_import, "unsupported feature should force fallback even when env enabled");
	check(decision.fallback_to_device_buffer, "unsupported feature should force fallback path");

	decision = detail::decide_rdram_memory_path(
			false, true, rdram_size, rdram_offset, alignment, nullptr);
	check(!decision.use_external_host_import && !decision.fallback_to_device_buffer,
	      "no-rdram-pointer path should skip import/fallback selection");
	check(decision.host_coherent, "no-rdram-pointer path should remain coherent by default");
	check(decision.effective_rdram_offset == rdram_offset,
	      "no-rdram-pointer path should preserve original offset metadata");
}
}

int main()
{
	test_env_toggle_parse();
	test_imported_size_alignment();
	test_memory_path_decision_matrix();
	std::cout << "emu_unit_rdp_memory_path_policy_test: PASS" << std::endl;
	return 0;
}
