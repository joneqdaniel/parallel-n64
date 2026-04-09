#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

CACHE_PATH="${EMU_HTS2PHRB_PM64_CACHE_PATH:-$REPO_ROOT/assets/PAPER MARIO_HIRESTEXTURES.hts}"
CONTEXT_ROOT="${EMU_HTS2PHRB_PM64_OVERLAY_REVIEW_CONTEXT_ROOT:-$REPO_ROOT/artifacts/paper-mario-probes/validation/20260408-full-cache-phrb-authorities-authority-context-abs-summary-fresh/validation-summary.json}"
REVIEW_PROFILE_PATH="${EMU_HTS2PHRB_PM64_OVERLAY_REVIEW_PROFILE_PATH:-$REPO_ROOT/tools/hires_runtime_overlay_review_profile.json}"
TRANSPORT_POLICY_PATH="${EMU_HTS2PHRB_PM64_OVERLAY_REVIEW_TRANSPORT_POLICY_PATH:-$REPO_ROOT/tools/hires_runtime_overlay_review_transport_policy.json}"

if [[ ! -f "$CACHE_PATH" ]]; then
  echo "SKIP: Paper Mario legacy cache not found at $CACHE_PATH."
  exit 77
fi

if [[ ! -f "$CONTEXT_ROOT" ]]; then
  echo "SKIP: Paper Mario overlay-review context summary not found at $CONTEXT_ROOT."
  exit 77
fi

if [[ ! -f "$REVIEW_PROFILE_PATH" ]]; then
  echo "SKIP: Paper Mario overlay-review profile not found at $REVIEW_PROFILE_PATH."
  exit 77
fi

if [[ ! -f "$TRANSPORT_POLICY_PATH" ]]; then
  echo "SKIP: Paper Mario overlay-review transport policy not found at $TRANSPORT_POLICY_PATH."
  exit 77
fi

TMPDIR_RUN="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR_RUN"
}
trap cleanup EXIT

OUTPUT_DIR="$TMPDIR_RUN/overlay-review-profile"
MAX_TOTAL_MS="15000"
MAX_BINARY_PACKAGE_BYTES="2100000000"

python3 "$REPO_ROOT/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --context-bundle "$CONTEXT_ROOT" \
  --review-profile "$REVIEW_PROFILE_PATH" \
  --minimum-outcome partial-runtime-package \
  --expect-context-class context-enriched \
  --max-total-ms "$MAX_TOTAL_MS" \
  --max-binary-package-bytes "$MAX_BINARY_PACKAGE_BYTES" \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR" >/dev/null

python3 "$REPO_ROOT/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --context-bundle "$CONTEXT_ROOT" \
  --review-profile "$REVIEW_PROFILE_PATH" \
  --minimum-outcome partial-runtime-package \
  --expect-context-class context-enriched \
  --max-total-ms "$MAX_TOTAL_MS" \
  --max-binary-package-bytes "$MAX_BINARY_PACKAGE_BYTES" \
  --reuse-existing \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR" >/dev/null

python3 - "$OUTPUT_DIR/hts2phrb-report.json" "$REVIEW_PROFILE_PATH" "$TRANSPORT_POLICY_PATH" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text())
review_profile_path = Path(sys.argv[2]).resolve()
transport_policy_path = Path(sys.argv[3]).resolve()

expected = {
    "conversion_outcome": "partial-runtime-package",
    "requested_family_count": 8992,
    "package_manifest_record_count": 8883,
    "package_manifest_runtime_ready_record_count": 8515,
    "package_manifest_runtime_ready_record_class": "mixed-native-and-compat",
    "package_manifest_runtime_ready_native_sampled_record_count": 28,
    "package_manifest_runtime_ready_compat_record_count": 8487,
    "package_manifest_runtime_deferred_record_count": 368,
    "package_manifest_runtime_deferred_record_class": "compat-only",
    "binding_count": 19,
    "unresolved_count": 9,
    "runtime_overlay_built": True,
    "runtime_overlay_reason": "runtime-context-available",
    "context_bundle_class": "context-enriched",
    "context_bundle_input_count": 1,
    "context_bundle_resolution_count": 3,
    "minimum_outcome": "partial-runtime-package",
    "gate_success": True,
    "reused_existing": True,
    "promotion_blocker_runtime_state_counts": {"canonical-only": 368},
    "promotion_blocker_reason_counts": {"exact-family-ambiguous": 368},
    "promotion_blocker_reason_unclassified_family_count": 0,
    "unresolved_family_reason_runtime_state_counts": {
        "exact-family-ambiguous": {"canonical-only": 368, "runtime-ready-package": 4}
    },
    "unresolved_family_reason_variant_group_count_counts": {"exact-family-ambiguous": {"2": 259, "3": 52, "4": 60, "5": 1}},
    "runtime_overlay_reason_counts": {"proxy-transport-selection-required": 9},
    "runtime_overlay_hash_review_class_counts": {
        "pixel-divergent-multi-dim": 3,
        "pixel-divergent-single-dim": 6,
    },
    "runtime_overlay_unresolved_count": 9,
    "runtime_overlay_candidate_set_cluster_count": 9,
    "runtime_overlay_candidate_set_cluster_size_counts": {"1": 9},
    "runtime_overlay_blocker_cluster_class_counts": {
        "large-multi-dim-cluster": 1,
        "large-single-dim-cluster": 3,
        "linked-import-ambiguity": 1,
        "small-multi-dim-cluster": 1,
        "small-single-dim-cluster": 3,
    },
    "runtime_overlay_action_hint_counts": {
        "defer-large-transport-cluster": 4,
        "defer-to-import-family-work": 1,
        "manual-selection-review": 4,
    },
    "runtime_overlay_candidate_set_review_group_count": 0,
    "runtime_overlay_blockers": [
        {"code": "overlay-proxy-transport-selection-required-cases", "count": 9},
        {"code": "overlay-pixel-divergent-single-dim-cases", "count": 6},
        {"code": "overlay-pixel-divergent-multi-dim-cases", "count": 3},
    ],
}

for key, expected_value in expected.items():
    actual = report.get(key)
    if actual != expected_value:
        raise SystemExit(
            f"FAIL: overlay-review profile report expected {key}={expected_value!r}, got {actual!r}."
        )

if report.get("gate_failures"):
    raise SystemExit(f"FAIL: overlay-review profile unexpectedly recorded gate failures: {report.get('gate_failures')!r}.")

review_profile_paths = [Path(value).resolve() for value in (report.get("review_profile_paths") or [])]
if review_profile_paths != [review_profile_path]:
    raise SystemExit(f"FAIL: unexpected review profile paths: {review_profile_paths!r}")

if Path(report.get("transport_policy_path") or "").resolve() != transport_policy_path:
    raise SystemExit(f"FAIL: unexpected transport policy path: {report.get('transport_policy_path')!r}")

if report.get("duplicate_review_paths") not in ([], None):
    raise SystemExit(f"FAIL: overlay-review profile should not inject duplicate review inputs: {report.get('duplicate_review_paths')!r}")
if report.get("alias_group_review_paths") not in ([], None):
    raise SystemExit(f"FAIL: overlay-review profile should not inject alias-group review inputs: {report.get('alias_group_review_paths')!r}")

overlay_review = report.get("runtime_overlay_review_summary") or {}
if overlay_review.get("candidate_set_cluster_count") != 9:
    raise SystemExit(f"FAIL: unexpected overlay review candidate-set cluster count: {overlay_review!r}")
if overlay_review.get("candidate_set_cluster_size_counts") != {"1": 9}:
    raise SystemExit(f"FAIL: unexpected overlay review candidate-set cluster sizes: {overlay_review!r}")

overlay_candidate_review = report.get("runtime_overlay_candidate_set_review_summary") or {}
if overlay_candidate_review.get("candidate_set_review_group_count") != 0:
    raise SystemExit(f"FAIL: expected the tracked review profile to eliminate candidate-set review groups: {overlay_candidate_review!r}")

summary_text = Path(report["summary_path"]).read_text()
if f"- Transport policy: `{transport_policy_path}`" not in summary_text:
    raise SystemExit(f"FAIL: markdown summary did not surface the tracked transport policy: {summary_text!r}")
PY

echo "emu_hts2phrb_paper_mario_runtime_overlay_review_profile_contract: PASS"
