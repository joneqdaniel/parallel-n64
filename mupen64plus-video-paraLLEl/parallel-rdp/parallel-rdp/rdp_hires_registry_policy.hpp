#pragma once

#include <cstddef>
#include <cstdint>

namespace RDP
{
namespace detail
{
enum class HiresRegistryResidencyState
{
	Missing,
	Queued,
	Ready,
	Failed,
};

enum class HiresRegistryTransition
{
	QueueUpload,
	UploadSucceeded,
	UploadFailed,
	DisableOrReset,
};

inline HiresRegistryResidencyState advance_hires_registry_state(
		HiresRegistryResidencyState current,
		HiresRegistryTransition transition)
{
	if (transition == HiresRegistryTransition::DisableOrReset)
		return HiresRegistryResidencyState::Missing;

	switch (current)
	{
	case HiresRegistryResidencyState::Missing:
		return transition == HiresRegistryTransition::QueueUpload ?
		       HiresRegistryResidencyState::Queued :
		       current;

	case HiresRegistryResidencyState::Queued:
		if (transition == HiresRegistryTransition::UploadSucceeded)
			return HiresRegistryResidencyState::Ready;
		if (transition == HiresRegistryTransition::UploadFailed)
			return HiresRegistryResidencyState::Failed;
		return current;

	case HiresRegistryResidencyState::Ready:
		return current;

	case HiresRegistryResidencyState::Failed:
		return transition == HiresRegistryTransition::QueueUpload ?
		       HiresRegistryResidencyState::Queued :
		       current;
	}

	return current;
}

inline constexpr uint32_t hires_registry_invalid_handle()
{
	return 0xffffffffu;
}

inline bool hires_registry_handle_valid(uint32_t handle, uint32_t capacity)
{
	return capacity > 0 &&
	       handle != hires_registry_invalid_handle() &&
	       handle < capacity;
}

enum class HiresRegistryHandleAllocationResult
{
	Allocated,
	Exhausted,
};

inline HiresRegistryHandleAllocationResult check_hires_registry_handle_allocation(
		uint32_t next_handle,
		uint32_t capacity)
{
	return next_handle < capacity ?
	       HiresRegistryHandleAllocationResult::Allocated :
	       HiresRegistryHandleAllocationResult::Exhausted;
}

inline bool should_queue_hires_upload(HiresRegistryResidencyState state,
                                      bool lookup_matched,
                                      bool descriptor_valid)
{
	if (!lookup_matched)
		return false;

	if (state == HiresRegistryResidencyState::Queued)
		return false;

	if (state == HiresRegistryResidencyState::Ready && descriptor_valid)
		return false;

	return true;
}

struct HiresRegistryEntryResidentMeta
{
	bool resident = false;
	bool pinned = false;
	uint64_t last_used_tick = 0;
};

inline int choose_hires_eviction_candidate(const HiresRegistryEntryResidentMeta *entries, size_t count)
{
	if (!entries || count == 0)
		return -1;

	int best = -1;
	for (size_t i = 0; i < count; i++)
	{
		if (!entries[i].resident || entries[i].pinned)
			continue;

		if (best < 0 || entries[i].last_used_tick < entries[best].last_used_tick)
			best = int(i);
	}

	return best;
}

enum class HiresRegistryBudgetDecision
{
	Admit,
	EvictOldestThenAdmit,
	RejectOverBudget,
};

inline HiresRegistryBudgetDecision decide_hires_registry_budget(
		size_t resident_bytes,
		size_t incoming_bytes,
		size_t budget_bytes,
		bool eviction_enabled,
		bool has_evictable_candidate)
{
	if (budget_bytes == 0)
		return HiresRegistryBudgetDecision::Admit;

	if (incoming_bytes > budget_bytes)
		return HiresRegistryBudgetDecision::RejectOverBudget;

	if (resident_bytes <= budget_bytes - incoming_bytes)
		return HiresRegistryBudgetDecision::Admit;

	if (eviction_enabled && has_evictable_candidate)
		return HiresRegistryBudgetDecision::EvictOldestThenAdmit;

	return HiresRegistryBudgetDecision::RejectOverBudget;
}
}
}
