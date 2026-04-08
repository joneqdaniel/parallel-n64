#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

CACHE_PATH="${EMU_HTS2PHRB_PM64_PRE_V401_CACHE_PATH:-$REPO_ROOT/assets/PAPER MARIO_HIRESTEXTURES.pre-v401-14774f23.hts}"
CONTEXT_ROOT="${EMU_HTS2PHRB_PM64_CONTEXT_ROOT:-$REPO_ROOT/artifacts/paper-mario-probes/validation/20260408-full-cache-phrb-authorities-authority-context-root-provenance-promoted-round2/validation-summary.json}"

if [[ ! -f "$CACHE_PATH" ]]; then
  echo "SKIP: Paper Mario pre-v401 legacy cache not found at $CACHE_PATH."
  exit 77
fi

if [[ ! -f "$CONTEXT_ROOT" ]]; then
  echo "SKIP: Paper Mario authority context summary not found at $CONTEXT_ROOT."
  exit 77
fi

TMPDIR_RUN="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR_RUN"
}
trap cleanup EXIT

ZERO_DIR="$TMPDIR_RUN/zero"
CONTEXT_DIR="$TMPDIR_RUN/context"

python3 "$REPO_ROOT/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --output-dir "$ZERO_DIR" \
  --minimum-outcome partial-runtime-package \
  --expect-context-class zero-context \
  --stdout-format json >/dev/null

python3 "$REPO_ROOT/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --context-bundle "$CONTEXT_ROOT" \
  --output-dir "$CONTEXT_DIR" \
  --minimum-outcome partial-runtime-package \
  --expect-context-class context-enriched \
  --stdout-format json >/dev/null

python3 - "$ZERO_DIR/hts2phrb-report.json" "$CONTEXT_DIR/hts2phrb-report.json" <<'PY'
import json
import sys
from pathlib import Path

zero = json.loads(Path(sys.argv[1]).read_text())
context = json.loads(Path(sys.argv[2]).read_text())

expected_zero = {
    "conversion_outcome": "partial-runtime-package",
    "requested_family_count": 8983,
    "package_manifest_record_count": 8983,
    "package_manifest_runtime_ready_record_count": 8599,
    "package_manifest_runtime_ready_record_class": "compat-only",
    "package_manifest_runtime_ready_native_sampled_record_count": 0,
    "package_manifest_runtime_ready_compat_record_count": 8599,
    "package_manifest_runtime_deferred_record_count": 384,
    "package_manifest_runtime_deferred_record_class": "compat-only",
    "unresolved_count": 0,
    "runtime_overlay_built": False,
    "runtime_overlay_reason": "no-runtime-context",
    "context_bundle_class": "zero-context",
    "context_bundle_input_count": 0,
    "context_bundle_resolution_count": 0,
}

expected_context = {
    "conversion_outcome": "partial-runtime-package",
    "requested_family_count": 8983,
    "package_manifest_record_count": 8874,
    "package_manifest_runtime_ready_record_count": 8494,
    "package_manifest_runtime_ready_record_class": "mixed-native-and-compat",
    "package_manifest_runtime_ready_native_sampled_record_count": 28,
    "package_manifest_runtime_ready_compat_record_count": 8466,
    "package_manifest_runtime_deferred_record_count": 380,
    "package_manifest_runtime_deferred_record_class": "compat-only",
    "unresolved_count": 0,
    "runtime_overlay_built": False,
    "runtime_overlay_reason": "no-runtime-context",
    "context_bundle_class": "context-enriched",
    "context_bundle_input_count": 1,
    "context_bundle_resolution_count": 3,
}

for label, report, expected in (
    ("pre-v401 zero-config", zero, expected_zero),
    ("pre-v401 authority-context", context, expected_context),
):
    for key, expected_value in expected.items():
        actual = report.get(key)
        if actual != expected_value:
            raise SystemExit(
                f"FAIL: {label} report expected {key}={expected_value!r}, got {actual!r}."
            )
PY

echo "emu_hts2phrb_paper_mario_pre_v401_full_cache_contract: PASS"
