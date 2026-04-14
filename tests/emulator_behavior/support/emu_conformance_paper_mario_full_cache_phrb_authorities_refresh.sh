#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

LEGACY_CACHE_PATH="${EMU_RUNTIME_PM64_FULL_CACHE_LEGACY_CACHE:-$REPO_ROOT/assets/PAPER MARIO_HIRESTEXTURES.hts}"
CONTEXT_DIR="${EMU_RUNTIME_PM64_FULL_CACHE_CONTEXT_DIR:-$REPO_ROOT/artifacts/paper-mario-probes/validation}"
OUTPUT_DIR="${EMU_RUNTIME_PM64_FULL_CACHE_REFRESH_OUTPUT_DIR:-}"
BUNDLE_ROOT="${EMU_RUNTIME_PM64_FULL_CACHE_REFRESH_BUNDLE_ROOT:-}"

if [[ "${EMU_ENABLE_RUNTIME_CONFORMANCE:-0}" != "1" ]]; then
  echo "SKIP: set EMU_ENABLE_RUNTIME_CONFORMANCE=1 to run Paper Mario full-cache PHRB authority refresh conformance."
  exit 77
fi

if [[ ! -f "$LEGACY_CACHE_PATH" ]]; then
  echo "SKIP: Paper Mario legacy cache not found at $LEGACY_CACHE_PATH."
  exit 77
fi

if [[ ! -d "$CONTEXT_DIR" ]]; then
  echo "SKIP: Paper Mario authority context directory not found at $CONTEXT_DIR."
  exit 77
fi

REFRESH_SCENARIO="$REPO_ROOT/tools/scenarios/paper-mario-full-cache-phrb-authority-refresh.sh"

if [[ ! -f "$REFRESH_SCENARIO" ]]; then
  echo "FAIL: full-cache authority refresh scenario is missing at $REFRESH_SCENARIO." >&2
  exit 1
fi

cleanup_output_dir=0
cleanup_bundle_root=0
if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$(mktemp -d)"
  cleanup_output_dir=1
fi
if [[ -z "$BUNDLE_ROOT" ]]; then
  BUNDLE_ROOT="$(mktemp -d)"
  cleanup_bundle_root=1
fi

cleanup() {
  local rc=$?
  if (( cleanup_output_dir )) && [[ $rc -eq 0 ]]; then
    rm -rf "$OUTPUT_DIR"
  else
    echo "[conformance-refresh] output dir: $OUTPUT_DIR"
  fi
  if (( cleanup_bundle_root )) && [[ $rc -eq 0 ]]; then
    rm -rf "$BUNDLE_ROOT"
  else
    echo "[conformance-refresh] bundle root: $BUNDLE_ROOT"
  fi
  exit "$rc"
}
trap cleanup EXIT

REPORT_PATH="$OUTPUT_DIR/hts2phrb-report.json"
PACKAGE_PATH="$OUTPUT_DIR/package.phrb"

bash "$REFRESH_SCENARIO" \
  --legacy-cache "$LEGACY_CACHE_PATH" \
  --context-dir "$CONTEXT_DIR" \
  --output-dir "$OUTPUT_DIR" \
  --bundle-root "$BUNDLE_ROOT" \
  --reuse-existing

if [[ ! -f "$REPORT_PATH" ]]; then
  echo "FAIL: refresh scenario did not produce $REPORT_PATH." >&2
  exit 1
fi
if [[ ! -f "$PACKAGE_PATH" ]]; then
  echo "FAIL: refresh scenario did not produce $PACKAGE_PATH." >&2
  exit 1
fi

python3 - "$REPORT_PATH" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text())

# Exact expectations: stable regardless of local artifact tree
exact = {
    "conversion_outcome": "partial-runtime-package",
    "requested_family_count": 8992,
    "package_manifest_runtime_ready_compat_record_count": 8487,
    "package_manifest_runtime_deferred_record_count": 368,
    "runtime_overlay_built": True,
    "runtime_overlay_reason": "runtime-context-available",
}
for key, expected_value in exact.items():
    actual = report.get(key)
    if actual != expected_value:
        raise SystemExit(
            f"FAIL: refresh report expected {key}={expected_value!r}, got {actual!r}."
        )

# Minimum bounds: grow as more context summaries accumulate in the local artifact tree
minimums = {
    "package_manifest_record_count": 8883,
    "package_manifest_runtime_ready_record_count": 8515,
    "package_manifest_runtime_ready_native_sampled_record_count": 28,
    "context_bundle_input_count": 1,
    "context_bundle_resolution_count": 3,
    "binding_count": 15,
}
for key, min_value in minimums.items():
    actual = report.get(key)
    if actual is None or actual < min_value:
        raise SystemExit(
            f"FAIL: refresh report expected {key}>={min_value!r}, got {actual!r}."
        )
PY

SUMMARY_PATH="$BUNDLE_ROOT/validation-summary.json"
if [[ ! -f "$SUMMARY_PATH" ]]; then
  echo "FAIL: refresh scenario did not produce $SUMMARY_PATH." >&2
  exit 1
fi

python3 - "$SUMMARY_PATH" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text())

# Exact expectations: stable regardless of enrichment depth
exact_fixture = {
    "title-screen": {
        "screenshot_sha256": "0e854083b48ccf48e0a372e39ca439c17f0e66523423fb2c3b68b94181c72ad5",
        "descriptor_path_class": "sampled-only",
    },
    "file-select": {
        "screenshot_sha256": "43bd91dab1dfa4001365caee5ba03bc4ae1999fd012f5e943093615b4c858ca9",
        "descriptor_path_class": "sampled-only",
    },
    "kmr-03-entry-5": {
        "screenshot_sha256": "212ffb9329b8d78e608874e524534ca54505a26204abe78524ef8fca97a1b638",
        "descriptor_path_class": "sampled-only",
    },
}

# Minimum bounds: grow as more enrichment context accumulates
min_fixture = {
    "title-screen":    {"native_sampled_entry_count": 503, "min_sampled": 268},
    "file-select":     {"native_sampled_entry_count": 503, "min_sampled": 214},
    "kmr-03-entry-5":  {"native_sampled_entry_count": 503, "min_sampled": 182},
}

fixtures = summary.get("fixtures") or []
if not summary.get("all_passed"):
    raise SystemExit("FAIL: refresh validation summary is not all_passed.")
if len(fixtures) != 3:
    raise SystemExit(f"FAIL: expected 3 refresh fixtures, found {len(fixtures)}.")
for fixture in fixtures:
    label = fixture.get("label")
    fe = exact_fixture.get(label)
    fm = min_fixture.get(label)
    if fe is None:
        raise SystemExit(f"FAIL: unexpected fixture label in refresh summary: {label!r}.")
    if not fixture.get("passed"):
        raise SystemExit(f"FAIL: refresh fixture {label} did not pass.")
    if fixture.get("screenshot_sha256") != fe["screenshot_sha256"]:
        raise SystemExit(
            f"FAIL: refresh fixture {label} expected screenshot hash "
            f"{fe['screenshot_sha256']}, got {fixture.get('screenshot_sha256')!r}."
        )
    hires = fixture.get("hires_summary") or {}
    if hires.get("source_mode") != "phrb-only":
        raise SystemExit(
            f"FAIL: refresh fixture {label} expected source_mode=phrb-only, got {hires.get('source_mode')!r}."
        )
    native_sampled = int(hires.get("native_sampled_entry_count") or 0)
    if native_sampled < fm["native_sampled_entry_count"]:
        raise SystemExit(
            f"FAIL: refresh fixture {label} expected native_sampled_entry_count>="
            f"{fm['native_sampled_entry_count']}, got {native_sampled}."
        )
    if hires.get("descriptor_path_class") != fe["descriptor_path_class"]:
        raise SystemExit(
            f"FAIL: refresh fixture {label} expected descriptor_path_class="
            f"{fe['descriptor_path_class']!r}, got {hires.get('descriptor_path_class')!r}."
        )
    descriptor_paths = hires.get("descriptor_path_counts") or {}
    sampled_count = int(descriptor_paths.get("sampled") or 0)
    if sampled_count < fm["min_sampled"]:
        raise SystemExit(
            f"FAIL: refresh fixture {label} expected sampled>={fm['min_sampled']}, got {sampled_count}."
        )
    for zero_key in ("native_checksum", "generic", "compat"):
        if int(descriptor_paths.get(zero_key) or 0) != 0:
            raise SystemExit(
                f"FAIL: refresh fixture {label} expected {zero_key}=0, "
                f"got {descriptor_paths.get(zero_key)!r}."
            )
PY

echo "emu_conformance_paper_mario_full_cache_phrb_authorities_refresh: PASS ($PACKAGE_PATH)"
