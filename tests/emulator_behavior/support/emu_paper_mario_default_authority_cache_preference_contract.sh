#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
COMMON_SH="$REPO_ROOT/tools/scenarios/lib/common.sh"
TITLE_SCENARIO="$REPO_ROOT/tools/scenarios/paper-mario-title-screen.sh"
FILE_SCENARIO="$REPO_ROOT/tools/scenarios/paper-mario-file-select.sh"
KMR_SCENARIO="$REPO_ROOT/tools/scenarios/paper-mario-kmr-03-entry-5.sh"
TITLE_ENV="$REPO_ROOT/tools/scenarios/paper-mario-title-screen.runtime.env"
FILE_ENV="$REPO_ROOT/tools/scenarios/paper-mario-file-select.runtime.env"
KMR_ENV="$REPO_ROOT/tools/scenarios/paper-mario-kmr-03-entry-5.runtime.env"

require_pattern() {
  local pattern="$1"
  local path="$2"
  local description="$3"
  if ! grep -Fq -- "$pattern" "$path"; then
    echo "FAIL: $description" >&2
    echo "  missing pattern: $pattern" >&2
    echo "  file: $path" >&2
    exit 1
  fi
}

require_pattern 'scenario_default_paper_mario_hires_cache()' "$COMMON_SH" \
  "common scenario helpers should define the Paper Mario default cache resolver"
require_pattern '20260408-pm64-all-families-authority-context-abs-summary/package.phrb' "$COMMON_SH" \
  "default cache resolver should prefer the current enriched full-cache PHRB artifact first"
require_pattern '20260407-pm64-all-families-authority-context-root/package.phrb' "$COMMON_SH" \
  "default cache resolver should preserve the older enriched full-cache PHRB artifact as fallback"
require_pattern 'paper-mario-hirestextures-9fa7bc07-all-families/package.phrb' "$COMMON_SH" \
  "default cache resolver should preserve the zero-config full-cache PHRB artifact as fallback"
require_pattern 'assets/PAPER MARIO_HIRESTEXTURES.hts' "$COMMON_SH" \
  "default cache resolver should still fall back to the legacy Paper Mario cache"

for scenario in "$TITLE_SCENARIO" "$FILE_SCENARIO" "$KMR_SCENARIO"; do
  require_pattern 'PACK_PATH="$(scenario_default_paper_mario_hires_cache "$REPO_ROOT")"' "$scenario" \
    "authority scenarios should default to the shared Paper Mario cache resolver"
done

require_pattern 'EXPECTED_SCREENSHOT_SHA256_ON="0e854083b48ccf48e0a372e39ca439c17f0e66523423fb2c3b68b94181c72ad5"' "$TITLE_ENV" \
  "title-screen runtime env should track the enriched full-cache PHRB authority hash"
require_pattern 'EXPECTED_SCREENSHOT_SHA256_ON="43bd91dab1dfa4001365caee5ba03bc4ae1999fd012f5e943093615b4c858ca9"' "$FILE_ENV" \
  "file-select runtime env should track the enriched full-cache PHRB authority hash"
require_pattern 'EXPECTED_SCREENSHOT_SHA256_ON="212ffb9329b8d78e608874e524534ca54505a26204abe78524ef8fca97a1b638"' "$KMR_ENV" \
  "kmr_03 runtime env should track the enriched full-cache PHRB authority hash"

for runtime_env in "$TITLE_ENV" "$FILE_ENV" "$KMR_ENV"; do
  require_pattern 'EXPECTED_HIRES_SUMMARY_SOURCE_MODE_ON="phrb-only"' "$runtime_env" \
    "runtime envs should require phrb-only source mode on the promoted authority lane"
  require_pattern 'EXPECTED_HIRES_SUMMARY_SOURCE_POLICY_ON="auto"' "$runtime_env" \
    "runtime envs should require the default auto source policy on the promoted authority lane"
  require_pattern 'EXPECTED_HIRES_MIN_SUMMARY_NATIVE_SAMPLED_ENTRY_COUNT_ON="1"' "$runtime_env" \
    "runtime envs should require native sampled entries on the promoted authority lane"
  require_pattern 'EXPECTED_HIRES_MIN_SUMMARY_SOURCE_PHRB_COUNT_ON="1"' "$runtime_env" \
    "runtime envs should require PHRB-backed entries on the promoted authority lane"
done

echo "emu_paper_mario_default_authority_cache_preference_contract: PASS"
