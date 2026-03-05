#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

if [[ "${EMU_ENABLE_RUNTIME_CONFORMANCE:-0}" != "1" ]]; then
  echo "SKIP: set EMU_ENABLE_RUNTIME_CONFORMANCE=1 to run runtime conformance smoke."
  exit 77
fi

if [[ ! -x "$REPO_ROOT/run-n64.sh" ]]; then
  echo "FAIL: run-n64.sh is missing or not executable." >&2
  exit 1
fi

find_lavapipe_icd() {
  if [[ -n "${VK_LAVAPIPE_ICD:-}" && -f "$VK_LAVAPIPE_ICD" ]]; then
    printf '%s\n' "$VK_LAVAPIPE_ICD"
    return 0
  fi

  local dir
  for dir in /usr/share/vulkan/icd.d /etc/vulkan/icd.d; do
    [[ -d "$dir" ]] || continue
    local candidate
    candidate="$(find "$dir" -maxdepth 1 -type f \( -name '*lvp*.json' -o -name '*lavapipe*.json' \) | head -n 1 || true)"
    if [[ -n "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

if ! lavapipe_icd="$(find_lavapipe_icd)"; then
  echo "SKIP: lavapipe ICD not found (set VK_LAVAPIPE_ICD to override)."
  exit 77
fi

log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT

set +e
VK_DRIVER_FILES="$lavapipe_icd" \
  timeout --signal=INT --kill-after=5 20s "$REPO_ROOT/run-n64.sh" -- --verbose >"$log_file" 2>&1
status=$?
set -e

if [[ $status -ne 0 && $status -ne 124 ]]; then
  cat "$log_file"
  echo "FAIL: runtime smoke exited with status $status." >&2
  exit 1
fi

if ! grep -Eqi 'llvmpipe|lavapipe' "$log_file"; then
  cat "$log_file"
  echo "FAIL: runtime smoke did not report a software Vulkan device." >&2
  exit 1
fi

if ! grep -q 'plugin_start_gfx success\.' "$log_file"; then
  cat "$log_file"
  echo "FAIL: runtime smoke did not reach plugin_start_gfx success." >&2
  exit 1
fi

echo "emu_conformance_runtime_smoke: PASS ($lavapipe_icd)"
