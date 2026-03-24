#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

FIXTURE_ID="paper-mario-file-select-input-probe"
MODE="on"
DRY_RUN=1
BUNDLE_DIR=""
RUNTIME_ENV="${RUNTIME_ENV_OVERRIDE:-$SCRIPT_DIR/paper-mario-file-select.runtime.env}"
PROBE_LABEL="probe"
INPUT_MASK=""
INPUT_HOLD_FRAMES="1"
INPUT_REPEAT_COUNT="1"
INTER_PULSE_SETTLE_FRAMES="5"
POST_INPUT_SETTLE_FRAMES="20"
STEP_CHUNK_FRAMES="1"
INPUT_SEQUENCE=""

usage() {
  cat <<'EOF'
Usage:
  tools/scenarios/paper-mario-file-select-input-probe.sh [options]

Options:
  --mode off|on              Evidence bundle mode label (default: on)
  --input-mask HEX           Required controller mask (example: 0x20)
  --input-hold-frames N      Frames to hold the input (default: 1)
  --input-repeat-count N     Number of input pulses to send (default: 1)
  --inter-pulse-settle N     Frames to settle between repeated pulses (default: 5)
  --input-sequence SPEC      Comma-separated pulse sequence overriding repeat mode.
                             Item format: MASK[:HOLD[:SETTLE_AFTER]]
                             Example: 0x20:1:5,0x01:1:20
  --post-input-settle N      Frames to settle after release (default: 20)
  --step-chunk-frames N      Maximum frames per STEP_FRAME command (default: 1)
  --probe-label LABEL        Short label for bundle metadata
  --bundle-dir PATH          Output bundle directory
  --run                      Execute the runtime path
  -h, --help                 Show this help
EOF
}

while (($#)); do
  case "$1" in
    --mode)
      shift
      MODE="${1:-}"
      ;;
    --input-mask)
      shift
      INPUT_MASK="${1:-}"
      ;;
    --input-hold-frames)
      shift
      INPUT_HOLD_FRAMES="${1:-}"
      ;;
    --input-repeat-count)
      shift
      INPUT_REPEAT_COUNT="${1:-}"
      ;;
    --inter-pulse-settle)
      shift
      INTER_PULSE_SETTLE_FRAMES="${1:-}"
      ;;
    --input-sequence)
      shift
      INPUT_SEQUENCE="${1:-}"
      ;;
    --post-input-settle)
      shift
      POST_INPUT_SETTLE_FRAMES="${1:-}"
      ;;
    --step-chunk-frames)
      shift
      STEP_CHUNK_FRAMES="${1:-}"
      ;;
    --probe-label)
      shift
      PROBE_LABEL="${1:-}"
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

if [[ -z "$INPUT_MASK" && -z "$INPUT_SEQUENCE" ]]; then
  echo "--input-mask or --input-sequence is required." >&2
  exit 2
fi

if [[ -z "$BUNDLE_DIR" ]]; then
  BUNDLE_DIR="$(scenario_default_bundle_dir "$REPO_ROOT" "$FIXTURE_ID" "$MODE")"
fi

ROM_PATH="$REPO_ROOT/assets/Paper Mario (USA).zip"
PACK_PATH="$REPO_ROOT/assets/PAPER MARIO_HIRESTEXTURES.hts"
RETROARCH_PATH="/home/auro/code/RetroArch"
MANIFEST="$REPO_ROOT/tools/fixtures/paper-mario-file-select.yaml"
PAPER_MARIO_SEMANTIC_JSON_REL="traces/paper-mario-game-status.json"
SAVEFILE_PATH=""
SAVEFILE_PRESENT=0
SAVEFILE_SHA256="missing"

scenario_prepare_bundle_dirs "$BUNDLE_DIR"

cat > "$BUNDLE_DIR/bundle.json" <<EOF
{
  "fixture_id": "$FIXTURE_ID",
  "mode": "$MODE",
  "bundle_dir": "$BUNDLE_DIR",
  "created_at": "$(date -Iseconds)",
  "runtime_rules": {
    "internal_scale": "4x",
    "serial_execution": true,
    "display_required": true
  },
  "probe": {
    "label": "$PROBE_LABEL",
    "input_mask": "$INPUT_MASK",
    "input_hold_frames": $INPUT_HOLD_FRAMES,
    "input_repeat_count": $INPUT_REPEAT_COUNT,
    "inter_pulse_settle_frames": $INTER_PULSE_SETTLE_FRAMES,
    "input_sequence": "$INPUT_SEQUENCE",
    "post_input_settle_frames": $POST_INPUT_SETTLE_FRAMES,
    "step_chunk_frames": $STEP_CHUNK_FRAMES
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
  "status": {
    "phase": "phase-1",
    "scenario_state": "bundle_initialized",
    "runtime_executed": false
  }
}
EOF

cat > "$BUNDLE_DIR/config.env" <<EOF
FIXTURE_ID=$FIXTURE_ID
MODE=$MODE
PROBE_LABEL=$PROBE_LABEL
INPUT_MASK=$INPUT_MASK
INPUT_HOLD_FRAMES=$INPUT_HOLD_FRAMES
INPUT_REPEAT_COUNT=$INPUT_REPEAT_COUNT
INTER_PULSE_SETTLE_FRAMES=$INTER_PULSE_SETTLE_FRAMES
INPUT_SEQUENCE=$INPUT_SEQUENCE
POST_INPUT_SETTLE_FRAMES=$POST_INPUT_SETTLE_FRAMES
STEP_CHUNK_FRAMES=$STEP_CHUNK_FRAMES
ROM_PATH=$ROM_PATH
HIRES_PACK_PATH=$PACK_PATH
RETROARCH_PATH=$RETROARCH_PATH
SAVEFILE_PATH=
SAVEFILE_PRESENT=0
SAVEFILE_SHA256=missing
EOF

scenario_print_header "$FIXTURE_ID" "$MODE" "$BUNDLE_DIR" "$MANIFEST"

if (( DRY_RUN )); then
  echo "[scenario] dry-run complete; runtime launch is intentionally deferred."
  exit 0
fi

scenario_source_runtime_env "$RUNTIME_ENV"

if [[ -z "${AUTHORITATIVE_STATE_PATH:-}" || ! -f "${AUTHORITATIVE_STATE_PATH:-}" ]]; then
  echo "[scenario] authoritative file-select state is required." >&2
  exit 1
fi

if [[ -n "${SAVEFILE_PATH:-}" && -f "${SAVEFILE_PATH:-}" ]]; then
  SAVEFILE_PATH="${SAVEFILE_PATH:-}"
  SAVEFILE_PRESENT=1
  SAVEFILE_SHA256="$(scenario_sha256_file "$SAVEFILE_PATH")"
  scenario_stage_optional_savefile "$SAVEFILE_PATH" "$BUNDLE_DIR" "Paper Mario (USA)"
fi

mkdir -p "$BUNDLE_DIR/states/ParaLLEl N64"
cp "$AUTHORITATIVE_STATE_PATH" "$BUNDLE_DIR/states/ParaLLEl N64/Paper Mario (USA).state"

scenario_patch_file "$BUNDLE_DIR/bundle.json" 's|"scenario_state": "bundle_initialized"|"scenario_state": "runtime_prepared"|g'
scenario_patch_file "$BUNDLE_DIR/bundle.json" 's|"runtime_executed": false|"runtime_executed": true|g'
scenario_patch_file "$BUNDLE_DIR/bundle.json" 's|"savefile_path": ""|"savefile_path": "'"${SAVEFILE_PATH:-}"'"|g; s|"savefile_present": false|"savefile_present": '"$(scenario_json_bool "$SAVEFILE_PRESENT")"'|g; s|"savefile_sha256": "missing"|"savefile_sha256": "'"${SAVEFILE_SHA256:-missing}"'"|g'
scenario_patch_file "$BUNDLE_DIR/config.env" 's|SAVEFILE_PATH=|SAVEFILE_PATH='"${SAVEFILE_PATH:-}"'|g; s|SAVEFILE_PRESENT=0|SAVEFILE_PRESENT='"$SAVEFILE_PRESENT"'|g; s|SAVEFILE_SHA256=missing|SAVEFILE_SHA256='"${SAVEFILE_SHA256:-missing}"'|g'

declare -a ADAPTER_ARGS=(
  --bundle-dir "$BUNDLE_DIR"
  --mode "$MODE"
  --retroarch-bin "$RETROARCH_BIN"
  --base-config "$RETROARCH_BASE_CONFIG"
  --core "$CORE_PATH"
  --rom "$ROM_PATH"
  --startup-wait "$STARTUP_WAIT"
  --command "WAIT_COMMAND_READY 120"
  --command "LOAD_STATE_SLOT_PAUSED 0"
  --command "STEP_FRAME ${POST_LOAD_SETTLE_FRAMES}"
  --command "WAIT_STATUS_FRAME PAUSED ${POST_LOAD_SETTLE_FRAMES} 10"
)

frame_cursor="$POST_LOAD_SETTLE_FRAMES"

append_chunked_step_commands() {
  local frame_count="$1"
  local timeout_seconds="$2"
  local remaining="$frame_count"
  local chunk=""
  while (( remaining > 0 )); do
    if (( remaining > STEP_CHUNK_FRAMES )); then
      chunk="$STEP_CHUNK_FRAMES"
    else
      chunk="$remaining"
    fi
    frame_cursor=$(( frame_cursor + chunk ))
    ADAPTER_ARGS+=(--command "STEP_FRAME ${chunk}")
    ADAPTER_ARGS+=(--command "WAIT_STATUS_FRAME PAUSED ${frame_cursor} ${timeout_seconds}")
    remaining=$(( remaining - chunk ))
  done
}

append_input_pulse() {
  local pulse_mask="$1"
  local hold_frames="$2"
  local settle_frames="$3"
  ADAPTER_ARGS+=(--command "SET_INPUT_PORT 0 ${pulse_mask}")
  append_chunked_step_commands "$hold_frames" 10
  ADAPTER_ARGS+=(--command "CLEAR_INPUT_PORT 0")
  append_chunked_step_commands "$settle_frames" 10
}

if [[ -n "$INPUT_SEQUENCE" ]]; then
  IFS=',' read -r -a sequence_items <<< "$INPUT_SEQUENCE"
  sequence_count="${#sequence_items[@]}"
  sequence_index="0"
  while (( sequence_index < sequence_count )); do
    sequence_item="${sequence_items[$sequence_index]}"
    IFS=':' read -r seq_mask seq_hold seq_settle <<< "$sequence_item"
    if [[ -z "${seq_mask:-}" ]]; then
      echo "[scenario] invalid --input-sequence item: $sequence_item" >&2
      exit 2
    fi
    if [[ -z "${seq_hold:-}" ]]; then
      seq_hold="$INPUT_HOLD_FRAMES"
    fi
    if [[ -z "${seq_settle:-}" ]]; then
      if (( sequence_index + 1 < sequence_count )); then
        seq_settle="$INTER_PULSE_SETTLE_FRAMES"
      else
        seq_settle="$POST_INPUT_SETTLE_FRAMES"
      fi
    fi
    append_input_pulse "$seq_mask" "$seq_hold" "$seq_settle"
    sequence_index=$(( sequence_index + 1 ))
  done
else
  repeat_index="1"
  while (( repeat_index <= INPUT_REPEAT_COUNT )); do
    if (( repeat_index < INPUT_REPEAT_COUNT )); then
      settle_frames="$INTER_PULSE_SETTLE_FRAMES"
    else
      settle_frames="$POST_INPUT_SETTLE_FRAMES"
    fi
    append_input_pulse "$INPUT_MASK" "$INPUT_HOLD_FRAMES" "$settle_frames"
    repeat_index=$(( repeat_index + 1 ))
  done
fi

ADAPTER_ARGS+=(
  --command "SNAPSHOT_CORE_MEMORY paper-mario-gamestatus 800740aa 230"
  --command "SNAPSHOT_CORE_MEMORY paper-mario-curgamemode 80151700 20"
  --command "SNAPSHOT_CORE_MEMORY paper-mario-transition 800a0944 8"
  --command "SCREENSHOT"
  --command "WAIT_NEW_CAPTURE 10"
  --command "QUIT"
)

PARALLEL_N64_GFX_PLUGIN_OVERRIDE="parallel" \
PARALLEL_RDP_HIRES_CACHE_PATH="$PACK_PATH" \
PARALLEL_RDP_HIRES_DEBUG="$([[ "$MODE" == "on" ]] && echo 1 || echo 0)" \
PARALLEL_RDP_HIRES_CI_PALETTE_PROBE="1" \
"$REPO_ROOT/tools/adapters/retroarch_stdin_session.sh" \
  "${ADAPTER_ARGS[@]}"

if [[ -f "$BUNDLE_DIR/traces/paper-mario-gamestatus.core-memory.txt" ]]; then
  scenario_decode_paper_mario_semantic_state \
    "$BUNDLE_DIR" \
    "$BUNDLE_DIR/$PAPER_MARIO_SEMANTIC_JSON_REL"
fi

scenario_extract_hires_log_evidence \
  "$BUNDLE_DIR" \
  "$BUNDLE_DIR/traces/hires-evidence.json"

echo "[scenario] probe complete: label=$PROBE_LABEL input_mask=$INPUT_MASK"
