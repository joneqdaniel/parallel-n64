#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

LEGACY_CACHE_PATH="${EMU_RUNTIME_PM64_FULL_CACHE_LEGACY_CACHE:-$REPO_ROOT/assets/PAPER MARIO_HIRESTEXTURES.hts}"
OUTPUT_DIR="${EMU_RUNTIME_PM64_FULL_CACHE_ZERO_CONFIG_REFRESH_OUTPUT_DIR:-}"
BUNDLE_ROOT="${EMU_RUNTIME_PM64_FULL_CACHE_ZERO_CONFIG_REFRESH_BUNDLE_ROOT:-}"
REFRESH_SCENARIO="$REPO_ROOT/tools/scenarios/paper-mario-full-cache-phrb-zero-config-refresh.sh"

if [[ "${EMU_ENABLE_RUNTIME_CONFORMANCE:-0}" != "1" ]]; then
  echo "SKIP: set EMU_ENABLE_RUNTIME_CONFORMANCE=1 to run Paper Mario full-cache zero-config PHRB authority refresh conformance."
  exit 77
fi

if [[ ! -f "$LEGACY_CACHE_PATH" ]]; then
  echo "SKIP: Paper Mario legacy cache not found at $LEGACY_CACHE_PATH."
  exit 77
fi

if [[ ! -f "$REFRESH_SCENARIO" ]]; then
  echo "FAIL: full-cache zero-config refresh scenario is missing at $REFRESH_SCENARIO." >&2
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
    echo "[zero-config-refresh] output dir: $OUTPUT_DIR"
  fi
  if (( cleanup_bundle_root )) && [[ $rc -eq 0 ]]; then
    rm -rf "$BUNDLE_ROOT"
  else
    echo "[zero-config-refresh] bundle root: $BUNDLE_ROOT"
  fi
  exit "$rc"
}
trap cleanup EXIT

bash "$REFRESH_SCENARIO" \
  --legacy-cache "$LEGACY_CACHE_PATH" \
  --output-dir "$OUTPUT_DIR" \
  --bundle-root "$BUNDLE_ROOT" \
  --reuse-existing

REPORT_PATH="$OUTPUT_DIR/hts2phrb-report.json"
PACKAGE_PATH="$OUTPUT_DIR/package.phrb"
SUMMARY_PATH="$BUNDLE_ROOT/validation-summary.json"
if [[ ! -f "$REPORT_PATH" ]]; then
  echo "FAIL: zero-config refresh scenario did not produce $REPORT_PATH." >&2
  exit 1
fi
if [[ ! -f "$PACKAGE_PATH" ]]; then
  echo "FAIL: zero-config refresh scenario did not produce $PACKAGE_PATH." >&2
  exit 1
fi
if [[ ! -f "$SUMMARY_PATH" ]]; then
  echo "FAIL: zero-config refresh scenario did not produce $SUMMARY_PATH." >&2
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
    "package_manifest_record_count": 8992,
    "package_manifest_runtime_ready_record_count": 8613,
    "package_manifest_runtime_ready_native_sampled_record_count": 0,
    "package_manifest_runtime_ready_compat_record_count": 8613,
    "package_manifest_runtime_deferred_record_count": 379,
    "unresolved_count": 0,
    "runtime_overlay_built": False,
    "runtime_overlay_reason": "no-runtime-context",
    "context_bundle_input_count": 0,
    "context_bundle_resolution_count": 0,
}
for key, expected_value in expected.items():
    actual = report.get(key)
    if actual != expected_value:
        raise SystemExit(
            f"FAIL: zero-config refresh report expected {key}={expected_value!r}, got {actual!r}."
        )
PY

python3 - "$SUMMARY_PATH" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text())
expected = {
    "title-screen": {
        "screenshot_sha256": "ba91ffce0cc7b6053568c0a7774bf0ae80825c95d95fce89ba4a9f79c62b9d16",
        "entry_count": 12420,
        "native_sampled_entry_count": 0,
        "entry_class": "compat-only",
        "descriptor_path_class": "compat-only",
        "descriptor_path_counts": {"sampled": 0, "native_checksum": 0, "generic": 0, "compat": 178},
    },
    "file-select": {
        "screenshot_sha256": "8a90f7874bd797a186ff85d488033dc332b2a75f5bec91ad33ca8246e6be7730",
        "entry_count": 12420,
        "native_sampled_entry_count": 0,
        "entry_class": "compat-only",
        "descriptor_path_class": "compat-only",
        "descriptor_path_counts": {"sampled": 0, "native_checksum": 0, "generic": 0, "compat": 82},
    },
    "kmr-03-entry-5": {
        "screenshot_sha256": "3a175a30d8154df34cd17d21eb8d6997ef12d6846bddf2b6c7f9c2074e0a215e",
        "entry_count": 12420,
        "native_sampled_entry_count": 0,
        "entry_class": "compat-only",
        "descriptor_path_class": "compat-only",
        "descriptor_path_counts": {"sampled": 0, "native_checksum": 0, "generic": 0, "compat": 112},
    },
}

fixtures = summary.get("fixtures") or []
if not summary.get("all_passed"):
    raise SystemExit("FAIL: zero-config refresh validation summary is not all_passed.")
if len(fixtures) != 3:
    raise SystemExit(f"FAIL: expected 3 zero-config refresh fixtures, found {len(fixtures)}.")
for fixture in fixtures:
    label = fixture.get("label")
    fixture_expected = expected.get(label)
    if fixture_expected is None:
        raise SystemExit(f"FAIL: unexpected fixture label in zero-config refresh summary: {label!r}.")
    if not fixture.get("passed"):
        raise SystemExit(f"FAIL: zero-config refresh fixture {label} did not pass.")
    if fixture.get("screenshot_sha256") != fixture_expected["screenshot_sha256"]:
        raise SystemExit(
            f"FAIL: zero-config refresh fixture {label} expected screenshot hash "
            f"{fixture_expected['screenshot_sha256']}, got {fixture.get('screenshot_sha256')!r}."
        )
    hires = fixture.get("hires_summary") or {}
    if hires.get("source_mode") != "phrb-only":
        raise SystemExit(
            f"FAIL: zero-config refresh fixture {label} expected source_mode=phrb-only, got {hires.get('source_mode')!r}."
        )
    if int(hires.get("entry_count") or 0) != fixture_expected["entry_count"]:
        raise SystemExit(
            f"FAIL: zero-config refresh fixture {label} expected entry_count="
            f"{fixture_expected['entry_count']}, got {hires.get('entry_count')!r}."
        )
    if int(hires.get("native_sampled_entry_count") or 0) != fixture_expected["native_sampled_entry_count"]:
        raise SystemExit(
            f"FAIL: zero-config refresh fixture {label} expected native_sampled_entry_count="
            f"{fixture_expected['native_sampled_entry_count']}, got {hires.get('native_sampled_entry_count')!r}."
        )
    if hires.get("entry_class") != fixture_expected["entry_class"]:
        raise SystemExit(
            f"FAIL: zero-config refresh fixture {label} expected entry_class="
            f"{fixture_expected['entry_class']!r}, got {hires.get('entry_class')!r}."
        )
    if hires.get("descriptor_path_class") != fixture_expected["descriptor_path_class"]:
        raise SystemExit(
            f"FAIL: zero-config refresh fixture {label} expected descriptor_path_class="
            f"{fixture_expected['descriptor_path_class']!r}, got {hires.get('descriptor_path_class')!r}."
        )
    descriptor_paths = hires.get("descriptor_path_counts") or {}
    if descriptor_paths != fixture_expected["descriptor_path_counts"]:
        raise SystemExit(
            f"FAIL: zero-config refresh fixture {label} expected descriptor_path_counts="
            f"{fixture_expected['descriptor_path_counts']!r}, got {descriptor_paths!r}."
        )
PY

echo "emu_conformance_paper_mario_full_cache_phrb_authorities_zero_config_refresh: PASS ($PACKAGE_PATH)"
