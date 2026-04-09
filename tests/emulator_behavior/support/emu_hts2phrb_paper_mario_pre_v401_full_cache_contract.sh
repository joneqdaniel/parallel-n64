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
MAX_TOTAL_MS="12000"
MAX_BINARY_PACKAGE_BYTES="2100000000"

python3 "$REPO_ROOT/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --output-dir "$ZERO_DIR" \
  --minimum-outcome partial-runtime-package \
  --expect-context-class zero-context \
  --max-total-ms "$MAX_TOTAL_MS" \
  --max-binary-package-bytes "$MAX_BINARY_PACKAGE_BYTES" \
  --stdout-format json >/dev/null

python3 "$REPO_ROOT/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --context-bundle "$CONTEXT_ROOT" \
  --output-dir "$CONTEXT_DIR" \
  --minimum-outcome partial-runtime-package \
  --expect-context-class context-enriched \
  --max-total-ms "$MAX_TOTAL_MS" \
  --max-binary-package-bytes "$MAX_BINARY_PACKAGE_BYTES" \
  --stdout-format json >/dev/null

python3 "$REPO_ROOT/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --output-dir "$ZERO_DIR" \
  --minimum-outcome partial-runtime-package \
  --expect-context-class zero-context \
  --max-total-ms "$MAX_TOTAL_MS" \
  --max-binary-package-bytes "$MAX_BINARY_PACKAGE_BYTES" \
  --reuse-existing \
  --stdout-format json >/dev/null

python3 "$REPO_ROOT/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --context-bundle "$CONTEXT_ROOT" \
  --output-dir "$CONTEXT_DIR" \
  --minimum-outcome partial-runtime-package \
  --expect-context-class context-enriched \
  --max-total-ms "$MAX_TOTAL_MS" \
  --max-binary-package-bytes "$MAX_BINARY_PACKAGE_BYTES" \
  --reuse-existing \
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
    "minimum_outcome": "partial-runtime-package",
    "gate_success": True,
    "reused_existing": True,
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
    "binding_count": 15,
    "unresolved_count": 13,
    "runtime_overlay_built": True,
    "runtime_overlay_reason": "runtime-context-available",
    "context_bundle_class": "context-enriched",
    "context_bundle_input_count": 1,
    "context_bundle_resolution_count": 3,
    "minimum_outcome": "partial-runtime-package",
    "gate_success": True,
    "reused_existing": True,
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
    if report.get("gate_failures"):
        raise SystemExit(f"FAIL: {label} report unexpectedly recorded gate failures: {report.get('gate_failures')!r}.")
    if float(report.get("total_runtime_ms") or 0.0) <= 0.0:
        raise SystemExit(f"FAIL: {label} report did not record total_runtime_ms: {report!r}.")
    if int(report.get("binary_package_bytes") or 0) <= 0:
        raise SystemExit(f"FAIL: {label} report did not record binary_package_bytes: {report!r}.")

overlay_review = context.get("runtime_overlay_review_summary") or {}
if overlay_review.get("unresolved_overlay_count") != 13:
    raise SystemExit(f"FAIL: authority-context overlay review expected 13 unresolved cases, got {overlay_review!r}.")
if overlay_review.get("reason_counts") != {"proxy-transport-selection-required": 13}:
    raise SystemExit(f"FAIL: authority-context overlay review had unexpected reasons: {overlay_review!r}.")
if overlay_review.get("hash_review_class_counts") != {
    "pixel-divergent-multi-dim": 5,
    "pixel-divergent-single-dim": 8,
}:
    raise SystemExit(f"FAIL: authority-context overlay review had unexpected hash review classes: {overlay_review!r}.")
if overlay_review.get("identical_alpha_hash_case_count_counts") != {"0": 9, "1": 4}:
    raise SystemExit(f"FAIL: authority-context overlay review had unexpected identical alpha-hash counts: {overlay_review!r}.")
if overlay_review.get("alpha_hash_overlap_case_count_counts") != {"0": 7, "1": 3, "2": 2, "3": 1}:
    raise SystemExit(f"FAIL: authority-context overlay review had unexpected alpha-hash overlap counts: {overlay_review!r}.")
if overlay_review.get("transport_candidate_alpha_hash_count_counts") != {
    "2": 6,
    "3": 1,
    "4": 1,
    "29": 1,
    "51": 1,
    "54": 1,
    "64": 1,
    "93": 1,
}:
    raise SystemExit(f"FAIL: authority-context overlay review had unexpected alpha-hash histogram: {overlay_review!r}.")
if overlay_review.get("transport_candidate_hash_error_count_counts") != {"0": 13}:
    raise SystemExit(f"FAIL: authority-context overlay review had unexpected hash error counts: {overlay_review!r}.")
if not context.get("runtime_overlay_review_json_path") or not Path(context["runtime_overlay_review_json_path"]).exists():
    raise SystemExit(f"FAIL: authority-context overlay review json path missing: {context.get('runtime_overlay_review_json_path')!r}.")
if not context.get("runtime_overlay_review_markdown_path") or not Path(context["runtime_overlay_review_markdown_path"]).exists():
    raise SystemExit(f"FAIL: authority-context overlay review markdown path missing: {context.get('runtime_overlay_review_markdown_path')!r}.")
PY

echo "emu_hts2phrb_paper_mario_pre_v401_full_cache_contract: PASS"
