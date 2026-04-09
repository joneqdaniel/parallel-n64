#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

CACHE_PATH_DEFAULT="$REPO_ROOT/artifacts/hires-pack-review/20260330-selected-plus-timeout-960-v1-add-1b85/package.phrb"
EXPECTED_ON_HASH_DEFAULT="4bd3929dabff3ffb1b7e03a9c10d8ce50e9b6d0f067825d3a788c48a41b6fc62"

CACHE_PATH="${EMU_RUNTIME_PM64_SELECTED_PHRB:-$CACHE_PATH_DEFAULT}"
EXPECTED_ON_HASH="${EMU_RUNTIME_PM64_SELECTED_TIMEOUT_ON_HASH:-$EXPECTED_ON_HASH_DEFAULT}"
BUNDLE_ROOT="${EMU_RUNTIME_PM64_SELECTED_TIMEOUT_BUNDLE_ROOT:-}"

if [[ "${EMU_ENABLE_RUNTIME_CONFORMANCE:-0}" != "1" ]]; then
  echo "SKIP: set EMU_ENABLE_RUNTIME_CONFORMANCE=1 to run Paper Mario selected-package timeout lookup-without-probe conformance."
  exit 77
fi

SCENARIO="$REPO_ROOT/tools/scenarios/paper-mario-title-timeout-probe.sh"
if [[ ! -x "$SCENARIO" ]]; then
  echo "FAIL: timeout probe wrapper is missing or not executable." >&2
  exit 1
fi

if [[ ! -f "$CACHE_PATH" ]]; then
  echo "SKIP: selected Paper Mario PHRB package not found at $CACHE_PATH (set EMU_RUNTIME_PM64_SELECTED_PHRB to override)."
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

OFF_BUNDLE="$BUNDLE_ROOT/off/timeout-960"
ON_BUNDLE="$BUNDLE_ROOT/on/timeout-960"

timeout --signal=INT --kill-after=15 600s \
  "$SCENARIO" \
  --mode off \
  --step-frames 960 \
  --step-chunk-frames 960 \
  --probe-label "timeout-960-off-baseline" \
  --bundle-dir "$OFF_BUNDLE" \
  --run

PARALLEL_RDP_HIRES_CACHE_PATH="$CACHE_PATH" \
PARALLEL_RDP_HIRES_RUNTIME_SOURCE_MODE=phrb-only \
PARALLEL_RDP_HIRES_SAMPLED_OBJECT_LOOKUP=1 \
PARALLEL_RDP_HIRES_SAMPLED_OBJECT_PROBE=0 \
timeout --signal=INT --kill-after=15 600s \
  "$SCENARIO" \
  --mode on \
  --step-frames 960 \
  --step-chunk-frames 960 \
  --probe-label "timeout-960-selected-package-no-probe" \
  --bundle-dir "$ON_BUNDLE" \
  --run

python3 - "$OFF_BUNDLE" "$ON_BUNDLE" "$EXPECTED_ON_HASH" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

off_bundle = Path(sys.argv[1])
on_bundle = Path(sys.argv[2])
expected_on_hash = sys.argv[3]

def capture_hash(bundle_dir: Path) -> str:
    captures = sorted((bundle_dir / "captures").glob("*"))
    if len(captures) != 1:
        raise SystemExit(f"FAIL: expected exactly one capture in {bundle_dir}/captures, found {len(captures)}.")
    return hashlib.sha256(captures[0].read_bytes()).hexdigest()

off_hash = capture_hash(off_bundle)
on_hash = capture_hash(on_bundle)
if on_hash != expected_on_hash:
    raise SystemExit(f"FAIL: expected on hash {expected_on_hash}, got {on_hash}.")
if on_hash != off_hash:
    raise SystemExit(f"FAIL: expected probe-off selected package to remain hash-identical to off ({off_hash}), got {on_hash}.")

hires = json.loads((on_bundle / "traces" / "hires-evidence.json").read_text())
summary = hires.get("summary") or {}
descriptor_paths = summary.get("descriptor_path_counts") or {}
detail_counts = summary.get("descriptor_path_detail_counts") or {}
sampled_probe = hires.get("sampled_object_probe") or {}

if summary.get("provider") != "on":
    raise SystemExit(f"FAIL: expected provider=on, got {summary.get('provider')!r}.")
if summary.get("source_mode") != "phrb-only":
    raise SystemExit(f"FAIL: expected source_mode=phrb-only, got {summary.get('source_mode')!r}.")
if summary.get("source_policy") != "phrb-only":
    raise SystemExit(f"FAIL: expected source_policy=phrb-only, got {summary.get('source_policy')!r}.")
if int(summary.get("native_sampled_entry_count") or 0) < 1:
    raise SystemExit(f"FAIL: expected native sampled entries, got {summary.get('native_sampled_entry_count')!r}.")
if int((summary.get("source_counts") or {}).get("phrb") or 0) < 1:
    raise SystemExit("FAIL: expected at least one PHRB-backed entry.")
if int(descriptor_paths.get("sampled") or 0) < 1:
    raise SystemExit(f"FAIL: expected sampled descriptor usage, got {descriptor_paths!r}.")
for key in ("native_checksum", "generic", "compat"):
    if int(descriptor_paths.get(key) or 0) != 0:
        raise SystemExit(f"FAIL: expected descriptor_paths.{key}=0, got {descriptor_paths.get(key)!r}.")
if int(sampled_probe.get("exact_hit_count") or 0) < 1:
    raise SystemExit(f"FAIL: expected sampled exact hits without probe, got {sampled_probe.get('exact_hit_count')!r}.")
if int(detail_counts.get("sampled_ordered_surface_singleton") or 0) < 1:
    raise SystemExit(
        "FAIL: expected sampled ordered-surface singleton descriptor traffic to stay live without probe, "
        f"got {detail_counts.get('sampled_ordered_surface_singleton')!r}."
    )
PY

echo "emu_conformance_paper_mario_selected_package_timeout_lookup_without_probe: PASS ($CACHE_PATH)"
