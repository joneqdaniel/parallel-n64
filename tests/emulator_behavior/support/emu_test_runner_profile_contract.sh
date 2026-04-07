#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
RUNNER="$REPO_ROOT/run-tests.sh"

if [[ ! -f "$RUNNER" ]]; then
  echo "FAIL: missing run-tests.sh at $RUNNER" >&2
  exit 1
fi

require_pattern() {
  local pattern="$1"
  local message="$2"
  if ! rg -n --fixed-strings -- "$pattern" "$RUNNER" >/dev/null; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

# Help/usage should advertise all maintained profiles.
require_pattern "--profile NAME        Test profile: all|emu-required|emu-optional|emu-conformance|emu-runtime-conformance|emu-dump|emu-tsan" \
  "usage text missing profile list"

# CLI conflict behavior must remain explicit.
require_pattern "--profile cannot be combined with -R." \
  "-R/profile conflict guard message missing"

# Required profile mappings.
require_pattern "ctest_args+=(-R \"^emu\\\\.unit\\\\.\")" \
  "emu-required regex mapping missing"
require_pattern "ctest_args+=(-R \"^emu\\\\.(conformance|dump)\\\\.\")" \
  "emu-optional regex mapping missing"
require_pattern "ctest_args+=(-R \"^emu\\\\.conformance\\\\.\")" \
  "emu-conformance regex mapping missing"
require_pattern "ctest_args+=(-R \"^emu\\\\.dump\\\\.\")" \
  "emu-dump regex mapping missing"

# Runtime conformance profile should include all dedicated lavapipe runtime tests.
require_pattern "ctest_args+=(-R \"^emu\\\\.conformance\\\\.(runtime_smoke_lavapipe|lavapipe_frame_hash|lavapipe_vi_filters_hash|lavapipe_vi_filters_mixed_hash|lavapipe_vi_downscale_hash|lavapipe_sm64_frame_hash|paper_mario_selected_package_authorities|paper_mario_selected_package_timeout_validation)$\")" \
  "emu-runtime-conformance regex mapping missing expected runtime tests"
require_pattern "export EMU_ENABLE_RUNTIME_CONFORMANCE=1" \
  "emu-runtime-conformance env enablement missing"

# TSAN profile should stay scoped to race-sensitive unit tests.
require_pattern "ctest_args+=(-R \"^emu\\\\.unit\\\\.(command_ring_policy|worker_thread)$\")" \
  "emu-tsan regex mapping missing"
require_pattern 'BUILD_DIR="$SCRIPT_DIR/build/ctest-tsan"' \
  "emu-tsan default build dir mapping missing"

# TSAN preflight/force override must remain available.
require_pattern 'if (( enable_tsan )) && [[ "${EMU_TSAN_FORCE:-0}" != "1" ]]; then' \
  "tsan force override guard missing"
require_pattern "[tests] emu-tsan skipped: ThreadSanitizer is unavailable in this environment." \
  "tsan skip messaging missing"

# Unknown profile should remain a hard error path.
require_pattern 'Unknown --profile value: $selected_profile' \
  "unknown-profile error path missing"

echo "emu_test_runner_profile_contract: PASS"
