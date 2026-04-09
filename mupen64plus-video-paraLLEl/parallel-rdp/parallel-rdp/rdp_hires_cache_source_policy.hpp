#pragma once

#include "texture_replacement.hpp"

#include <string>

namespace RDP::detail
{
inline ReplacementProvider::CacheSourcePolicy configured_hires_cache_source_policy(unsigned mode)
{
	switch (mode)
	{
	case 1:
		return ReplacementProvider::CacheSourcePolicy::PHRBOnly;
	case 2:
		return ReplacementProvider::CacheSourcePolicy::LegacyOnly;
	case 3:
		return ReplacementProvider::CacheSourcePolicy::All;
	case 0:
	default:
		return ReplacementProvider::CacheSourcePolicy::Auto;
	}
}

inline ReplacementProvider::CacheSourcePolicy parse_hires_cache_source_policy_env(const char *env)
{
	if (!env || !*env)
		return ReplacementProvider::CacheSourcePolicy::Auto;

	std::string token(env);
	for (char &c : token)
	{
		if (c >= 'A' && c <= 'Z')
			c = char(c - 'A' + 'a');
	}

	if (token == "auto")
		return ReplacementProvider::CacheSourcePolicy::Auto;
	if (token == "phrb-only" || token == "phrb")
		return ReplacementProvider::CacheSourcePolicy::PHRBOnly;
	if (token == "legacy-only" || token == "legacy")
		return ReplacementProvider::CacheSourcePolicy::LegacyOnly;
	if (token == "all")
		return ReplacementProvider::CacheSourcePolicy::All;
	return ReplacementProvider::CacheSourcePolicy::Auto;
}

inline ReplacementProvider::CacheSourcePolicy resolve_hires_cache_source_policy(unsigned configured_mode, const char *env)
{
	if (env && *env)
		return parse_hires_cache_source_policy_env(env);
	return configured_hires_cache_source_policy(configured_mode);
}

inline const char *hires_cache_source_policy_name(ReplacementProvider::CacheSourcePolicy policy)
{
	switch (policy)
	{
	case ReplacementProvider::CacheSourcePolicy::Auto:
		return "auto";
	case ReplacementProvider::CacheSourcePolicy::PHRBOnly:
		return "phrb-only";
	case ReplacementProvider::CacheSourcePolicy::LegacyOnly:
		return "legacy-only";
	case ReplacementProvider::CacheSourcePolicy::All:
	default:
		return "all";
	}
}
}
