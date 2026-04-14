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

require_pattern 'source "$SCRIPT_DIR/lib/common.sh"' \
  "shared PHRB authority runner should source the shared scenario helpers"
require_pattern 'if ! scenario_require_phrb_runtime_cache "$CACHE_PATH"; then' \
  "shared PHRB authority runner should use the shared case-insensitive PHRB validator"
require_pattern 'f"- Expected source mode: `{expected_source_mode}`"' \
  "shared PHRB authority markdown summary should include expected source mode"
require_pattern 'f"- Descriptor detail: native checksum exact `' \
  "shared PHRB authority markdown summary should include native checksum descriptor detail"
require_pattern '("title-screen", "paper-mario-title-screen")' \
  "shared PHRB authority runner should keep the title-screen fixture"
require_pattern '("file-select", "paper-mario-file-select")' \
  "shared PHRB authority runner should keep the file-select fixture"
require_pattern '("kmr-03-entry-5", "paper-mario-kmr-03-entry-5")' \
  "shared PHRB authority runner should keep the kmr-03-entry-5 fixture"

echo "emu_paper_mario_phrb_authority_validation_contract: PASS"
