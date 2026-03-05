#include "mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_hires_state_policy.hpp"

#include <cstdlib>
#include <iostream>
#include <cstdint>

using namespace RDP::detail;

namespace
{
struct TileState
{
	uint64_t checksum64 = 0;
	uint16_t formatsize = 0;
	uint16_t orig_w = 0;
	uint16_t orig_h = 0;
	bool valid = false;
	bool hit = false;
};

static void check(bool condition, const char *message)
{
	if (!condition)
	{
		std::cerr << "FAIL: " << message << std::endl;
		std::exit(1);
	}
}

static void test_reset_hires_tracking_state_clears_all_fields()
{
	TileState tiles[4] = {};
	for (unsigned i = 0; i < 4; i++)
	{
		tiles[i].checksum64 = 0x1234567800000000ull | i;
		tiles[i].formatsize = static_cast<uint16_t>(0x100u + i);
		tiles[i].orig_w = static_cast<uint16_t>(64u + i);
		tiles[i].orig_h = static_cast<uint16_t>(32u + i);
		tiles[i].valid = true;
		tiles[i].hit = (i & 1u) != 0;
	}

	bool tlut_shadow_valid = true;
	uint64_t lookup_total = 77;
	uint64_t lookup_hits = 55;
	uint64_t lookup_misses = 22;

	reset_hires_tracking_state(tiles, tlut_shadow_valid, lookup_total, lookup_hits, lookup_misses);

	for (unsigned i = 0; i < 4; i++)
	{
		check(tiles[i].checksum64 == 0, "tile checksum should reset");
		check(tiles[i].formatsize == 0, "tile formatsize should reset");
		check(tiles[i].orig_w == 0 && tiles[i].orig_h == 0, "tile dimensions should reset");
		check(!tiles[i].valid, "tile valid bit should reset");
		check(!tiles[i].hit, "tile hit bit should reset");
	}
	check(!tlut_shadow_valid, "tlut shadow validity should reset");
	check(lookup_total == 0 && lookup_hits == 0 && lookup_misses == 0,
	      "lookup counters should reset");
}

static void test_hires_provider_changed_contract()
{
	const void *p0 = nullptr;
	const void *p1 = reinterpret_cast<const void *>(uintptr_t(0x1000));
	const void *p2 = reinterpret_cast<const void *>(uintptr_t(0x2000));

	check(!hires_provider_changed(p0, p0), "null->null should not count as changed");
	check(hires_provider_changed(p0, p1), "null->provider should count as changed");
	check(!hires_provider_changed(p1, p1), "same provider pointer should not count as changed");
	check(hires_provider_changed(p1, p2), "different provider pointers should count as changed");
	check(hires_provider_changed(p1, p0), "provider->null should count as changed");
}
}

int main()
{
	test_reset_hires_tracking_state_clears_all_fields();
	test_hires_provider_changed_contract();
	std::cout << "emu_unit_hires_state_policy_test: PASS" << std::endl;
	return 0;
}
