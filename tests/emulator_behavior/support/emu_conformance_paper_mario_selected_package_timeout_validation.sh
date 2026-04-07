#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

CACHE_PATH_DEFAULT="$REPO_ROOT/artifacts/hires-pack-review/20260330-selected-plus-timeout-960-v1-add-1b85/package.phrb"
LOADER_MANIFEST_DEFAULT="$REPO_ROOT/artifacts/hires-pack-review/20260330-selected-plus-timeout-960-v1-add-1b85/loader-manifest.json"
TRANSPORT_REVIEW_DEFAULT="$REPO_ROOT/artifacts/hires-pack-review/20260406-timeout-960-sampled-transport-next/review.json"
EXPECTED_ON_HASH_DEFAULT="664c0d0784f12cdd6424bce6ae53e828bb08da22a66db0a50f08d6e2de97b3d9"

CACHE_PATH="${EMU_RUNTIME_PM64_SELECTED_PHRB:-$CACHE_PATH_DEFAULT}"
LOADER_MANIFEST="${EMU_RUNTIME_PM64_SELECTED_LOADER_MANIFEST:-$LOADER_MANIFEST_DEFAULT}"
TRANSPORT_REVIEW="${EMU_RUNTIME_PM64_SELECTED_TRANSPORT_REVIEW:-$TRANSPORT_REVIEW_DEFAULT}"
EXPECTED_ON_HASH="${EMU_RUNTIME_PM64_SELECTED_TIMEOUT_ON_HASH:-$EXPECTED_ON_HASH_DEFAULT}"
BUNDLE_ROOT="${EMU_RUNTIME_PM64_SELECTED_TIMEOUT_BUNDLE_ROOT:-}"

if [[ "${EMU_ENABLE_RUNTIME_CONFORMANCE:-0}" != "1" ]]; then
  echo "SKIP: set EMU_ENABLE_RUNTIME_CONFORMANCE=1 to run Paper Mario selected-package timeout conformance."
  exit 77
fi

SCENARIO="$REPO_ROOT/tools/scenarios/paper-mario-title-timeout-selected-package-validation.sh"
if [[ ! -x "$SCENARIO" ]]; then
  echo "FAIL: timeout selected-package validation wrapper is missing or not executable." >&2
  exit 1
fi

if [[ ! -f "$CACHE_PATH" ]]; then
  echo "SKIP: selected Paper Mario PHRB package not found at $CACHE_PATH (set EMU_RUNTIME_PM64_SELECTED_PHRB to override)."
  exit 77
fi

if [[ ! -f "$LOADER_MANIFEST" ]]; then
  echo "SKIP: selected-package loader manifest not found at $LOADER_MANIFEST."
  exit 77
fi

if [[ ! -f "$TRANSPORT_REVIEW" ]]; then
  echo "SKIP: selected-package transport review not found at $TRANSPORT_REVIEW."
  exit 77
fi

TITLE_ENV="$REPO_ROOT/tools/scenarios/paper-mario-title-screen.runtime.env"
if [[ ! -f "$TITLE_ENV" ]]; then
  echo "SKIP: runtime env missing for paper-mario-title-screen at $TITLE_ENV."
  exit 77
fi

readarray -t prereq_paths < <(
  ENV_PATH="$TITLE_ENV" python3 - <<'PY'
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
)

bin_path="${prereq_paths[0]:-}"
base_cfg="${prereq_paths[1]:-}"
core_path="${prereq_paths[2]:-}"
rom_path="${prereq_paths[3]:-}"
authoritative_state_path="${prereq_paths[4]:-}"

if [[ -z "$bin_path" || ! -x "$bin_path" ]]; then
  echo "SKIP: RetroArch binary missing for title-timeout conformance at $bin_path."
  exit 77
fi
if [[ -z "$base_cfg" || ! -f "$base_cfg" ]]; then
  echo "SKIP: RetroArch config missing for title-timeout conformance at $base_cfg."
  exit 77
fi
if [[ -z "$core_path" || ! -f "$core_path" ]]; then
  echo "SKIP: libretro core missing for title-timeout conformance at $core_path."
  exit 77
fi
if [[ -z "$rom_path" || ! -f "$rom_path" ]]; then
  echo "SKIP: Paper Mario ROM missing for title-timeout conformance at $rom_path."
  exit 77
fi
if [[ -z "$authoritative_state_path" || ! -f "$authoritative_state_path" ]]; then
  echo "SKIP: authoritative state missing for title-timeout conformance at $authoritative_state_path."
  exit 77
fi

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
  "$SCENARIO" \
  --cache-path "$CACHE_PATH" \
  --bundle-root "$BUNDLE_ROOT" \
  --steps "960" \
  --loader-manifest "$LOADER_MANIFEST" \
  --transport-review "$TRANSPORT_REVIEW"
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  echo "FAIL: selected-package timeout validation exited with status $rc." >&2
  exit 1
fi

SUMMARY_PATH="$BUNDLE_ROOT/validation-summary.json"
REVIEW_PATH="$BUNDLE_ROOT/on/timeout-960/traces/hires-sampled-selector-review.json"
if [[ ! -f "$SUMMARY_PATH" ]]; then
  echo "FAIL: selected-package timeout validation did not produce $SUMMARY_PATH." >&2
  exit 1
fi
if [[ ! -f "$REVIEW_PATH" ]]; then
  echo "FAIL: selected-package timeout validation did not produce $REVIEW_PATH." >&2
  exit 1
fi

python3 - "$SUMMARY_PATH" "$REVIEW_PATH" "$EXPECTED_ON_HASH" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text())
review = json.loads(Path(sys.argv[2]).read_text())
expected_on_hash = sys.argv[3]

steps = summary.get("steps") or []
if len(steps) != 1:
    raise SystemExit(f"FAIL: expected 1 timeout step, found {len(steps)}.")

step = steps[0]
if int(step.get("step_frames") or 0) != 960:
    raise SystemExit(f"FAIL: expected timeout step_frames=960, got {step.get('step_frames')!r}.")
if step.get("on_hash") != expected_on_hash:
    raise SystemExit(
        f"FAIL: expected selected-package timeout on_hash={expected_on_hash}, "
        f"got {step.get('on_hash')!r}."
    )

semantic = step.get("semantic") or {}
if semantic.get("map_name_candidate") != "kmr_03" or int(semantic.get("entry_id") or -1) != 5:
    raise SystemExit(f"FAIL: unexpected semantic state {semantic!r}.")
if semantic.get("init_symbol") != "state_init_world" or semantic.get("step_symbol") != "state_step_world":
    raise SystemExit(f"FAIL: unexpected semantic callbacks {semantic!r}.")

hires = step.get("hires_summary") or {}
if hires.get("source_mode") != "phrb-only":
    raise SystemExit(f"FAIL: expected source_mode=phrb-only, got {hires.get('source_mode')!r}.")
if int(hires.get("entry_count") or 0) < 1:
    raise SystemExit("FAIL: selected-package timeout lane has no hi-res entries.")
if int(hires.get("native_sampled_entry_count") or 0) < 1:
    raise SystemExit("FAIL: selected-package timeout lane has no native sampled entries.")

probe = step.get("sampled_object_probe") or {}
if int(probe.get("exact_conflict_miss_count") or 0) < 1:
    raise SystemExit("FAIL: expected at least one exact conflict miss in timeout probe.")

pool_families = review.get("pool_families") or []
target = None
for family in pool_families:
    if family.get("sampled_low32") == "1b8530fb":
        target = family
        break
if target is None:
    raise SystemExit("FAIL: review did not report the 1b8530fb pool family.")
if target.get("pool_recommendation") != "defer-runtime-pool-semantics":
    raise SystemExit(
        "FAIL: expected 1b8530fb pool recommendation to remain "
        f"'defer-runtime-pool-semantics', got {target.get('pool_recommendation')!r}."
    )
PY

echo "emu_conformance_paper_mario_selected_package_timeout_validation: PASS ($CACHE_PATH)"
