#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
RUNNER="$REPO_ROOT/tools/scenarios/paper-mario-phrb-authority-validation.sh"

if [[ ! -f "$RUNNER" ]]; then
  echo "FAIL: missing paper-mario-phrb-authority-validation.sh at $RUNNER" >&2
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

require_pattern 'PARALLEL_RDP_HIRES_RUNTIME_SOURCE_MODE="${PARALLEL_RDP_HIRES_RUNTIME_SOURCE_MODE:-phrb-only}"' \
  "shared PHRB authority runner should default runtime source mode to phrb-only"
require_pattern 'EXPECTED_HIRES_SUMMARY_SOURCE_POLICY_ON="$EXPECTED_SOURCE_POLICY"' \
  "shared PHRB authority runner should pass through expected source policy"
require_pattern 'f"- Expected source policy: `{expected_source_policy}`"' \
  "shared PHRB authority markdown summary should include expected source policy"
require_pattern 'f"- Descriptor detail: native checksum exact `' \
  "shared PHRB authority markdown summary should include native checksum descriptor detail"
require_pattern '("title-screen", "paper-mario-title-screen")' \
  "shared PHRB authority runner should keep the title-screen fixture"
require_pattern '("file-select", "paper-mario-file-select")' \
  "shared PHRB authority runner should keep the file-select fixture"
require_pattern '("kmr-03-entry-5", "paper-mario-kmr-03-entry-5")' \
  "shared PHRB authority runner should keep the kmr-03-entry-5 fixture"

echo "emu_paper_mario_phrb_authority_validation_contract: PASS"
