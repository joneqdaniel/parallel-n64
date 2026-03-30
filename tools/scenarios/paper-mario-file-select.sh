#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
MANIFEST="$REPO_ROOT/tools/fixtures/paper-mario-file-select.yaml"
FIXTURE_ID="paper-mario-file-select"
MODE="off"
AUTHORITY_MODE="auto"
DRY_RUN=1
BUNDLE_DIR=""
RUNTIME_ENV="${RUNTIME_ENV_OVERRIDE:-$SCRIPT_DIR/paper-mario-file-select.runtime.env}"

usage() {
  cat <<'EOF'
Usage:
  tools/scenarios/paper-mario-file-select.sh [options]

Options:
  --mode off|on       Evidence bundle mode label (default: off)
  --authority-mode auto|authoritative|bootstrap
                      State selection mode (default: auto)
  --bundle-dir PATH   Output bundle directory
  --run               Reserve bundle and continue toward runtime execution
  -h, --help          Show this help
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
    --authority-mode)
      shift
      AUTHORITY_MODE="${1:-}"
      if [[ "$AUTHORITY_MODE" != "auto" && "$AUTHORITY_MODE" != "authoritative" && "$AUTHORITY_MODE" != "bootstrap" ]]; then
        echo "--authority-mode must be 'auto', 'authoritative', or 'bootstrap'." >&2
        exit 2
      fi
      ;;
    --bundle-dir)
      shift
      BUNDLE_DIR="${1:-}"
      if [[ -z "$BUNDLE_DIR" ]]; then
        echo "--bundle-dir requires a value." >&2
        exit 2
      fi
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

ROM_PATH="$REPO_ROOT/assets/Paper Mario (USA).zip"
PACK_PATH="$REPO_ROOT/assets/PAPER MARIO_HIRESTEXTURES.hts"
RETROARCH_PATH="/home/auro/code/RetroArch"
AUTHORITY_GRAPH_PATH="$REPO_ROOT/tools/fixtures/paper-mario-authority-graph.yaml"
AUTHORITY_NODE_ID="file_select_idle"
BOOTSTRAP_PARENT_FIXTURE_ID="paper-mario-title-screen"
REMINT_SCRIPT="tools/scenarios/remint-paper-mario-file-select-authority.sh"
AUTHORITATIVE_STATE_PATH=""
AUTHORITATIVE_STATE_PRESENT=0
AUTHORITATIVE_STATE_SHA256="missing"
BOOTSTRAP_STATE_PATH=""
BOOTSTRAP_STATE_PRESENT=0
BOOTSTRAP_STATE_SHA256="missing"
AUTHORITY_MODE_USED="none"
ACTIVE_STATE_PATH=""
ACTIVE_STATE_SHA256="missing"
PAPER_MARIO_SEMANTIC_JSON_REL="traces/paper-mario-game-status.json"
SAVEFILE_PATH=""
SAVEFILE_PRESENT=0
SAVEFILE_SHA256="missing"
EXPECTED_SCREENSHOT_SHA256=""
EXPECTED_INIT_SYMBOL=""
EXPECTED_STEP_SYMBOL=""

scenario_prepare_bundle_dirs "$BUNDLE_DIR"

cat > "$BUNDLE_DIR/bundle.json" <<EOF
{
  "fixture_id": "$FIXTURE_ID",
  "mode": "$MODE",
  "manifest_path": "$MANIFEST",
  "bundle_dir": "$BUNDLE_DIR",
  "created_at": "$(date -Iseconds)",
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
    "retroarch_path": "$RETROARCH_PATH",
    "savefile_path": "",
    "savefile_present": false,
    "savefile_sha256": "missing"
  },
  "fixture_authority": {
    "authority_mode_requested": "$AUTHORITY_MODE",
    "authority_mode_used": "none",
    "authority_graph_path": "$AUTHORITY_GRAPH_PATH",
    "authority_node_id": "$AUTHORITY_NODE_ID",
    "bootstrap_parent_fixture_id": "$BOOTSTRAP_PARENT_FIXTURE_ID",
    "remint_script": "$REMINT_SCRIPT",
    "authoritative_state_path": "",
    "authoritative_state_present": false,
    "authoritative_state_sha256": "missing",
    "bootstrap_state_path": "",
    "bootstrap_state_present": false,
    "bootstrap_state_sha256": "missing",
    "active_state_path": "",
    "active_state_sha256": "missing",
    "post_load_settle_frames": 0
  },
  "controller_script": {
    "start_mask": "",
    "start_hold_frames": 0,
    "target_frame": 0
  },
  "status": {
    "phase": "phase-0",
    "scenario_state": "bundle_initialized",
    "runtime_executed": false
  }
}
EOF

cat > "$BUNDLE_DIR/config.env" <<EOF
FIXTURE_ID=$FIXTURE_ID
MODE=$MODE
MANIFEST_PATH=$MANIFEST
ROM_PATH=$ROM_PATH
HIRES_PACK_PATH=$PACK_PATH
RETROARCH_PATH=$RETROARCH_PATH
SAVEFILE_PATH=
SAVEFILE_PRESENT=0
SAVEFILE_SHA256=missing
AUTHORITY_MODE_REQUESTED=$AUTHORITY_MODE
AUTHORITY_MODE_USED=none
AUTHORITY_GRAPH_PATH=$AUTHORITY_GRAPH_PATH
AUTHORITY_NODE_ID=$AUTHORITY_NODE_ID
BOOTSTRAP_PARENT_FIXTURE_ID=$BOOTSTRAP_PARENT_FIXTURE_ID
REMINT_SCRIPT=$REMINT_SCRIPT
AUTHORITATIVE_STATE_PATH=
AUTHORITATIVE_STATE_PRESENT=0
AUTHORITATIVE_STATE_SHA256=missing
BOOTSTRAP_STATE_PATH=
BOOTSTRAP_STATE_PRESENT=0
BOOTSTRAP_STATE_SHA256=missing
ACTIVE_STATE_PATH=
ACTIVE_STATE_SHA256=missing
POST_LOAD_SETTLE_FRAMES=0
FILE_SELECT_START_MASK=
FILE_SELECT_START_HOLD_FRAMES=0
FILE_SELECT_TARGET_FRAME=0
INTERNAL_SCALE=4x
SERIAL_EXECUTION=1
DISPLAY_REQUIRED=1
EOF

cat > "$BUNDLE_DIR/README.md" <<EOF
# $FIXTURE_ID

- Mode: \`$MODE\`
- Manifest: [paper-mario-file-select.yaml]($MANIFEST)
- Internal scale: \`4x\`
- Execution rule: one emulator-facing run at a time
- Status: bundle initialized

This bundle is a Phase 0 file-select fixture.
Populate \`captures/\`, \`logs/\`, and \`traces/\` through the tracked scenario and adapter flow.
EOF

scenario_print_header "$FIXTURE_ID" "$MODE" "$BUNDLE_DIR" "$MANIFEST"

if (( DRY_RUN )); then
  echo "[scenario] dry-run complete; runtime launch is intentionally deferred."
else
  scenario_source_runtime_env "$RUNTIME_ENV"

  PACK_PATH="${PARALLEL_RDP_HIRES_CACHE_PATH:-$PACK_PATH}"
  scenario_configure_hires_runtime_env_for_cache "$PACK_PATH"
  PACK_SHA256="$(scenario_sha256_file "$PACK_PATH")"

  VERIFY_SCREENSHOT_SHA256=""
  if [[ "$MODE" == "off" ]]; then
    VERIFY_SCREENSHOT_SHA256="${EXPECTED_SCREENSHOT_SHA256_OFF:-${EXPECTED_SCREENSHOT_SHA256:-}}"
  elif [[ "$MODE" == "on" ]]; then
    VERIFY_SCREENSHOT_SHA256="${EXPECTED_SCREENSHOT_SHA256_ON:-}"
  fi
  if [[ "${DISABLE_SCREENSHOT_VERIFY:-0}" == "1" ]]; then
    VERIFY_SCREENSHOT_SHA256=""
  fi

  if [[ -n "${AUTHORITATIVE_STATE_PATH:-}" && -f "${AUTHORITATIVE_STATE_PATH:-}" ]]; then
    AUTHORITATIVE_STATE_PRESENT=1
    AUTHORITATIVE_STATE_SHA256="$(scenario_sha256_file "$AUTHORITATIVE_STATE_PATH")"
  fi
  if [[ -n "${BOOTSTRAP_STATE_PATH:-}" && -f "${BOOTSTRAP_STATE_PATH:-}" ]]; then
    BOOTSTRAP_STATE_PRESENT=1
    BOOTSTRAP_STATE_SHA256="$(scenario_sha256_file "$BOOTSTRAP_STATE_PATH")"
  fi
  if [[ -n "${SAVEFILE_PATH:-}" && -f "${SAVEFILE_PATH:-}" ]]; then
    SAVEFILE_PRESENT=1
    SAVEFILE_SHA256="$(scenario_sha256_file "$SAVEFILE_PATH")"
    scenario_stage_optional_savefile "$SAVEFILE_PATH" "$BUNDLE_DIR" "Paper Mario (USA)"
  fi

  case "$AUTHORITY_MODE" in
    authoritative)
      if (( ! AUTHORITATIVE_STATE_PRESENT )); then
        echo "[scenario] authoritative Paper Mario file-select state is required." >&2
        exit 1
      fi
      AUTHORITY_MODE_USED="authoritative"
      ACTIVE_STATE_PATH="$AUTHORITATIVE_STATE_PATH"
      ACTIVE_STATE_SHA256="$AUTHORITATIVE_STATE_SHA256"
      ;;
    bootstrap)
      if (( ! BOOTSTRAP_STATE_PRESENT )); then
        echo "[scenario] bootstrap Paper Mario title-screen state is required." >&2
        exit 1
      fi
      AUTHORITY_MODE_USED="bootstrap"
      ACTIVE_STATE_PATH="$BOOTSTRAP_STATE_PATH"
      ACTIVE_STATE_SHA256="$BOOTSTRAP_STATE_SHA256"
      ;;
    auto)
      if (( AUTHORITATIVE_STATE_PRESENT )); then
        AUTHORITY_MODE_USED="authoritative"
        ACTIVE_STATE_PATH="$AUTHORITATIVE_STATE_PATH"
        ACTIVE_STATE_SHA256="$AUTHORITATIVE_STATE_SHA256"
      elif (( BOOTSTRAP_STATE_PRESENT )); then
        AUTHORITY_MODE_USED="bootstrap"
        ACTIVE_STATE_PATH="$BOOTSTRAP_STATE_PATH"
        ACTIVE_STATE_SHA256="$BOOTSTRAP_STATE_SHA256"
      else
        echo "[scenario] authoritative or bootstrap Paper Mario state is required for the file-select fixture." >&2
        exit 1
      fi
      ;;
  esac

  mkdir -p "$BUNDLE_DIR/states/ParaLLEl N64"
  cp "$ACTIVE_STATE_PATH" "$BUNDLE_DIR/states/ParaLLEl N64/Paper Mario (USA).state"

  scenario_patch_file "$BUNDLE_DIR/bundle.json" 's|"hires_pack_path": "[^"]*"|"hires_pack_path": "'"${PACK_PATH}"'"|g; s|"hires_pack_sha256": "[^"]*"|"hires_pack_sha256": "'"${PACK_SHA256}"'"|g; s|"savefile_path": ""|"savefile_path": "'"${SAVEFILE_PATH:-}"'"|g; s|"savefile_present": false|"savefile_present": '"$(scenario_json_bool "$SAVEFILE_PRESENT")"'|g; s|"savefile_sha256": "missing"|"savefile_sha256": "'"${SAVEFILE_SHA256:-missing}"'"|g; s|"authority_mode_used": "none"|"authority_mode_used": "'"${AUTHORITY_MODE_USED:-none}"'"|g; s|"bootstrap_parent_fixture_id": "paper-mario-title-screen"|"bootstrap_parent_fixture_id": "'"${BOOTSTRAP_PARENT_FIXTURE_ID:-}"'"|g; s|"remint_script": "tools/scenarios/remint-paper-mario-file-select-authority.sh"|"remint_script": "'"${REMINT_SCRIPT:-}"'"|g; s|"authoritative_state_path": ""|"authoritative_state_path": "'"${AUTHORITATIVE_STATE_PATH:-}"'"|g; s|"authoritative_state_present": false|"authoritative_state_present": '"$(scenario_json_bool "$AUTHORITATIVE_STATE_PRESENT")"'|g; s|"authoritative_state_sha256": "missing"|"authoritative_state_sha256": "'"${AUTHORITATIVE_STATE_SHA256:-missing}"'"|g; s|"bootstrap_state_path": ""|"bootstrap_state_path": "'"${BOOTSTRAP_STATE_PATH:-}"'"|g; s|"bootstrap_state_present": false|"bootstrap_state_present": '"$(scenario_json_bool "$BOOTSTRAP_STATE_PRESENT")"'|g; s|"bootstrap_state_sha256": "missing"|"bootstrap_state_sha256": "'"${BOOTSTRAP_STATE_SHA256:-missing}"'"|g; s|"active_state_path": ""|"active_state_path": "'"${ACTIVE_STATE_PATH:-}"'"|g; s|"active_state_sha256": "missing"|"active_state_sha256": "'"${ACTIVE_STATE_SHA256:-missing}"'"|g; s|"post_load_settle_frames": 0|"post_load_settle_frames": '"${POST_LOAD_SETTLE_FRAMES:-0}"'|g; s|"start_mask": ""|"start_mask": "'"${FILE_SELECT_START_MASK:-}"'"|g; s|"start_hold_frames": 0|"start_hold_frames": '"${FILE_SELECT_START_HOLD_FRAMES:-0}"'|g; s|"target_frame": 0|"target_frame": '"${FILE_SELECT_TARGET_FRAME:-0}"'|g'
  scenario_patch_file "$BUNDLE_DIR/config.env" 's|HIRES_PACK_PATH=.*|HIRES_PACK_PATH='"${PACK_PATH}"'|g; s|SAVEFILE_PATH=|SAVEFILE_PATH='"${SAVEFILE_PATH:-}"'|g; s|SAVEFILE_PRESENT=0|SAVEFILE_PRESENT='"$SAVEFILE_PRESENT"'|g; s|SAVEFILE_SHA256=missing|SAVEFILE_SHA256='"${SAVEFILE_SHA256:-missing}"'|g; s|AUTHORITY_MODE_USED=none|AUTHORITY_MODE_USED='"${AUTHORITY_MODE_USED:-none}"'|g; s|BOOTSTRAP_PARENT_FIXTURE_ID=paper-mario-title-screen|BOOTSTRAP_PARENT_FIXTURE_ID='"${BOOTSTRAP_PARENT_FIXTURE_ID:-}"'|g; s|REMINT_SCRIPT=tools/scenarios/remint-paper-mario-file-select-authority.sh|REMINT_SCRIPT='"${REMINT_SCRIPT:-}"'|g; s|AUTHORITATIVE_STATE_PATH=|AUTHORITATIVE_STATE_PATH='"${AUTHORITATIVE_STATE_PATH:-}"'|g; s|AUTHORITATIVE_STATE_PRESENT=0|AUTHORITATIVE_STATE_PRESENT='"$AUTHORITATIVE_STATE_PRESENT"'|g; s|AUTHORITATIVE_STATE_SHA256=missing|AUTHORITATIVE_STATE_SHA256='"${AUTHORITATIVE_STATE_SHA256:-missing}"'|g; s|BOOTSTRAP_STATE_PATH=|BOOTSTRAP_STATE_PATH='"${BOOTSTRAP_STATE_PATH:-}"'|g; s|BOOTSTRAP_STATE_PRESENT=0|BOOTSTRAP_STATE_PRESENT='"$BOOTSTRAP_STATE_PRESENT"'|g; s|BOOTSTRAP_STATE_SHA256=missing|BOOTSTRAP_STATE_SHA256='"${BOOTSTRAP_STATE_SHA256:-missing}"'|g; s|ACTIVE_STATE_PATH=|ACTIVE_STATE_PATH='"${ACTIVE_STATE_PATH:-}"'|g; s|ACTIVE_STATE_SHA256=missing|ACTIVE_STATE_SHA256='"${ACTIVE_STATE_SHA256:-missing}"'|g; s|POST_LOAD_SETTLE_FRAMES=0|POST_LOAD_SETTLE_FRAMES='"${POST_LOAD_SETTLE_FRAMES:-0}"'|g; s|FILE_SELECT_START_MASK=|FILE_SELECT_START_MASK='"${FILE_SELECT_START_MASK:-}"'|g; s|FILE_SELECT_START_HOLD_FRAMES=0|FILE_SELECT_START_HOLD_FRAMES='"${FILE_SELECT_START_HOLD_FRAMES:-0}"'|g; s|FILE_SELECT_TARGET_FRAME=0|FILE_SELECT_TARGET_FRAME='"${FILE_SELECT_TARGET_FRAME:-0}"'|g'

  if [[ "$AUTHORITY_MODE_USED" == "authoritative" ]]; then
    PARALLEL_N64_GFX_PLUGIN_OVERRIDE="parallel" \
    PARALLEL_RDP_HIRES_CACHE_PATH="$PACK_PATH" \
    PARALLEL_RDP_HIRES_DEBUG="$([[ "$MODE" == "on" ]] && echo 1 || echo 0)" \
    PARALLEL_RDP_HIRES_BLOCK_SHAPE_PROBE="${PARALLEL_RDP_HIRES_BLOCK_SHAPE_PROBE:-}" \
    PARALLEL_RDP_HIRES_CI_PALETTE_PROBE="${PARALLEL_RDP_HIRES_CI_PALETTE_PROBE:-}" \
    PARALLEL_RDP_HIRES_FILTER_ALLOW_TILE="${PARALLEL_RDP_HIRES_FILTER_ALLOW_TILE:-${HIRES_FILTER_ALLOW_TILE:-}}" \
    PARALLEL_RDP_HIRES_FILTER_ALLOW_BLOCK="${PARALLEL_RDP_HIRES_FILTER_ALLOW_BLOCK:-${HIRES_FILTER_ALLOW_BLOCK:-}}" \
    PARALLEL_RDP_HIRES_FILTER_SIGNATURES="${PARALLEL_RDP_HIRES_FILTER_SIGNATURES:-${HIRES_FILTER_SIGNATURES:-}}" \
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
      --command "SNAPSHOT_CORE_MEMORY paper-mario-filemenu-pressed-buttons 8024c084 4" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-filemenu-held-buttons 8024c08c 4" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-save-slot-has-data 80077a24 4" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-window-files-title 8015a2f0 32" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-window-files-confirm-prompt 8015a310 32" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-window-files-message 8015a330 32" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-window-files-input-field 8015a350 32" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-window-files-input-keyboard 8015a370 32" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-window-files-confirm-options 8015a390 32" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-window-files-slot2-body 8015a470 32" \
      --command "SCREENSHOT" \
      --command "WAIT_NEW_CAPTURE 10" \
      --command "QUIT"
  else
    input_hold_target=$(( POST_LOAD_SETTLE_FRAMES + FILE_SELECT_START_HOLD_FRAMES ))
    remaining_frames=$(( FILE_SELECT_TARGET_FRAME - input_hold_target ))

    PARALLEL_N64_GFX_PLUGIN_OVERRIDE="parallel" \
    PARALLEL_RDP_HIRES_CACHE_PATH="$PACK_PATH" \
    PARALLEL_RDP_HIRES_DEBUG="$([[ "$MODE" == "on" ]] && echo 1 || echo 0)" \
    PARALLEL_RDP_HIRES_BLOCK_SHAPE_PROBE="${PARALLEL_RDP_HIRES_BLOCK_SHAPE_PROBE:-}" \
    PARALLEL_RDP_HIRES_CI_PALETTE_PROBE="${PARALLEL_RDP_HIRES_CI_PALETTE_PROBE:-}" \
    PARALLEL_RDP_HIRES_FILTER_ALLOW_TILE="${PARALLEL_RDP_HIRES_FILTER_ALLOW_TILE:-${HIRES_FILTER_ALLOW_TILE:-}}" \
    PARALLEL_RDP_HIRES_FILTER_ALLOW_BLOCK="${PARALLEL_RDP_HIRES_FILTER_ALLOW_BLOCK:-${HIRES_FILTER_ALLOW_BLOCK:-}}" \
    PARALLEL_RDP_HIRES_FILTER_SIGNATURES="${PARALLEL_RDP_HIRES_FILTER_SIGNATURES:-${HIRES_FILTER_SIGNATURES:-}}" \
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
      --command "SET_INPUT_PORT 0 ${FILE_SELECT_START_MASK}" \
      --command "STEP_FRAME ${FILE_SELECT_START_HOLD_FRAMES}" \
      --command "WAIT_STATUS_FRAME PAUSED ${input_hold_target} 10" \
      --command "CLEAR_INPUT_PORT 0" \
      --command "STEP_FRAME ${remaining_frames}" \
      --command "WAIT_STATUS_FRAME PAUSED ${FILE_SELECT_TARGET_FRAME} 10" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-gamestatus 800740aa 230" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-curgamemode 80151700 20" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-transition 800a0944 8" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-filemenu-current-menu 8024c098 1" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-filemenu-menus 80249b84 8" \
      --command "SNAPSHOT_CORE_POINTER_MEMORY paper-mario-filemenu-main-panel 80249b84 28" \
      --command "SNAPSHOT_CORE_POINTER_MEMORY paper-mario-filemenu-confirm-panel 80249b88 28" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-filemenu-pressed-buttons 8024c084 4" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-filemenu-held-buttons 8024c08c 4" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-save-slot-has-data 80077a24 4" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-window-files-title 8015a2f0 32" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-window-files-confirm-prompt 8015a310 32" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-window-files-message 8015a330 32" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-window-files-input-field 8015a350 32" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-window-files-input-keyboard 8015a370 32" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-window-files-confirm-options 8015a390 32" \
      --command "SNAPSHOT_CORE_MEMORY paper-mario-window-files-slot2-body 8015a470 32" \
      --command "SCREENSHOT" \
      --command "WAIT_NEW_CAPTURE 10" \
      --command "QUIT"
  fi

  if [[ -f "$BUNDLE_DIR/traces/paper-mario-gamestatus.core-memory.txt" ]]; then
    scenario_decode_paper_mario_semantic_state \
      "$BUNDLE_DIR" \
      "$BUNDLE_DIR/$PAPER_MARIO_SEMANTIC_JSON_REL"
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
fi
