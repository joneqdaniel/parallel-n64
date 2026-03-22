#pragma once

#include <cstdint>
#include <string>

namespace RDP
{
namespace detail
{
enum class HiresConfigureOutcome
{
	Disabled,
	MissingPath,
	LoadFailed,
	LoadSucceeded
};

inline std::string resolve_hires_cache_path(const std::string &configured_path, const char *env_path)
{
	if (env_path && *env_path)
		return env_path;
	if (!configured_path.empty())
		return configured_path;
	return "";
}

inline bool should_attempt_hires_cache_load(bool enable, const char *cache_path)
{
	return enable && cache_path && *cache_path;
}

inline HiresConfigureOutcome classify_hires_configure_outcome(bool enable, const char *cache_path, bool load_ok)
{
	if (!enable)
		return HiresConfigureOutcome::Disabled;
	if (!cache_path || !*cache_path)
		return HiresConfigureOutcome::MissingPath;
	return load_ok ? HiresConfigureOutcome::LoadSucceeded : HiresConfigureOutcome::LoadFailed;
}

inline bool should_attach_hires_provider(HiresConfigureOutcome outcome)
{
	return outcome == HiresConfigureOutcome::LoadSucceeded;
}

inline constexpr uint32_t hires_invalid_descriptor_index()
{
	return 0xffffffffu;
}

inline bool hires_descriptor_index_valid(uint32_t index)
{
	return index != hires_invalid_descriptor_index();
}
}
}
