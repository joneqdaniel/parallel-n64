#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

FIXTURE_ID="paper-mario-file-select-block-family-probe"
MANIFEST="$REPO_ROOT/tools/fixtures/paper-mario-file-select-block-family-probe.yaml"
MODE="on"
DRY_RUN=1
BUNDLE_DIR=""
SOURCE_BUNDLE="${SOURCE_BUNDLE:-$REPO_ROOT/artifacts/paper-mario-file-select/on/20260326-texel-link-check}"
RUNTIME_ENV="${RUNTIME_ENV_OVERRIDE:-$SCRIPT_DIR/paper-mario-file-select.runtime.env}"

usage() {
  cat <<'EOF'
Usage:
  tools/scenarios/paper-mario-file-select-block-family-probe.sh [options]

Options:
  --mode off|on            Scenario mode label (default: on)
  --source-bundle PATH     Source bundle used to derive the 64x1 probe plan
  --bundle-dir PATH        Output bundle directory
  --run                    Execute the live probe
  -h, --help               Show this help
EOF
}

while (($#)); do
  case "$1" in
    --mode)
      shift
      MODE="${1:-}"
      if [[ "$MODE" != "off" && "$MODE" != "on" ]]; then
        echo "--mode must be 'off' or 'on'." >&2
        exit 2
      fi
      ;;
    --source-bundle)
      shift
      SOURCE_BUNDLE="${1:-}"
      ;;
    --bundle-dir)
      shift
      BUNDLE_DIR="${1:-}"
      ;;
    --run)
      DRY_RUN=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ -z "$BUNDLE_DIR" ]]; then
  BUNDLE_DIR="$(scenario_default_bundle_dir "$REPO_ROOT" "$FIXTURE_ID" "$MODE")"
fi

scenario_prepare_bundle_dirs "$BUNDLE_DIR"
scenario_print_header "$FIXTURE_ID" "$MODE" "$BUNDLE_DIR" "$MANIFEST"

PLAN_JSON="$BUNDLE_DIR/traces/hires-block-family-plan.json"
REPORT_JSON="$BUNDLE_DIR/traces/hires-block-family-report.json"
REPORT_MD="$BUNDLE_DIR/traces/hires-block-family-report.md"

python3 "$REPO_ROOT/tools/hires_block_family_probe.py" plan \
  --source-bundle "$SOURCE_BUNDLE" \
  --mode block \
  --outcome miss \
  --formatsize 514 \
  --width 64 \
  --height 1 \
  --tile 7 \
  --output "$PLAN_JSON"

PROBE_MIN_ADDR="$(python3 - <<'PY' "$PLAN_JSON"
import json, sys
plan = json.load(open(sys.argv[1]))
print(plan["snapshot"]["min_addr"])
PY
)"
PROBE_SPAN_BYTES="$(python3 - <<'PY' "$PLAN_JSON"
import json, sys
plan = json.load(open(sys.argv[1]))
print(plan["snapshot"]["span_bytes"])
PY
)"

ROM_PATH="$REPO_ROOT/assets/Paper Mario (USA).zip"
PACK_PATH="$REPO_ROOT/assets/PAPER MARIO_HIRESTEXTURES.hts"
RETROARCH_PATH="/home/auro/code/RetroArch"
AUTHORITATIVE_STATE_PATH=""
AUTHORITATIVE_STATE_SHA256="missing"
EXPECTED_SCREENSHOT_SHA256=""

cat > "$BUNDLE_DIR/bundle.json" <<EOF
{
  "fixture_id": "$FIXTURE_ID",
  "mode": "$MODE",
  "manifest_path": "$MANIFEST",
  "bundle_dir": "$BUNDLE_DIR",
  "created_at": "$(date -Iseconds)",
  "probe_source_bundle": "$SOURCE_BUNDLE",
  "runtime_rules": {
    "internal_scale": "4x",
    "serial_execution": true,
    "display_required": true
  },
  "inputs": {
    "rom_path": "$ROM_PATH",
    "rom_sha256": "$(scenario_sha256_file "$ROM_PATH")",
    "hires_pack_path": "$PACK_PATH",
    "hires_pack_sha256": "$(scenario_sha256_file "$PACK_PATH")",
    "retroarch_path": "$RETROARCH_PATH"
  },
  "probe": {
    "plan_path": "$PLAN_JSON",
    "snapshot_min_addr": "$PROBE_MIN_ADDR",
    "snapshot_span_bytes": $PROBE_SPAN_BYTES
  },
  "status": {
    "scenario_state": "bundle_initialized",
    "runtime_executed": false
  }
}
EOF

if (( DRY_RUN )); then
  echo "[scenario] dry-run complete; runtime launch is intentionally deferred."
  exit 0
fi

scenario_source_runtime_env "$RUNTIME_ENV"

if [[ ! -f "${AUTHORITATIVE_STATE_PATH:-}" ]]; then
  echo "[scenario] authoritative file-select state is required." >&2
  exit 1
fi

AUTHORITATIVE_STATE_SHA256="$(scenario_sha256_file "$AUTHORITATIVE_STATE_PATH")"
VERIFY_SCREENSHOT_SHA256=""
if [[ "$MODE" == "off" ]]; then
  VERIFY_SCREENSHOT_SHA256="${EXPECTED_SCREENSHOT_SHA256_OFF:-${EXPECTED_SCREENSHOT_SHA256:-}}"
else
  VERIFY_SCREENSHOT_SHA256="${EXPECTED_SCREENSHOT_SHA256_ON:-}"
fi

mkdir -p "$BUNDLE_DIR/states/ParaLLEl N64"
cp "$AUTHORITATIVE_STATE_PATH" "$BUNDLE_DIR/states/ParaLLEl N64/Paper Mario (USA).state"

scenario_patch_file "$BUNDLE_DIR/bundle.json" 's|"scenario_state": "bundle_initialized"|"scenario_state": "runtime_prepared"|g; s|"runtime_executed": false|"runtime_executed": true|g'

PARALLEL_N64_GFX_PLUGIN_OVERRIDE="parallel" \
PARALLEL_RDP_HIRES_CACHE_PATH="$PACK_PATH" \
PARALLEL_RDP_HIRES_DEBUG="$([[ "$MODE" == "on" ]] && echo 1 || echo 0)" \
"$REPO_ROOT/tools/adapters/retroarch_stdin_session.sh" \
  --bundle-dir "$BUNDLE_DIR" \
  --mode "$MODE" \
  --retroarch-bin "$RETROARCH_BIN" \
  --base-config "$RETROARCH_BASE_CONFIG" \
  --core "$CORE_PATH" \
  --rom "$ROM_PATH" \
  --startup-wait "$STARTUP_WAIT" \
  --command "WAIT_COMMAND_READY 120" \
  --command "LOAD_STATE_SLOT_PAUSED 0" \
  --command "STEP_FRAME ${POST_LOAD_SETTLE_FRAMES}" \
  --command "WAIT_STATUS_FRAME PAUSED ${POST_LOAD_SETTLE_FRAMES} 10" \
  --command "SNAPSHOT_CORE_MEMORY paper-mario-gamestatus 800740aa 230" \
  --command "SNAPSHOT_CORE_MEMORY paper-mario-curgamemode 80151700 20" \
  --command "SNAPSHOT_CORE_MEMORY paper-mario-transition 800a0944 8" \
  --command "SNAPSHOT_CORE_MEMORY paper-mario-filemenu-current-menu 8024c098 1" \
  --command "SNAPSHOT_CORE_MEMORY paper-mario-filemenu-menus 80249b84 8" \
  --command "SNAPSHOT_CORE_POINTER_MEMORY paper-mario-filemenu-main-panel 80249b84 28" \
  --command "SNAPSHOT_CORE_POINTER_MEMORY paper-mario-filemenu-confirm-panel 80249b88 28" \
  --command "SNAPSHOT_CORE_MEMORY paper-mario-save-slot-has-data 80077a24 4" \
  --command "SNAPSHOT_CORE_MEMORY paper-mario-window-files-title 8015a2f0 32" \
  --command "SNAPSHOT_CORE_MEMORY paper-mario-window-files-slot2-body 8015a470 32" \
  --command "SNAPSHOT_CORE_MEMORY paper-mario-block-family-span ${PROBE_MIN_ADDR} ${PROBE_SPAN_BYTES}" \
  --command "SCREENSHOT" \
  --command "WAIT_NEW_CAPTURE 10" \
  --command "QUIT"

if [[ -f "$BUNDLE_DIR/traces/paper-mario-gamestatus.core-memory.txt" ]]; then
  scenario_decode_paper_mario_semantic_state \
    "$BUNDLE_DIR" \
    "$BUNDLE_DIR/traces/paper-mario-game-status.json"
fi

scenario_extract_hires_log_evidence \
  "$BUNDLE_DIR" \
  "$BUNDLE_DIR/traces/hires-evidence.json"

scenario_verify_paper_mario_fixture \
  "$BUNDLE_DIR" \
  "$BUNDLE_DIR/traces/fixture-verification.json" \
  "$FIXTURE_ID" \
  "$VERIFY_SCREENSHOT_SHA256" \
  "${EXPECTED_INIT_SYMBOL:-}" \
  "${EXPECTED_STEP_SYMBOL:-}"

python3 "$REPO_ROOT/tools/hires_block_family_probe.py" analyze \
  --plan "$PLAN_JSON" \
  --snapshot-trace "$BUNDLE_DIR/traces/paper-mario-block-family-span.core-memory.txt" \
  --cache "$PACK_PATH" \
  --output-json "$REPORT_JSON" \
  --output-markdown "$REPORT_MD"

echo "[scenario] block-family probe complete: $REPORT_MD"
