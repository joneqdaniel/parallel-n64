#include "mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_hires_cache_source_policy.hpp"

#include <cstdlib>
#include <iostream>

namespace
{
using RDP::ReplacementProvider;
using RDP::detail::hires_cache_source_policy_name;
using RDP::detail::parse_hires_cache_source_policy_env;

static void check(bool condition, const char *message)
{
	if (!condition)
	{
		std::cerr << "FAIL: " << message << std::endl;
		std::exit(1);
	}
}

static void test_parse_defaults_and_aliases()
{
	check(parse_hires_cache_source_policy_env(nullptr) == ReplacementProvider::CacheSourcePolicy::Auto,
	      "null runtime source env should default to auto");
	check(parse_hires_cache_source_policy_env("") == ReplacementProvider::CacheSourcePolicy::Auto,
	      "empty runtime source env should default to auto");
	check(parse_hires_cache_source_policy_env("auto") == ReplacementProvider::CacheSourcePolicy::Auto,
	      "auto should parse as auto");
	check(parse_hires_cache_source_policy_env("AUTO") == ReplacementProvider::CacheSourcePolicy::Auto,
	      "auto should parse case-insensitively");
	check(parse_hires_cache_source_policy_env("phrb-only") == ReplacementProvider::CacheSourcePolicy::PHRBOnly,
	      "phrb-only should parse as phrb-only");
	check(parse_hires_cache_source_policy_env("PHRB") == ReplacementProvider::CacheSourcePolicy::PHRBOnly,
	      "phrb alias should parse case-insensitively");
	check(parse_hires_cache_source_policy_env("legacy-only") == ReplacementProvider::CacheSourcePolicy::LegacyOnly,
	      "legacy-only should parse as legacy-only");
	check(parse_hires_cache_source_policy_env("legacy") == ReplacementProvider::CacheSourcePolicy::LegacyOnly,
	      "legacy alias should parse as legacy-only");
	check(parse_hires_cache_source_policy_env("all") == ReplacementProvider::CacheSourcePolicy::All,
	      "all should remain an explicit opt-out token");
}

static void test_parse_invalid_tokens_fall_back_to_auto()
{
	check(parse_hires_cache_source_policy_env("bogus") == ReplacementProvider::CacheSourcePolicy::Auto,
	      "invalid runtime source tokens should fall back to auto");
	check(parse_hires_cache_source_policy_env("native-first") == ReplacementProvider::CacheSourcePolicy::Auto,
	      "unknown aliases should not silently broaden back to all");
}

static void test_policy_name_round_trip()
{
	check(std::string(hires_cache_source_policy_name(ReplacementProvider::CacheSourcePolicy::Auto)) == "auto",
	      "auto policy name should round-trip");
	check(std::string(hires_cache_source_policy_name(ReplacementProvider::CacheSourcePolicy::PHRBOnly)) == "phrb-only",
	      "phrb-only policy name should round-trip");
	check(std::string(hires_cache_source_policy_name(ReplacementProvider::CacheSourcePolicy::LegacyOnly)) == "legacy-only",
	      "legacy-only policy name should round-trip");
	check(std::string(hires_cache_source_policy_name(ReplacementProvider::CacheSourcePolicy::All)) == "all",
	      "all policy name should round-trip");
}
}

int main()
{
	test_parse_defaults_and_aliases();
	test_parse_invalid_tokens_fall_back_to_auto();
	test_policy_name_round_trip();
	std::cout << "emu_unit_rdp_hires_cache_source_policy_test: PASS" << std::endl;
	return 0;
}
