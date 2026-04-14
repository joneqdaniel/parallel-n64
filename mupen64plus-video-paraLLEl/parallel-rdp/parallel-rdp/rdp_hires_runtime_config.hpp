#pragma once

#include <cstdlib>
#include <string>

namespace RDP::detail
{

struct HiresGlideN64CompatCRCOverride
{
	bool present = false;
	bool enabled = false;
};

inline bool resolve_hires_gliden64_compat_crc_auto_enabled(bool has_phrb_compat_entries)
{
	return has_phrb_compat_entries;
}

inline HiresGlideN64CompatCRCOverride parse_hires_gliden64_compat_crc_override(const char *env)
{
	HiresGlideN64CompatCRCOverride result = {};
	if (!env)
		return result;

	result.present = true;
	result.enabled = strtol(env, nullptr, 0) > 0;
	return result;
}

inline bool resolve_hires_gliden64_compat_crc_enabled(HiresGlideN64CompatCRCOverride override_policy,
                                                       bool auto_enable_default)
{
	return override_policy.present ? override_policy.enabled : auto_enable_default;
}
}
