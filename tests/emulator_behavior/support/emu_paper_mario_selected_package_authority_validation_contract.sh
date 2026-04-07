#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/package.phrb"
printf 'phrb' > "$CACHE_PATH"

write_fixture_bundle() {
  local label="$1"
  local fixture_id="$2"
  local screenshot_sha="$3"
  local init_symbol="$4"
  local step_symbol="$5"
  local entry_count="$6"
  local native_count="$7"
  local phrb_count="$8"

  local bundle_dir="$TMP_DIR/bundles/$label"
  mkdir -p "$bundle_dir/traces"
  cat > "$bundle_dir/traces/fixture-verification.json" <<EOF
{
  "fixture_id": "$fixture_id",
  "passed": true,
  "checks": {
    "screenshot_sha256": "$screenshot_sha"
  },
  "actual": {
    "capture_path": "$bundle_dir/captures/capture.png",
    "init_symbol": "$init_symbol",
    "step_symbol": "$step_symbol",
    "hires_summary_provider": "on",
    "hires_summary_source_mode": "phrb-only",
    "hires_summary_entry_count": $entry_count,
    "hires_summary_native_sampled_entry_count": $native_count,
    "hires_summary_source_phrb_count": $phrb_count,
    "hires_exact_hit_count": 12,
    "hires_exact_conflict_miss_count": 3,
    "hires_exact_unresolved_miss_count": 4
  },
  "failures": []
}
EOF
}

write_fixture_bundle "title-screen" "paper-mario-title-screen" "titlehash" "state_init_title_screen" "state_step_title_screen" 10 10 10
write_fixture_bundle "file-select" "paper-mario-file-select" "filehash" "state_init_file_select" "state_step_file_select" 20 20 20
write_fixture_bundle "kmr-03-entry-5" "paper-mario-kmr-03-entry-5" "kmrhash" "state_init_world" "state_step_world" 30 30 30

bash "$REPO_ROOT/tools/scenarios/paper-mario-selected-package-authority-validation.sh" \
  --cache-path "$CACHE_PATH" \
  --bundle-root "$TMP_DIR/bundles" \
  --reuse

python3 - "$TMP_DIR/bundles/validation-summary.json" "$TMP_DIR/bundles/validation-summary.md" <<'PY'
import json
import sys
from pathlib import Path

summary_path = Path(sys.argv[1])
md_path = Path(sys.argv[2])
summary = json.loads(summary_path.read_text())
markdown = md_path.read_text()

def check(condition, message):
    if not condition:
        raise SystemExit(message)

check(summary.get("all_passed") is True, f"unexpected pass state: {summary}")
fixtures = summary.get("fixtures") or []
check(len(fixtures) == 3, f"unexpected fixture count: {fixtures}")
check(fixtures[0]["hires_summary"]["source_mode"] == "phrb-only", f"unexpected source mode: {fixtures[0]}")
check(fixtures[2]["sampled_object_probe"]["exact_unresolved_miss_count"] == 4, f"unexpected sampled probe summary: {fixtures[2]}")
check("All passed: `true`" in markdown, f"missing all-passed markdown: {markdown}")
check("source mode `phrb-only`" in markdown, f"missing source mode markdown: {markdown}")
print("emu_paper_mario_selected_package_authority_validation_contract: PASS")
PY
