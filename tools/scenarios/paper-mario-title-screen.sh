#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
MANIFEST="$REPO_ROOT/tools/fixtures/paper-mario-title-screen.yaml"
FIXTURE_ID="paper-mario-title-screen"
MODE="off"
AUTHORITY_MODE="auto"
DRY_RUN=1
BUNDLE_DIR=""
RUNTIME_ENV="$SCRIPT_DIR/paper-mario-title-screen.runtime.env"

usage() {
  cat <<'EOF'
Usage:
  tools/scenarios/paper-mario-title-screen.sh [options]

Options:
  --mode off|on       Evidence bundle mode label (default: off)
  --authority-mode auto|authoritative
                      State selection mode (default: auto)
  --bundle-dir PATH   Output bundle directory
  --run               Reserve bundle and continue toward runtime execution
  -h, --help          Show this help

Notes:
  - This scenario is Phase 0 scaffolding for the first strict Paper Mario fixture.
  - Emulator-facing runs are expected at 4x internal scale and one at a time.
  - The current script prepares a reproducible evidence bundle and environment summary.
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
      if [[ "$AUTHORITY_MODE" != "auto" && "$AUTHORITY_MODE" != "authoritative" ]]; then
        echo "--authority-mode must be 'auto' or 'authoritative'." >&2
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
AUTHORITY_NODE_ID="title_screen_idle"
BOOTSTRAP_PARENT_FIXTURE_ID=""
REMINT_SCRIPT=""
AUTHORITATIVE_STATE_PATH=""
AUTHORITATIVE_STATE_PRESENT=0
AUTHORITATIVE_STATE_SHA256="missing"
AUTHORITY_MODE_USED="none"
GAME_STATUS_TRACE_REL="traces/paper-mario-game-status.core-memory.txt"
GAME_STATUS_JSON_REL="traces/paper-mario-game-status.json"

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
    "retroarch_path": "$RETROARCH_PATH"
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
    "active_state_path": "",
    "active_state_sha256": "missing",
    "post_load_settle_frames": 0
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
AUTHORITY_MODE_REQUESTED=$AUTHORITY_MODE
AUTHORITY_MODE_USED=none
AUTHORITY_GRAPH_PATH=$AUTHORITY_GRAPH_PATH
AUTHORITY_NODE_ID=$AUTHORITY_NODE_ID
BOOTSTRAP_PARENT_FIXTURE_ID=
REMINT_SCRIPT=
AUTHORITATIVE_STATE_PATH=
AUTHORITATIVE_STATE_PRESENT=0
AUTHORITATIVE_STATE_SHA256=missing
ACTIVE_STATE_PATH=
ACTIVE_STATE_SHA256=missing
POST_LOAD_SETTLE_FRAMES=0
INTERNAL_SCALE=4x
SERIAL_EXECUTION=1
DISPLAY_REQUIRED=1
EOF

cat > "$BUNDLE_DIR/README.md" <<EOF
# $FIXTURE_ID

- Mode: \`$MODE\`
- Manifest: [paper-mario-title-screen.yaml]($MANIFEST)
- Internal scale: \`4x\`
- Execution rule: one emulator-facing run at a time
- Status: bundle initialized

This bundle is a Phase 0 scaffold.
Populate \`captures/\`, \`logs/\`, and \`traces/\` through the tracked scenario and adapter flow.
EOF

scenario_print_header "$FIXTURE_ID" "$MODE" "$BUNDLE_DIR" "$MANIFEST"

if (( DRY_RUN )); then
  echo "[scenario] dry-run complete; runtime launch is intentionally deferred."
else
  # shellcheck disable=SC1090
  source "$RUNTIME_ENV"

  if [[ -n "${AUTHORITATIVE_STATE_PATH:-}" && -f "${AUTHORITATIVE_STATE_PATH:-}" ]]; then
    AUTHORITATIVE_STATE_PRESENT=1
    AUTHORITATIVE_STATE_SHA256="$(scenario_sha256_file "$AUTHORITATIVE_STATE_PATH")"
    mkdir -p "$BUNDLE_DIR/states/ParaLLEl N64"
    cp "$AUTHORITATIVE_STATE_PATH" "$BUNDLE_DIR/states/ParaLLEl N64/Paper Mario (USA).state"
    AUTHORITY_MODE_USED="authoritative"
  fi

  if [[ "$AUTHORITY_MODE" == "authoritative" && "$AUTHORITATIVE_STATE_PRESENT" != "1" ]]; then
    echo "[scenario] authoritative title-screen state is required." >&2
    exit 1
  fi

  scenario_patch_file "$BUNDLE_DIR/bundle.json" 's|"authority_mode_used": "none"|"authority_mode_used": "'"${AUTHORITY_MODE_USED:-none}"'"|g; s|"bootstrap_parent_fixture_id": ""|"bootstrap_parent_fixture_id": "'"${BOOTSTRAP_PARENT_FIXTURE_ID:-}"'"|g; s|"remint_script": ""|"remint_script": "'"${REMINT_SCRIPT:-}"'"|g; s|"authoritative_state_path": ""|"authoritative_state_path": "'"${AUTHORITATIVE_STATE_PATH:-}"'"|g; s|"authoritative_state_present": false|"authoritative_state_present": '"$(scenario_json_bool "$AUTHORITATIVE_STATE_PRESENT")"'|g; s|"authoritative_state_sha256": "missing"|"authoritative_state_sha256": "'"${AUTHORITATIVE_STATE_SHA256:-missing}"'"|g; s|"active_state_path": ""|"active_state_path": "'"${AUTHORITATIVE_STATE_PATH:-}"'"|g; s|"active_state_sha256": "missing"|"active_state_sha256": "'"${AUTHORITATIVE_STATE_SHA256:-missing}"'"|g; s|"post_load_settle_frames": 0|"post_load_settle_frames": '"${POST_LOAD_SETTLE_FRAMES:-0}"'|g'
  scenario_patch_file "$BUNDLE_DIR/config.env" 's|AUTHORITY_MODE_USED=none|AUTHORITY_MODE_USED='"${AUTHORITY_MODE_USED:-none}"'|g; s|BOOTSTRAP_PARENT_FIXTURE_ID=|BOOTSTRAP_PARENT_FIXTURE_ID='"${BOOTSTRAP_PARENT_FIXTURE_ID:-}"'|g; s|REMINT_SCRIPT=|REMINT_SCRIPT='"${REMINT_SCRIPT:-}"'|g; s|AUTHORITATIVE_STATE_PATH=|AUTHORITATIVE_STATE_PATH='"${AUTHORITATIVE_STATE_PATH:-}"'|g; s|AUTHORITATIVE_STATE_PRESENT=0|AUTHORITATIVE_STATE_PRESENT='"$AUTHORITATIVE_STATE_PRESENT"'|g; s|AUTHORITATIVE_STATE_SHA256=missing|AUTHORITATIVE_STATE_SHA256='"${AUTHORITATIVE_STATE_SHA256:-missing}"'|g; s|ACTIVE_STATE_PATH=|ACTIVE_STATE_PATH='"${AUTHORITATIVE_STATE_PATH:-}"'|g; s|ACTIVE_STATE_SHA256=missing|ACTIVE_STATE_SHA256='"${AUTHORITATIVE_STATE_SHA256:-missing}"'|g; s|POST_LOAD_SETTLE_FRAMES=0|POST_LOAD_SETTLE_FRAMES='"${POST_LOAD_SETTLE_FRAMES:-0}"'|g'

  declare -a runtime_commands
  runtime_commands=(
    --command "WAIT_LOG 120 ${STARTUP_READY_PATTERN:-EmuThread: M64CMD_EXECUTE.}"
  )

  if (( AUTHORITATIVE_STATE_PRESENT )); then
    runtime_commands+=(
      --command "LOAD_STATE_SLOT_PAUSED 0"
      --command "STEP_FRAME ${POST_LOAD_SETTLE_FRAMES:-3}"
      --command "WAIT_STATUS_FRAME PAUSED ${POST_LOAD_SETTLE_FRAMES:-3} 10"
      --command "SNAPSHOT_CORE_MEMORY paper-mario-game-status 800740aa 40"
      --command "SCREENSHOT"
      --command "WAIT_NEW_CAPTURE 10"
      --command "QUIT"
    )
  else
    runtime_commands+=(
      --command "SET_PAUSE ON"
      --command "WAIT_STATUS PAUSED 5"
      --command "SAVE_STATE"
      --command "SCREENSHOT"
      --command "WAIT_NEW_CAPTURE 10"
      --command "QUIT"
    )
  fi

  "$REPO_ROOT/tools/adapters/retroarch_stdin_session.sh" \
    --bundle-dir "$BUNDLE_DIR" \
    --mode "$MODE" \
    --retroarch-bin "$RETROARCH_BIN" \
    --base-config "$RETROARCH_BASE_CONFIG" \
    --core "$CORE_PATH" \
    --rom "$ROM_PATH" \
    --startup-wait "$STARTUP_WAIT" \
    "${runtime_commands[@]}"

  if [[ -f "$BUNDLE_DIR/$GAME_STATUS_TRACE_REL" ]]; then
    scenario_decode_paper_mario_game_status_snapshot \
      "$BUNDLE_DIR/$GAME_STATUS_TRACE_REL" \
      "$BUNDLE_DIR/$GAME_STATUS_JSON_REL"
  fi
fi
