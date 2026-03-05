#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
EXPECTED_SHA256="d055796500995b01845e39036d3af1fa57ea72a50080a2698bd26d1d0653379e"

if [[ "${EMU_ENABLE_RUNTIME_CONFORMANCE:-0}" != "1" ]]; then
  echo "SKIP: set EMU_ENABLE_RUNTIME_CONFORMANCE=1 to run lavapipe VI downscale frame hash conformance."
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
shot_file="$(mktemp --suffix=.png)"
tmp_cfg="$(mktemp)"
tmp_opt="$(mktemp)"
trap 'rm -f "$log_file" "$shot_file" "$tmp_cfg" "$tmp_opt"' EXIT

cat > "$tmp_cfg" <<CONFIG
core_options_path = "$tmp_opt"
global_core_options = "true"
game_specific_options = "false"
config_save_on_exit = "false"
CONFIG

cat > "$tmp_opt" <<'OPTS'
parallel-n64-gfxplugin = "parallel"
parallel-n64-parallel-rdp-synchronous = "disabled"
parallel-n64-parallel-rdp-overscan = "0"
parallel-n64-parallel-rdp-divot-filter = "enabled"
parallel-n64-parallel-rdp-gamma-dither = "enabled"
parallel-n64-parallel-rdp-vi-aa = "enabled"
parallel-n64-parallel-rdp-vi-bilinear = "enabled"
parallel-n64-parallel-rdp-dither-filter = "enabled"
parallel-n64-parallel-rdp-upscaling = "4x"
parallel-n64-parallel-rdp-downscaling = "1/2"
parallel-n64-parallel-rdp-native-texture-lod = "enabled"
parallel-n64-parallel-rdp-native-tex-rect = "enabled"
parallel-n64-parallel-rdp-hirestex = "disabled"
OPTS

set +e
VK_DRIVER_FILES="$lavapipe_icd" \
  timeout --signal=INT --kill-after=5 120s "$REPO_ROOT/run-n64.sh" -- \
    -c "$tmp_cfg" \
    --verbose \
    --max-frames=180 \
    --max-frames-ss \
    --max-frames-ss-path="$shot_file" >"$log_file" 2>&1
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  cat "$log_file"
  echo "FAIL: VI-downscale frame-hash run exited with status $rc." >&2
  exit 1
fi

if [[ ! -s "$shot_file" ]]; then
  cat "$log_file"
  echo "FAIL: VI-downscale screenshot file was not produced." >&2
  exit 1
fi

if ! grep -Eqi 'llvmpipe|lavapipe' "$log_file"; then
  cat "$log_file"
  echo "FAIL: VI-downscale frame-hash run did not report a software Vulkan device." >&2
  exit 1
fi

if ! grep -q 'plugin_start_gfx success\.' "$log_file"; then
  cat "$log_file"
  echo "FAIL: VI-downscale frame-hash run did not reach plugin_start_gfx success." >&2
  exit 1
fi

actual_sha256="$(sha256sum "$shot_file" | awk '{ print $1 }')"
if [[ "$actual_sha256" != "$EXPECTED_SHA256" ]]; then
  echo "FAIL: lavapipe VI-downscale frame hash mismatch." >&2
  echo "expected=$EXPECTED_SHA256" >&2
  echo "actual=$actual_sha256" >&2
  cat "$log_file"
  exit 1
fi

echo "emu_conformance_lavapipe_vi_downscale_hash: PASS ($actual_sha256)"
