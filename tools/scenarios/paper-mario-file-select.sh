#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$REPO_ROOT/tools/fixtures/paper-mario-file-select.yaml"
FIXTURE_ID="paper-mario-file-select"
MODE="off"
DRY_RUN=1
BUNDLE_DIR=""
RUNTIME_ENV="$SCRIPT_DIR/paper-mario-file-select.runtime.env"

usage() {
  cat <<'EOF'
Usage:
  tools/scenarios/paper-mario-file-select.sh [options]

Options:
  --mode off|on       Evidence bundle mode label (default: off)
  --bundle-dir PATH   Output bundle directory
  --run               Reserve bundle and continue toward runtime execution
  -h, --help          Show this help
EOF
}

sha256_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "missing"
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    shasum -a 256 "$path" | awk '{print $1}'
  fi
}

json_bool() {
  if [[ "$1" == "1" ]]; then
    echo "true"
  else
    echo "false"
  fi
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
  timestamp="$(date +"%Y%m%d-%H%M%S")"
  BUNDLE_DIR="$REPO_ROOT/artifacts/$FIXTURE_ID/$MODE/$timestamp"
fi

ROM_PATH="$REPO_ROOT/assets/Paper Mario (USA).zip"
PACK_PATH="$REPO_ROOT/assets/PAPER MARIO_HIRESTEXTURES.hts"
RETROARCH_PATH="/home/auro/code/RetroArch"
AUTHORITATIVE_STATE_PATH=""
AUTHORITATIVE_STATE_PRESENT=0

mkdir -p "$BUNDLE_DIR"/captures "$BUNDLE_DIR"/logs "$BUNDLE_DIR"/traces

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
    "rom_sha256": "$(sha256_file "$ROM_PATH")",
    "hires_pack_path": "$PACK_PATH",
    "hires_pack_sha256": "$(sha256_file "$PACK_PATH")",
    "retroarch_path": "$RETROARCH_PATH"
  },
  "fixture_authority": {
    "authoritative_state_path": "",
    "authoritative_state_present": false,
    "post_load_settle_frames": 0
  },
  "controller_script": {
    "start_mask": "",
    "start_hold_frames": 0,
    "post_input_settle_frames": 0
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
AUTHORITATIVE_STATE_PATH=
AUTHORITATIVE_STATE_PRESENT=0
POST_LOAD_SETTLE_FRAMES=0
FILE_SELECT_START_MASK=
FILE_SELECT_START_HOLD_FRAMES=0
POST_INPUT_SETTLE_FRAMES=0
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

This bundle is a Phase 0 scripted-controller fixture.
Populate \`captures/\`, \`logs/\`, and \`traces/\` through the tracked scenario and adapter flow.
EOF

echo "[scenario] fixture: $FIXTURE_ID"
echo "[scenario] mode: $MODE"
echo "[scenario] bundle: $BUNDLE_DIR"
echo "[scenario] manifest: $MANIFEST"
echo "[scenario] internal scale: 4x"
echo "[scenario] execution: serial"

if (( DRY_RUN )); then
  echo "[scenario] dry-run complete; runtime launch is intentionally deferred."
else
  # shellcheck disable=SC1090
  source "$RUNTIME_ENV"

  if [[ -n "${AUTHORITATIVE_STATE_PATH:-}" && -f "${AUTHORITATIVE_STATE_PATH:-}" ]]; then
    AUTHORITATIVE_STATE_PRESENT=1
    mkdir -p "$BUNDLE_DIR/states/ParaLLEl N64"
    cp "$AUTHORITATIVE_STATE_PATH" "$BUNDLE_DIR/states/ParaLLEl N64/Paper Mario (USA).state"
  fi

  perl -0pi -e 's|"authoritative_state_path": ""|"authoritative_state_path": "'"${AUTHORITATIVE_STATE_PATH:-}"'"|g; s|"authoritative_state_present": false|"authoritative_state_present": '"$(json_bool "$AUTHORITATIVE_STATE_PRESENT")"'|g; s|"post_load_settle_frames": 0|"post_load_settle_frames": '"${POST_LOAD_SETTLE_FRAMES:-0}"'|g; s|"start_mask": ""|"start_mask": "'"${FILE_SELECT_START_MASK:-}"'"|g; s|"start_hold_frames": 0|"start_hold_frames": '"${FILE_SELECT_START_HOLD_FRAMES:-0}"'|g; s|"post_input_settle_frames": 0|"post_input_settle_frames": '"${POST_INPUT_SETTLE_FRAMES:-0}"'|g' "$BUNDLE_DIR/bundle.json"
  perl -0pi -e 's|AUTHORITATIVE_STATE_PATH=|AUTHORITATIVE_STATE_PATH='"${AUTHORITATIVE_STATE_PATH:-}"'|g; s|AUTHORITATIVE_STATE_PRESENT=0|AUTHORITATIVE_STATE_PRESENT='"$AUTHORITATIVE_STATE_PRESENT"'|g; s|POST_LOAD_SETTLE_FRAMES=0|POST_LOAD_SETTLE_FRAMES='"${POST_LOAD_SETTLE_FRAMES:-0}"'|g; s|FILE_SELECT_START_MASK=|FILE_SELECT_START_MASK='"${FILE_SELECT_START_MASK:-}"'|g; s|FILE_SELECT_START_HOLD_FRAMES=0|FILE_SELECT_START_HOLD_FRAMES='"${FILE_SELECT_START_HOLD_FRAMES:-0}"'|g; s|POST_INPUT_SETTLE_FRAMES=0|POST_INPUT_SETTLE_FRAMES='"${POST_INPUT_SETTLE_FRAMES:-0}"'|g' "$BUNDLE_DIR/config.env"

  if (( ! AUTHORITATIVE_STATE_PRESENT )); then
    echo "[scenario] authoritative title-screen state is required for the file-select fixture." >&2
    exit 1
  fi

  post_load_target=$(( POST_LOAD_SETTLE_FRAMES ))
  post_input_target=$(( POST_LOAD_SETTLE_FRAMES + FILE_SELECT_START_HOLD_FRAMES ))
  final_target=$(( post_input_target + POST_INPUT_SETTLE_FRAMES ))

  "$REPO_ROOT/tools/adapters/retroarch_stdin_session.sh" \
    --bundle-dir "$BUNDLE_DIR" \
    --mode "$MODE" \
    --retroarch-bin "$RETROARCH_BIN" \
    --base-config "$RETROARCH_BASE_CONFIG" \
    --core "$CORE_PATH" \
    --rom "$ROM_PATH" \
    --startup-wait "$STARTUP_WAIT" \
    --command "WAIT_LOG 120 ${STARTUP_READY_PATTERN:-EmuThread: M64CMD_EXECUTE.}" \
    --command "LOAD_STATE_SLOT_PAUSED 0" \
    --command "STEP_FRAME ${POST_LOAD_SETTLE_FRAMES}" \
    --command "WAIT_STATUS_FRAME PAUSED ${post_load_target} 10" \
    --command "SET_INPUT_PORT 0 ${FILE_SELECT_START_MASK}" \
    --command "STEP_FRAME ${FILE_SELECT_START_HOLD_FRAMES}" \
    --command "WAIT_STATUS_FRAME PAUSED ${post_input_target} 10" \
    --command "CLEAR_INPUT_PORT 0" \
    --command "STEP_FRAME ${POST_INPUT_SETTLE_FRAMES}" \
    --command "WAIT_STATUS_FRAME PAUSED ${final_target} 10" \
    --command "SCREENSHOT" \
    --command "WAIT_NEW_CAPTURE 10" \
    --command "QUIT"
fi
