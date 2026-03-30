#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

FIXTURE_ID="paper-mario-title-timeout-probe"
MODE="off"
DRY_RUN=1
BUNDLE_DIR=""
RUNTIME_ENV="${RUNTIME_ENV_OVERRIDE:-$SCRIPT_DIR/paper-mario-title-screen.runtime.env}"
PROBE_LABEL="title-timeout-probe"
STEP_FRAMES=""
STEP_CHUNK_FRAMES="30"

usage() {
  cat <<'EOF'
Usage:
  tools/scenarios/paper-mario-title-timeout-probe.sh [options]

Options:
  --mode off|on            Evidence bundle mode label (default: off)
  --step-frames N          Required frame count to advance after title authority load
  --step-chunk-frames N    Maximum frames per STEP_FRAME command (default: 30)
  --probe-label LABEL      Short label for bundle metadata
  --bundle-dir PATH        Output bundle directory
  --run                    Execute the runtime path
  -h, --help               Show this help
EOF
}

while (($#)); do
  case "$1" in
    --mode)
      shift
      MODE="${1:-}"
      ;;
    --step-frames)
      shift
      STEP_FRAMES="${1:-}"
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

if [[ -z "$STEP_FRAMES" ]]; then
  echo "--step-frames is required." >&2
  exit 2
fi

if [[ -z "$BUNDLE_DIR" ]]; then
  BUNDLE_DIR="$(scenario_default_bundle_dir "$REPO_ROOT" "$FIXTURE_ID" "$MODE")"
fi

ROM_PATH="$REPO_ROOT/assets/Paper Mario (USA).zip"
PACK_PATH="$REPO_ROOT/assets/PAPER MARIO_HIRESTEXTURES.hts"
RETROARCH_PATH="/home/auro/code/RetroArch"
MANIFEST="$REPO_ROOT/tools/fixtures/paper-mario-title-screen.yaml"
PAPER_MARIO_SEMANTIC_JSON_REL="traces/paper-mario-game-status.json"

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
    "step_frames": $STEP_FRAMES,
    "step_chunk_frames": $STEP_CHUNK_FRAMES,
    "authority_fixture_id": "paper-mario-title-screen"
  },
  "inputs": {
    "rom_path": "$ROM_PATH",
    "rom_sha256": "$(scenario_sha256_file "$ROM_PATH")",
    "hires_pack_path": "$PACK_PATH",
    "hires_pack_sha256": "$(scenario_sha256_file "$PACK_PATH")",
    "retroarch_path": "$RETROARCH_PATH"
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
STEP_FRAMES=$STEP_FRAMES
STEP_CHUNK_FRAMES=$STEP_CHUNK_FRAMES
ROM_PATH=$ROM_PATH
HIRES_PACK_PATH=$PACK_PATH
RETROARCH_PATH=$RETROARCH_PATH
EOF

scenario_print_header "$FIXTURE_ID" "$MODE" "$BUNDLE_DIR" "$MANIFEST"

if (( DRY_RUN )); then
  echo "[scenario] dry-run complete; runtime launch is intentionally deferred."
  exit 0
fi

scenario_source_runtime_env "$RUNTIME_ENV"

PACK_PATH="${PARALLEL_RDP_HIRES_CACHE_PATH:-$PACK_PATH}"
scenario_configure_hires_runtime_env_for_cache "$PACK_PATH"
PACK_SHA256="$(scenario_sha256_file "$PACK_PATH")"

scenario_patch_file "$BUNDLE_DIR/bundle.json" 's|"hires_pack_path": "[^"]*"|"hires_pack_path": "'"${PACK_PATH}"'"|g; s|"hires_pack_sha256": "[^"]*"|"hires_pack_sha256": "'"${PACK_SHA256}"'"|g'
scenario_patch_file "$BUNDLE_DIR/config.env" 's|HIRES_PACK_PATH=.*|HIRES_PACK_PATH='"${PACK_PATH}"'|g'

if [[ -z "${AUTHORITATIVE_STATE_PATH:-}" || ! -f "${AUTHORITATIVE_STATE_PATH:-}" ]]; then
  echo "[scenario] authoritative title-screen state is required." >&2
  exit 1
fi

mkdir -p "$BUNDLE_DIR/states/ParaLLEl N64"
cp "$AUTHORITATIVE_STATE_PATH" "$BUNDLE_DIR/states/ParaLLEl N64/Paper Mario (USA).state"

scenario_patch_file "$BUNDLE_DIR/bundle.json" 's|"scenario_state": "bundle_initialized"|"scenario_state": "runtime_prepared"|g'
scenario_patch_file "$BUNDLE_DIR/bundle.json" 's|"runtime_executed": false|"runtime_executed": true|g'

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

append_chunked_step_commands "$STEP_FRAMES" 90

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
"$REPO_ROOT/tools/adapters/retroarch_stdin_session.sh" \
  "${ADAPTER_ARGS[@]}"

scenario_decode_paper_mario_semantic_state \
  "$BUNDLE_DIR" \
  "$BUNDLE_DIR/$PAPER_MARIO_SEMANTIC_JSON_REL"

scenario_extract_hires_log_evidence \
  "$BUNDLE_DIR" \
  "$BUNDLE_DIR/traces/hires-evidence.json"

echo "[scenario] probe complete."
echo "[scenario] semantic trace: $BUNDLE_DIR/$PAPER_MARIO_SEMANTIC_JSON_REL"
