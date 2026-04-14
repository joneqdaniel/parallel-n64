#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/tools/scenarios/lib/common.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

write_capture_bundle() {
  local bundle_dir="$1"
  local mode="$2"
  mkdir -p "$bundle_dir/captures" "$bundle_dir/traces"
  printf 'fixture-capture' > "$bundle_dir/captures/capture.png"
  cat > "$bundle_dir/bundle.json" <<EOF
{"mode":"$mode"}
EOF
  cat > "$bundle_dir/traces/paper-mario-game-status.json" <<'EOF'
{
  "paper_mario_us": {
    "cur_game_mode": {
      "init_symbol": "state_init_title_screen",
      "step_symbol": "state_step_title_screen"
    }
  }
}
EOF
}

PASS_BUNDLE="$TMPDIR/pass-on"
write_capture_bundle "$PASS_BUNDLE" "on"
cat > "$PASS_BUNDLE/traces/hires-evidence.json" <<'EOF'
{
  "summary": {
    "provider": "on",
    "source_mode": "phrb-only",
    "entry_count": 66,
    "native_sampled_entry_count": 65,
    "compat_entry_count": 1,
    "sampled_index_count": 65,
    "sampled_family_count": 4,
    "compat_low32_family_count": 1,
    "source_counts": {
      "phrb": 66
    }
  },
  "provenance": {
    "available": true,
    "source_class_counts": {"authored-rdram": 4},
    "provenance_class_counts": {"loadtile": 4}
  },
  "draw_usage": {
    "available": true,
    "draw_class_counts": {"texrect": 4}
  },
  "sampler_usage": {"available": false},
  "sampled_object_probe": {"available": false}
}
EOF
PASS_HASH="$(scenario_sha256_file "$PASS_BUNDLE/captures/capture.png")"
(
  export EXPECTED_HIRES_SUMMARY_PROVIDER_ON="on"
  export EXPECTED_HIRES_SUMMARY_SOURCE_MODE_ON="phrb-only"
  export EXPECTED_HIRES_MIN_SUMMARY_ENTRY_COUNT_ON="1"
  export EXPECTED_HIRES_MIN_SUMMARY_NATIVE_SAMPLED_ENTRY_COUNT_ON="1"
  export EXPECTED_HIRES_MIN_SUMMARY_SOURCE_PHRB_COUNT_ON="1"
  export EXPECTED_HIRES_PROVENANCE_AVAILABLE_ON="1"
  export EXPECTED_HIRES_DRAW_USAGE_AVAILABLE_ON="1"
  export EXPECTED_HIRES_SOURCE_CLASS_PRESENT_ON="authored-rdram"
  export EXPECTED_HIRES_PROVENANCE_CLASS_PRESENT_ON="loadtile"
  export EXPECTED_HIRES_DRAW_CLASS_PRESENT_ON="texrect"
  scenario_verify_paper_mario_fixture \
    "$PASS_BUNDLE" \
    "$PASS_BUNDLE/verification.json" \
    "paper-mario-title-screen" \
    "$PASS_HASH" \
    "state_init_title_screen" \
    "state_step_title_screen"
)

PASS_OFF_BUNDLE="$TMPDIR/pass-off"
write_capture_bundle "$PASS_OFF_BUNDLE" "off"
cat > "$PASS_OFF_BUNDLE/traces/hires-evidence.json" <<'EOF'
{
  "summary": null,
  "provenance": null,
  "draw_usage": null,
  "sampler_usage": null,
  "sampled_object_probe": null
}
EOF
PASS_OFF_HASH="$(scenario_sha256_file "$PASS_OFF_BUNDLE/captures/capture.png")"
(
  export EXPECTED_HIRES_PROVENANCE_AVAILABLE_OFF="0"
  export EXPECTED_HIRES_DRAW_USAGE_AVAILABLE_OFF="0"
  scenario_verify_paper_mario_fixture \
    "$PASS_OFF_BUNDLE" \
    "$PASS_OFF_BUNDLE/verification.json" \
    "paper-mario-title-screen" \
    "$PASS_OFF_HASH" \
    "state_init_title_screen" \
    "state_step_title_screen"
)

FAIL_BUNDLE="$TMPDIR/fail-on"
write_capture_bundle "$FAIL_BUNDLE" "on"
cat > "$FAIL_BUNDLE/traces/hires-evidence.json" <<'EOF'
{
  "summary": {"provider": "on"},
  "provenance": {
    "available": true,
    "source_class_counts": {"authored-rdram": 4},
    "provenance_class_counts": {"copy-cycle": 4}
  },
  "draw_usage": {
    "available": true,
    "draw_class_counts": {"texrect": 4}
  },
  "sampler_usage": {"available": false},
  "sampled_object_probe": {"available": false}
}
EOF
FAIL_HASH="$(scenario_sha256_file "$FAIL_BUNDLE/captures/capture.png")"
set +e
(
  export EXPECTED_HIRES_SUMMARY_PROVIDER_ON="on"
  export EXPECTED_HIRES_PROVENANCE_AVAILABLE_ON="1"
  export EXPECTED_HIRES_DRAW_USAGE_AVAILABLE_ON="1"
  export EXPECTED_HIRES_SOURCE_CLASS_PRESENT_ON="authored-rdram"
  export EXPECTED_HIRES_PROVENANCE_CLASS_PRESENT_ON="loadtile"
  export EXPECTED_HIRES_DRAW_CLASS_PRESENT_ON="texrect"
  scenario_verify_paper_mario_fixture \
    "$FAIL_BUNDLE" \
    "$FAIL_BUNDLE/verification.json" \
    "paper-mario-title-screen" \
    "$FAIL_HASH" \
    "state_init_title_screen" \
    "state_step_title_screen"
)
status=$?
set -e
if [[ "$status" -eq 0 ]]; then
  echo "expected semantic hi-res verification failure, but check passed" >&2
  exit 1
fi
