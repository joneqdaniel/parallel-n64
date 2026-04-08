#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

LEGACY_CACHE_PATH="${EMU_RUNTIME_PM64_FULL_CACHE_LEGACY_CACHE:-$REPO_ROOT/assets/PAPER MARIO_HIRESTEXTURES.hts}"
CONTEXT_SUMMARY_PATH="${EMU_RUNTIME_PM64_FULL_CACHE_CONTEXT_SUMMARY:-$REPO_ROOT/artifacts/paper-mario-probes/validation/20260408-full-cache-phrb-authorities-authority-context-root-provenance-promoted-round2/validation-summary.json}"
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

if [[ ! -f "$CONTEXT_SUMMARY_PATH" ]]; then
  echo "SKIP: Paper Mario authority context summary not found at $CONTEXT_SUMMARY_PATH."
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
  --context-summary "$CONTEXT_SUMMARY_PATH" \
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
expected = {
    "conversion_outcome": "partial-runtime-package",
    "requested_family_count": 8992,
    "package_manifest_record_count": 8883,
    "package_manifest_runtime_ready_record_count": 8508,
    "package_manifest_runtime_ready_native_sampled_record_count": 28,
    "package_manifest_runtime_ready_compat_record_count": 8480,
    "package_manifest_runtime_deferred_record_count": 375,
    "unresolved_count": 0,
    "runtime_overlay_built": False,
    "runtime_overlay_reason": "no-runtime-context",
    "context_bundle_input_count": 1,
    "context_bundle_resolution_count": 3,
}
for key, expected_value in expected.items():
    actual = report.get(key)
    if actual != expected_value:
        raise SystemExit(
            f"FAIL: refresh report expected {key}={expected_value!r}, got {actual!r}."
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
expected = {
    "title-screen": {
        "screenshot_sha256": "0e854083b48ccf48e0a372e39ca439c17f0e66523423fb2c3b68b94181c72ad5",
        "native_sampled_entry_count": 503,
        "descriptor_path_class": "sampled-only",
        "descriptor_path_counts": {"sampled": 268, "native_checksum": 0, "generic": 0, "compat": 0},
    },
    "file-select": {
        "screenshot_sha256": "43bd91dab1dfa4001365caee5ba03bc4ae1999fd012f5e943093615b4c858ca9",
        "native_sampled_entry_count": 503,
        "descriptor_path_class": "sampled-only",
        "descriptor_path_counts": {"sampled": 214, "native_checksum": 0, "generic": 0, "compat": 0},
    },
    "kmr-03-entry-5": {
        "screenshot_sha256": "212ffb9329b8d78e608874e524534ca54505a26204abe78524ef8fca97a1b638",
        "native_sampled_entry_count": 503,
        "descriptor_path_class": "sampled-only",
        "descriptor_path_counts": {"sampled": 182, "native_checksum": 0, "generic": 0, "compat": 0},
    },
}

fixtures = summary.get("fixtures") or []
if not summary.get("all_passed"):
    raise SystemExit("FAIL: refresh validation summary is not all_passed.")
if len(fixtures) != 3:
    raise SystemExit(f"FAIL: expected 3 refresh fixtures, found {len(fixtures)}.")
for fixture in fixtures:
    label = fixture.get("label")
    fixture_expected = expected.get(label)
    if fixture_expected is None:
        raise SystemExit(f"FAIL: unexpected fixture label in refresh summary: {label!r}.")
    if not fixture.get("passed"):
        raise SystemExit(f"FAIL: refresh fixture {label} did not pass.")
    if fixture.get("screenshot_sha256") != fixture_expected["screenshot_sha256"]:
        raise SystemExit(
            f"FAIL: refresh fixture {label} expected screenshot hash "
            f"{fixture_expected['screenshot_sha256']}, got {fixture.get('screenshot_sha256')!r}."
        )
    hires = fixture.get("hires_summary") or {}
    if hires.get("source_mode") != "phrb-only":
        raise SystemExit(
            f"FAIL: refresh fixture {label} expected source_mode=phrb-only, got {hires.get('source_mode')!r}."
        )
    if hires.get("source_policy") != "phrb-only":
        raise SystemExit(
            f"FAIL: refresh fixture {label} expected source_policy=phrb-only, got {hires.get('source_policy')!r}."
        )
    if int(hires.get("native_sampled_entry_count") or 0) != fixture_expected["native_sampled_entry_count"]:
        raise SystemExit(
            f"FAIL: refresh fixture {label} expected native_sampled_entry_count="
            f"{fixture_expected['native_sampled_entry_count']}, got {hires.get('native_sampled_entry_count')!r}."
        )
    if hires.get("descriptor_path_class") != fixture_expected["descriptor_path_class"]:
        raise SystemExit(
            f"FAIL: refresh fixture {label} expected descriptor_path_class="
            f"{fixture_expected['descriptor_path_class']!r}, got {hires.get('descriptor_path_class')!r}."
        )
    descriptor_paths = hires.get("descriptor_path_counts") or {}
    if descriptor_paths != fixture_expected["descriptor_path_counts"]:
        raise SystemExit(
            f"FAIL: refresh fixture {label} expected descriptor_path_counts="
            f"{fixture_expected['descriptor_path_counts']!r}, got {descriptor_paths!r}."
        )
PY

echo "emu_conformance_paper_mario_full_cache_phrb_authorities_refresh: PASS ($PACKAGE_PATH)"
