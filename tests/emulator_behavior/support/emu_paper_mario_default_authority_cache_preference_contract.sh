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
FULL_CACHE_CONFORMANCE="$REPO_ROOT/tests/emulator_behavior/support/emu_conformance_paper_mario_full_cache_phrb_authorities.sh"

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
if grep -Fq 'paper-mario-hirestextures-9fa7bc07-all-families/package.phrb' "$COMMON_SH"; then
  echo "FAIL: default cache resolver should not fall back to the zero-config full-cache PHRB artifact." >&2
  exit 1
fi
if grep -Fq 'assets/PAPER MARIO_HIRESTEXTURES.hts' "$COMMON_SH"; then
  echo "FAIL: default cache resolver should no longer fall back to the legacy Paper Mario cache." >&2
  exit 1
fi
require_pattern 'No default Paper Mario PHRB runtime cache found.' "$COMMON_SH" \
  "default cache resolver should fail closed when no promoted PHRB runtime cache is available"

require_pattern 'CACHE_PATH="$ENRICHED_CACHE_PATH_CURRENT"' "$FULL_CACHE_CONFORMANCE" \
  "default full-cache conformance should prefer the current enriched PHRB artifact first"
require_pattern 'CACHE_PATH="$ENRICHED_CACHE_PATH_LEGACY"' "$FULL_CACHE_CONFORMANCE" \
  "default full-cache conformance should preserve the older enriched PHRB artifact as fallback"
if grep -Fq 'CACHE_PATH="$ZERO_CONFIG_CACHE_PATH"' "$FULL_CACHE_CONFORMANCE"; then
  echo "FAIL: default full-cache conformance should not fall back to the zero-config PHRB artifact implicitly." >&2
  exit 1
fi

for scenario in "$TITLE_SCENARIO" "$FILE_SCENARIO" "$KMR_SCENARIO"; do
  require_pattern 'PACK_PATH="$(scenario_default_paper_mario_hires_cache "$REPO_ROOT")"' "$scenario" \
    "authority scenarios should default to the shared Paper Mario cache resolver"
done

require_pattern 'EXPECTED_SCREENSHOT_SHA256_ON="5da2429afbddfb37b15c5dcb598fa0cc4c3213fd7cddf6cfa5822047db99cb26"' "$TITLE_ENV" \
  "title-screen runtime env should track the enriched full-cache PHRB authority hash"
require_pattern 'EXPECTED_SCREENSHOT_SHA256_ON="b5649593babbd9d6e677cb750cf7fa62b4fbe3254e9108460b9e49fb2cb53f26"' "$FILE_ENV" \
  "file-select runtime env should track the enriched full-cache PHRB authority hash"
require_pattern 'EXPECTED_SCREENSHOT_SHA256_ON="272bddd5e099b63d878521d33e4dcf0742d7a474117bbe81bc2d65fb1e8695ac"' "$KMR_ENV" \
  "kmr_03 runtime env should track the enriched full-cache PHRB authority hash"

for runtime_env in "$TITLE_ENV" "$FILE_ENV" "$KMR_ENV"; do
  require_pattern 'EXPECTED_HIRES_SUMMARY_SOURCE_MODE_ON="phrb-only"' "$runtime_env" \
    "runtime envs should require phrb-only source mode on the promoted authority lane"
  require_pattern 'EXPECTED_HIRES_MIN_SUMMARY_NATIVE_SAMPLED_ENTRY_COUNT_ON="1"' "$runtime_env" \
    "runtime envs should require native sampled entries on the promoted authority lane"
  require_pattern 'EXPECTED_HIRES_MIN_SUMMARY_SOURCE_PHRB_COUNT_ON="1"' "$runtime_env" \
    "runtime envs should require PHRB-backed entries on the promoted authority lane"
done

echo "emu_paper_mario_default_authority_cache_preference_contract: PASS"
