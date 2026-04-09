#include "mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_hires_cache_source_policy.hpp"

#include <cstdlib>
#include <iostream>

namespace
{
using RDP::ReplacementProvider;
using RDP::detail::configured_hires_cache_source_policy;
using RDP::detail::hires_cache_source_policy_name;
using RDP::detail::parse_hires_cache_source_policy_env;
using RDP::detail::resolve_hires_cache_source_policy;

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

static void test_configured_policy_mapping()
{
	check(configured_hires_cache_source_policy(0) == ReplacementProvider::CacheSourcePolicy::Auto,
	      "configured auto mode should map to auto");
	check(configured_hires_cache_source_policy(1) == ReplacementProvider::CacheSourcePolicy::PHRBOnly,
	      "configured mode 1 should map to phrb-only");
	check(configured_hires_cache_source_policy(2) == ReplacementProvider::CacheSourcePolicy::LegacyOnly,
	      "configured mode 2 should map to legacy-only");
	check(configured_hires_cache_source_policy(3) == ReplacementProvider::CacheSourcePolicy::All,
	      "configured mode 3 should map to all");
	check(configured_hires_cache_source_policy(99) == ReplacementProvider::CacheSourcePolicy::Auto,
	      "unknown configured modes should fall back to auto");
}

static void test_resolve_policy_prefers_env_when_present()
{
	check(resolve_hires_cache_source_policy(1, nullptr) == ReplacementProvider::CacheSourcePolicy::PHRBOnly,
	      "configured mode should apply when no env override is present");
	check(resolve_hires_cache_source_policy(2, "") == ReplacementProvider::CacheSourcePolicy::LegacyOnly,
	      "empty env override should keep configured mode");
	check(resolve_hires_cache_source_policy(2, "all") == ReplacementProvider::CacheSourcePolicy::All,
	      "explicit env override should beat configured mode");
	check(resolve_hires_cache_source_policy(1, "legacy-only") == ReplacementProvider::CacheSourcePolicy::LegacyOnly,
	      "env override should be parsed with normal aliases");
	check(resolve_hires_cache_source_policy(3, "bogus") == ReplacementProvider::CacheSourcePolicy::Auto,
	      "invalid env overrides should still follow env parse fallback semantics");
}
}

int main()
{
	test_parse_defaults_and_aliases();
	test_parse_invalid_tokens_fall_back_to_auto();
	test_policy_name_round_trip();
	test_configured_policy_mapping();
	test_resolve_policy_prefers_env_when_present();
	std::cout << "emu_unit_rdp_hires_cache_source_policy_test: PASS" << std::endl;
	return 0;
}
