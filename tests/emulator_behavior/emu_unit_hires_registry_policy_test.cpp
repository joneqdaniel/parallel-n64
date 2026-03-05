#include "mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_hires_registry_policy.hpp"

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

static void test_state_machine_transitions()
{
	auto state = HiresRegistryResidencyState::Missing;
	state = advance_hires_registry_state(state, HiresRegistryTransition::QueueUpload);
	check(state == HiresRegistryResidencyState::Queued, "missing->queue should transition to queued");

	state = advance_hires_registry_state(state, HiresRegistryTransition::UploadSucceeded);
	check(state == HiresRegistryResidencyState::Ready, "queued->success should transition to ready");

	state = advance_hires_registry_state(state, HiresRegistryTransition::UploadFailed);
	check(state == HiresRegistryResidencyState::Ready, "ready should ignore upload-failed transition");

	state = advance_hires_registry_state(state, HiresRegistryTransition::DisableOrReset);
	check(state == HiresRegistryResidencyState::Missing, "disable/reset should always transition to missing");

	state = advance_hires_registry_state(state, HiresRegistryTransition::QueueUpload);
	state = advance_hires_registry_state(state, HiresRegistryTransition::UploadFailed);
	check(state == HiresRegistryResidencyState::Failed, "queued->failed should transition to failed");

	state = advance_hires_registry_state(state, HiresRegistryTransition::QueueUpload);
	check(state == HiresRegistryResidencyState::Queued, "failed->queue should transition to queued for retry");
}

static void test_upload_queue_gate_contract()
{
	check(!should_queue_hires_upload(HiresRegistryResidencyState::Missing, false, false),
	      "lookup miss should never queue upload");
	check(should_queue_hires_upload(HiresRegistryResidencyState::Missing, true, false),
	      "lookup match in missing state should queue upload");
	check(!should_queue_hires_upload(HiresRegistryResidencyState::Queued, true, false),
	      "already queued entry should not queue upload again");
	check(!should_queue_hires_upload(HiresRegistryResidencyState::Ready, true, true),
	      "ready entry with valid descriptor should not queue upload");
	check(should_queue_hires_upload(HiresRegistryResidencyState::Ready, true, false),
	      "ready entry with invalid descriptor should re-queue upload");
}

static void test_handle_validity_and_allocation_contract()
{
	check(hires_registry_invalid_handle() == 0xffffffffu, "invalid handle sentinel mismatch");
	check(!hires_registry_handle_valid(hires_registry_invalid_handle(), 8), "invalid sentinel should be rejected");
	check(hires_registry_handle_valid(0u, 8), "handle zero should be valid when capacity > 0");
	check(hires_registry_handle_valid(7u, 8), "upper-bound in-range handle should be valid");
	check(!hires_registry_handle_valid(8u, 8), "out-of-range handle should be invalid");
	check(!hires_registry_handle_valid(0u, 0), "zero capacity should reject all handles");

	check(check_hires_registry_handle_allocation(0u, 2u) == HiresRegistryHandleAllocationResult::Allocated,
	      "first handle allocation should succeed");
	check(check_hires_registry_handle_allocation(1u, 2u) == HiresRegistryHandleAllocationResult::Allocated,
	      "last in-range handle allocation should succeed");
	check(check_hires_registry_handle_allocation(2u, 2u) == HiresRegistryHandleAllocationResult::Exhausted,
	      "capacity exhaustion should be reported");
}

static void test_budget_decision_contract()
{
	check(decide_hires_registry_budget(64, 32, 0, false, false) == HiresRegistryBudgetDecision::Admit,
	      "zero budget should represent unlimited policy");
	check(decide_hires_registry_budget(64, 32, 128, false, false) == HiresRegistryBudgetDecision::Admit,
	      "in-budget upload should admit");
	check(decide_hires_registry_budget(64, 96, 128, false, false) == HiresRegistryBudgetDecision::RejectOverBudget,
	      "over-budget upload with eviction disabled should reject");
	check(decide_hires_registry_budget(64, 96, 128, true, true) == HiresRegistryBudgetDecision::EvictOldestThenAdmit,
	      "over-budget upload with eviction enabled and candidate should evict+admit");
	check(decide_hires_registry_budget(64, 96, 128, true, false) == HiresRegistryBudgetDecision::RejectOverBudget,
	      "over-budget upload with no evictable candidate should reject");
}

static void test_eviction_candidate_selection_skips_pinned_entries()
{
	HiresRegistryEntryResidentMeta entries[] = {
		{ true,  true,  1 },
		{ true,  false, 9 },
		{ true,  false, 3 },
		{ false, false, 0 },
	};

	const int index = choose_hires_eviction_candidate(entries, sizeof(entries) / sizeof(entries[0]));
	check(index == 2, "oldest non-pinned resident entry should be selected");

	entries[1].pinned = true;
	entries[2].pinned = true;
	check(choose_hires_eviction_candidate(entries, sizeof(entries) / sizeof(entries[0])) == -1,
	      "all-pinned resident entries should yield no eviction candidate");
}
}

int main()
{
	test_state_machine_transitions();
	test_upload_queue_gate_contract();
	test_handle_validity_and_allocation_contract();
	test_budget_decision_contract();
	test_eviction_candidate_selection_skips_pinned_entries();

	std::cout << "emu_unit_hires_registry_policy_test: PASS" << std::endl;
	return 0;
}
