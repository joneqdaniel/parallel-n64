#include "mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_hires_runtime_config.hpp"

#include <cstdlib>
#include <iostream>

namespace
{
using RDP::detail::HiresGlideN64CompatCRCOverride;
using RDP::detail::parse_hires_gliden64_compat_crc_override;
using RDP::detail::resolve_hires_gliden64_compat_crc_auto_enabled;
using RDP::detail::resolve_hires_gliden64_compat_crc_enabled;

static void check(bool condition, const char *message)
{
	if (!condition)
	{
		std::cerr << "FAIL: " << message << std::endl;
		std::exit(1);
	}
}

static void test_compat_crc_override_parsing()
{
	HiresGlideN64CompatCRCOverride unset = parse_hires_gliden64_compat_crc_override(nullptr);
	check(!unset.present, "missing compat CRC env should not create an override");
	check(!unset.enabled, "missing compat CRC env should default the override payload to false");

	HiresGlideN64CompatCRCOverride disabled = parse_hires_gliden64_compat_crc_override("0");
	check(disabled.present, "compat CRC env should mark the override as present");
	check(!disabled.enabled, "compat CRC env=0 should disable the fallback");

	HiresGlideN64CompatCRCOverride enabled = parse_hires_gliden64_compat_crc_override("1");
	check(enabled.present, "compat CRC env should mark the override as present");
	check(enabled.enabled, "compat CRC env=1 should enable the fallback");
}

static void test_compat_crc_resolution_prefers_explicit_override()
{
	check(!resolve_hires_gliden64_compat_crc_enabled({}, false),
	      "no override and no auto-enable policy should keep the fallback disabled");
	check(resolve_hires_gliden64_compat_crc_enabled({}, true),
	      "compat-bearing PHRB auto-enable should enable the fallback when no env override is present");
	check(!resolve_hires_gliden64_compat_crc_enabled({true, false}, true),
	      "explicit env=0 should beat compat-bearing PHRB auto-enable");
	check(resolve_hires_gliden64_compat_crc_enabled({true, true}, false),
	      "explicit env=1 should beat a missing auto-enable default");
	check(!resolve_hires_gliden64_compat_crc_enabled({}, false),
	      "pure native loads should stay compat-disabled by default");
}

static void test_compat_crc_auto_enable_matrix()
{
	check(!resolve_hires_gliden64_compat_crc_auto_enabled(false),
	      "pure native loads should not auto-enable compat CRC");
	check(resolve_hires_gliden64_compat_crc_auto_enabled(true),
	      "compat-bearing PHRB loads should auto-enable compat CRC");
}
}

int main()
{
	test_compat_crc_override_parsing();
	test_compat_crc_resolution_prefers_explicit_override();
	test_compat_crc_auto_enable_matrix();
	std::cout << "emu_unit_rdp_hires_compat_crc_override_test: PASS" << std::endl;
	return 0;
}
