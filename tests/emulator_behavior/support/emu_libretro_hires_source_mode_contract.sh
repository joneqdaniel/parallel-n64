#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
LIBRETRO_C="$REPO_ROOT/libretro/libretro.c"
PARALLEL_H="$REPO_ROOT/mupen64plus-video-paraLLEl/parallel.h"
PARALLEL_CPP="$REPO_ROOT/mupen64plus-video-paraLLEl/parallel.cpp"
RDP_CPP="$REPO_ROOT/mupen64plus-video-paraLLEl/rdp.cpp"
POLICY_HPP="$REPO_ROOT/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_hires_cache_source_policy.hpp"
RDP_DEVICE_CPP="$REPO_ROOT/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_device.cpp"

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

require_pattern 'parallel-n64-parallel-rdp-hirestex-source-mode' "$LIBRETRO_C" \
  "libretro core options should expose the hi-res source-mode setting"
require_pattern 'Hi-res texture source mode (restart); auto|phrb-only|legacy-only|all' "$LIBRETRO_C" \
  "libretro core option should advertise all supported source-mode values"
require_pattern 'parallel_set_hires_source_mode(1);' "$LIBRETRO_C" \
  "libretro should map phrb-only to the ParaLLEl source-mode setter"
require_pattern 'parallel_set_hires_source_mode(2);' "$LIBRETRO_C" \
  "libretro should map legacy-only to the ParaLLEl source-mode setter"
require_pattern 'parallel_set_hires_source_mode(3);' "$LIBRETRO_C" \
  "libretro should map all to the ParaLLEl source-mode setter"
require_pattern 'parallel_set_hires_source_mode(0);' "$LIBRETRO_C" \
  "libretro should default the source-mode setter back to auto"

require_pattern 'void parallel_set_hires_source_mode(unsigned mode);' "$PARALLEL_H" \
  "parallel frontend header should declare the hi-res source-mode setter"
require_pattern 'RDP::hires_source_mode = mode;' "$PARALLEL_CPP" \
  "parallel frontend implementation should store the configured source-mode"

require_pattern 'resolve_hires_cache_source_policy(hires_source_mode, getenv("PARALLEL_RDP_HIRES_RUNTIME_SOURCE_MODE"))' "$RDP_CPP" \
  "rdp init should resolve configured source-mode with env override support"
require_pattern 'source_mode=%s' "$RDP_CPP" \
  "rdp init logging should surface the active source-mode"
require_pattern 'configure_hires_replacement(hires_capabilities_ok, hires_cache_path.c_str(), cache_source_policy);' "$RDP_CPP" \
  "rdp init should pass the resolved source-mode into configure_hires_replacement"

require_pattern 'resolve_hires_cache_source_policy(unsigned configured_mode, const char *env)' "$POLICY_HPP" \
  "policy helpers should expose configured-mode resolution"
require_pattern 'if (env && *env)' "$POLICY_HPP" \
  "policy resolution should keep env override semantics"
require_pattern 'ReplacementProvider::CacheSourcePolicy::PHRBOnly' "$POLICY_HPP" \
  "policy helper should keep phrb-only mapping"

require_pattern 'configure_hires_replacement(bool enable, const char *cache_path,' "$RDP_DEVICE_CPP" \
  "rdp device should accept explicit source policy from the frontend"

echo "emu_libretro_hires_source_mode_contract: PASS"
