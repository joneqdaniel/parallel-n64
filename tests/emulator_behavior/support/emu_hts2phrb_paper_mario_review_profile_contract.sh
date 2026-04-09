#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

CACHE_PATH="${EMU_HTS2PHRB_PM64_CACHE_PATH:-$REPO_ROOT/assets/PAPER MARIO_HIRESTEXTURES.hts}"
BUNDLE_PATH="${EMU_HTS2PHRB_PM64_REVIEW_PROFILE_BUNDLE_PATH:-$REPO_ROOT/artifacts/paper-mario-probes/validation/20260407-title-timeout-selected-package-7701ac09-dedupe-review/validation-summary.json}"
REVIEW_PROFILE_PATH="${EMU_HTS2PHRB_PM64_REVIEW_PROFILE_PATH:-$REPO_ROOT/tools/hires_selected_package_review_profile.json}"

if [[ ! -f "$CACHE_PATH" ]]; then
  echo "SKIP: Paper Mario legacy cache not found at $CACHE_PATH."
  exit 77
fi

if [[ ! -f "$BUNDLE_PATH" ]]; then
  echo "SKIP: Paper Mario review-profile bundle summary not found at $BUNDLE_PATH."
  exit 77
fi

if [[ ! -f "$REVIEW_PROFILE_PATH" ]]; then
  echo "SKIP: Paper Mario review profile not found at $REVIEW_PROFILE_PATH."
  exit 77
fi

TMPDIR_RUN="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR_RUN"
}
trap cleanup EXIT

OUTPUT_DIR="$TMPDIR_RUN/review-profile"

python3 "$REPO_ROOT/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$BUNDLE_PATH" \
  --bundle-step 960 \
  --review-profile "$REVIEW_PROFILE_PATH" \
  --runtime-overlay-mode auto \
  --minimum-outcome partial-runtime-package \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR" >/dev/null

python3 "$REPO_ROOT/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$BUNDLE_PATH" \
  --bundle-step 960 \
  --review-profile "$REVIEW_PROFILE_PATH" \
  --runtime-overlay-mode auto \
  --minimum-outcome partial-runtime-package \
  --reuse-existing \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR" >/dev/null

python3 - "$OUTPUT_DIR/hts2phrb-report.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text())

if report.get("requested_family_count") != 10:
    raise SystemExit(f"FAIL: expected 10 requested families for the timeout review-profile bundle, got {report!r}.")
if int(report.get("package_manifest_record_count") or 0) != 10:
    raise SystemExit(f"FAIL: expected 10 canonical package records for the timeout review-profile bundle, got {report!r}.")
if int(report.get("package_manifest_runtime_ready_record_count") or 0) < 2:
    raise SystemExit(f"FAIL: expected at least 2 runtime-ready package records, got {report!r}.")
if report.get("conversion_outcome") not in {"partial-runtime-package", "promotable-runtime-package"}:
    raise SystemExit(f"FAIL: unexpected conversion outcome for review-profile front door {report!r}.")
if not report.get("gate_success") or report.get("gate_failures"):
    raise SystemExit(f"FAIL: review-profile front door unexpectedly failed gates {report!r}.")
if not report.get("reused_existing"):
    raise SystemExit(f"FAIL: second review-profile run should have reused the prior output {report!r}.")

review_profile_paths = report.get("review_profile_paths") or []
duplicate_review_paths = report.get("duplicate_review_paths") or []
alias_group_review_paths = report.get("alias_group_review_paths") or []
if len(review_profile_paths) != 1 or len(duplicate_review_paths) != 1 or len(alias_group_review_paths) != 1:
    raise SystemExit(f"FAIL: expected one profile/duplicate/alias review input in the report {report!r}.")

valid_states = {"applied", "skipped"}
duplicate_state = report.get("duplicate_review_state")
alias_state = report.get("alias_group_review_state")
if duplicate_state not in valid_states:
    raise SystemExit(f"FAIL: duplicate review state must stay explicit on the front door {report!r}.")
if alias_state not in valid_states:
    raise SystemExit(f"FAIL: alias review state must stay explicit on the front door {report!r}.")

duplicate_changes = int(report.get("duplicate_review_change_count") or 0)
duplicate_skips = int(report.get("duplicate_review_skip_count") or 0)
alias_changes = int(report.get("alias_group_review_change_count") or 0)
alias_skips = int(report.get("alias_group_review_skip_count") or 0)
if duplicate_changes + duplicate_skips != 1:
    raise SystemExit(f"FAIL: duplicate review input should be either applied or skipped exactly once {report!r}.")
if alias_changes + alias_skips != 1:
    raise SystemExit(f"FAIL: alias review input should be either applied or skipped exactly once {report!r}.")

valid_skip_reasons = {"record-not-in-scope", "no-asset-candidates"}
if duplicate_skips:
    skip = (report.get("duplicate_review_skips") or [{}])[0]
    if skip.get("skip_reason") not in valid_skip_reasons:
        raise SystemExit(f"FAIL: duplicate review skip reason was unexpected {skip!r}.")
if alias_skips:
    skip = (report.get("alias_group_review_skips") or [{}])[0]
    if skip.get("skip_reason") not in valid_skip_reasons:
        raise SystemExit(f"FAIL: alias review skip reason was unexpected {skip!r}.")
PY

echo "emu_hts2phrb_paper_mario_review_profile_contract: PASS"
