#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

CACHE_PATH_DEFAULT="$REPO_ROOT/artifacts/hires-pack-review/20260330-selected-plus-timeout-960-v1-add-1b85/package.phrb"
CACHE_PATH="${EMU_RUNTIME_PM64_SELECTED_PHRB:-$CACHE_PATH_DEFAULT}"
BUNDLE_ROOT="${EMU_RUNTIME_PM64_SELECTED_BUNDLE_ROOT:-}"

if [[ "${EMU_ENABLE_RUNTIME_CONFORMANCE:-0}" != "1" ]]; then
  echo "SKIP: set EMU_ENABLE_RUNTIME_CONFORMANCE=1 to run Paper Mario selected-package authority conformance."
  exit 77
fi

if [[ ! -x "$REPO_ROOT/tools/scenarios/paper-mario-selected-package-authority-validation.sh" ]]; then
  echo "FAIL: selected-package authority validation wrapper is missing or not executable." >&2
  exit 1
fi

if [[ ! -f "$CACHE_PATH" ]]; then
  echo "SKIP: selected Paper Mario PHRB package not found at $CACHE_PATH (set EMU_RUNTIME_PM64_SELECTED_PHRB to override)."
  exit 77
fi

require_runtime_env_prereqs() {
  local env_path="$1"
  local label="$2"
  if [[ ! -f "$env_path" ]]; then
    echo "SKIP: runtime env missing for $label at $env_path."
    exit 77
  fi

  local bin_path base_cfg core_path rom_path authoritative_state_path
  bin_path="$(
    ENV_PATH="$env_path" python3 - <<'PY'
import os
from pathlib import Path

env_path = Path(os.environ["ENV_PATH"])
values = {}
for raw in env_path.read_text().splitlines():
    line = raw.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    values[key] = value.strip().strip('"')
for key in ("RETROARCH_BIN", "RETROARCH_BASE_CONFIG", "CORE_PATH", "ROM_PATH", "AUTHORITATIVE_STATE_PATH"):
    print(values.get(key, ""))
PY
  )"

  mapfile -t prereq_paths <<<"$bin_path"
  bin_path="${prereq_paths[0]:-}"
  base_cfg="${prereq_paths[1]:-}"
  core_path="${prereq_paths[2]:-}"
  rom_path="${prereq_paths[3]:-}"
  authoritative_state_path="${prereq_paths[4]:-}"

  if [[ -z "$bin_path" || ! -x "$bin_path" ]]; then
    echo "SKIP: RetroArch binary missing for $label at $bin_path."
    exit 77
  fi
  if [[ -z "$base_cfg" || ! -f "$base_cfg" ]]; then
    echo "SKIP: RetroArch config missing for $label at $base_cfg."
    exit 77
  fi
  if [[ -z "$core_path" || ! -f "$core_path" ]]; then
    echo "SKIP: libretro core missing for $label at $core_path."
    exit 77
  fi
  if [[ -z "$rom_path" || ! -f "$rom_path" ]]; then
    echo "SKIP: Paper Mario ROM missing for $label at $rom_path."
    exit 77
  fi
  if [[ -z "$authoritative_state_path" || ! -f "$authoritative_state_path" ]]; then
    echo "SKIP: authoritative state missing for $label at $authoritative_state_path."
    exit 77
  fi
}

require_runtime_env_prereqs "$REPO_ROOT/tools/scenarios/paper-mario-title-screen.runtime.env" "paper-mario-title-screen"
require_runtime_env_prereqs "$REPO_ROOT/tools/scenarios/paper-mario-file-select.runtime.env" "paper-mario-file-select"
require_runtime_env_prereqs "$REPO_ROOT/tools/scenarios/paper-mario-kmr-03-entry-5.runtime.env" "paper-mario-kmr-03-entry-5"

cleanup_bundle_root=0
if [[ -z "$BUNDLE_ROOT" ]]; then
  BUNDLE_ROOT="$(mktemp -d)"
  cleanup_bundle_root=1
fi

cleanup() {
  local rc=$?
  if (( cleanup_bundle_root )) && [[ $rc -eq 0 ]]; then
    rm -rf "$BUNDLE_ROOT"
  else
    echo "[conformance] bundle root: $BUNDLE_ROOT"
  fi
  exit "$rc"
}
trap cleanup EXIT

set +e
timeout --signal=INT --kill-after=15 600s \
  "$REPO_ROOT/tools/scenarios/paper-mario-selected-package-authority-validation.sh" \
  --cache-path "$CACHE_PATH" \
  --bundle-root "$BUNDLE_ROOT"
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  echo "FAIL: selected-package authority validation exited with status $rc." >&2
  exit 1
fi

SUMMARY_PATH="$BUNDLE_ROOT/validation-summary.json"
if [[ ! -f "$SUMMARY_PATH" ]]; then
  echo "FAIL: selected-package authority validation did not produce $SUMMARY_PATH." >&2
  exit 1
fi

python3 - "$SUMMARY_PATH" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text())
fixtures = summary.get("fixtures") or []
if not summary.get("all_passed"):
    raise SystemExit("FAIL: selected-package authority summary is not all_passed.")
if len(fixtures) != 3:
    raise SystemExit(f"FAIL: expected 3 fixtures, found {len(fixtures)}.")
for fixture in fixtures:
    if not fixture.get("passed"):
        raise SystemExit(f"FAIL: fixture {fixture.get('label')} did not pass.")
    hires = fixture.get("hires_summary") or {}
    if hires.get("source_mode") != "phrb-only":
        raise SystemExit(
            f"FAIL: fixture {fixture.get('label')} expected source_mode=phrb-only, "
            f"got {hires.get('source_mode')!r}."
        )
    if int(hires.get("entry_count") or 0) < 1:
        raise SystemExit(f"FAIL: fixture {fixture.get('label')} has no hi-res entries.")
    if int(hires.get("native_sampled_entry_count") or 0) < 1:
        raise SystemExit(f"FAIL: fixture {fixture.get('label')} has no native sampled entries.")
PY

echo "emu_conformance_paper_mario_selected_package_authorities: PASS ($CACHE_PATH)"
