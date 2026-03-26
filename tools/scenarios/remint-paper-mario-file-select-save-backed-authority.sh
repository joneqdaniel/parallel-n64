#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

RUNTIME_ENV="${RUNTIME_ENV_OVERRIDE:-$SCRIPT_DIR/paper-mario-file-select-save-backed.runtime.env}"
OUTPUT_PATH="$REPO_ROOT/assets/states/paper-mario-file-select-save-backed/ParaLLEl N64/Paper Mario (USA).state"
BUNDLE_ROOT=""

usage() {
  cat <<'EOF'
Usage:
  tools/scenarios/remint-paper-mario-file-select-save-backed-authority.sh [options]

Options:
  --output-path PATH  Write the reminted save-backed file-select state here
  --bundle-root PATH  Directory for bootstrap/verify evidence bundles
  -h, --help          Show this help

Notes:
  - This script intentionally avoids loading any existing savestate during bootstrap.
  - It stages the configured Paper Mario savefile, cold boots, waits to title, presses START,
    waits to file select, presses START again, waits to file select, saves there, and verifies
    the resulting state semantically.
EOF
}

while (($#)); do
  case "$1" in
    --output-path)
      shift
      OUTPUT_PATH="${1:-}"
      if [[ -z "$OUTPUT_PATH" ]]; then
        echo "--output-path requires a value." >&2
        exit 2
      fi
      ;;
    --bundle-root)
      shift
      BUNDLE_ROOT="${1:-}"
      if [[ -z "$BUNDLE_ROOT" ]]; then
        echo "--bundle-root requires a value." >&2
        exit 2
      fi
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

scenario_source_runtime_env "$RUNTIME_ENV"

if [[ -z "${SAVEFILE_PATH:-}" || ! -f "${SAVEFILE_PATH:-}" ]]; then
  echo "Savefile not found: ${SAVEFILE_PATH:-missing}" >&2
  exit 1
fi

if [[ -z "$BUNDLE_ROOT" ]]; then
  timestamp="$(date +"%Y%m%d-%H%M%S")"
  BUNDLE_ROOT="$REPO_ROOT/artifacts/paper-mario-file-select-save-backed/remint/$timestamp"
fi

BOOTSTRAP_BUNDLE="$BUNDLE_ROOT/bootstrap"
VERIFY_BUNDLE="$BUNDLE_ROOT/verify"
SAVEFILE_SHA256="$(scenario_sha256_file "$SAVEFILE_PATH")"

mkdir -p "$BOOTSTRAP_BUNDLE" "$VERIFY_BUNDLE"
scenario_stage_optional_savefile "$SAVEFILE_PATH" "$BOOTSTRAP_BUNDLE" "Paper Mario (USA)"
scenario_stage_optional_savefile "$SAVEFILE_PATH" "$VERIFY_BUNDLE" "Paper Mario (USA)"

echo "[remint] bootstrap bundle: $BOOTSTRAP_BUNDLE"
echo "[remint] verify bundle: $VERIFY_BUNDLE"
echo "[remint] output path: $OUTPUT_PATH"
echo "[remint] staged savefile: $SAVEFILE_PATH"
echo "[remint] staged savefile sha256: $SAVEFILE_SHA256"

PARALLEL_N64_GFX_PLUGIN_OVERRIDE="parallel" \
"$REPO_ROOT/tools/adapters/retroarch_stdin_session.sh" \
  --bundle-dir "$BOOTSTRAP_BUNDLE" \
  --mode off \
  --retroarch-bin "$RETROARCH_BIN" \
  --base-config "$RETROARCH_BASE_CONFIG" \
  --core "$CORE_PATH" \
  --rom "$ROM_PATH" \
  --startup-wait "$STARTUP_WAIT" \
  --command "WAIT_LOG 120 ${STARTUP_READY_PATTERN:-EmuThread: M64CMD_EXECUTE.}" \
  --command "WAIT ${TITLE_BOOT_WAIT_SECONDS}" \
  --command "SET_INPUT_PORT 0 ${TITLE_START_MASK}" \
  --command "WAIT 0.2" \
  --command "CLEAR_INPUT_PORT 0" \
  --command "WAIT ${TITLE_POST_PRESS_WAIT_SECONDS}" \
  --command "SET_INPUT_PORT 0 ${FILE_SELECT_START_MASK}" \
  --command "WAIT 0.2" \
  --command "CLEAR_INPUT_PORT 0" \
  --command "WAIT ${FILE_SELECT_POST_PRESS_WAIT_SECONDS:-5}" \
  --command "SAVE_STATE" \
  --command "WAIT_SAVE_STATE" \
  --command "QUIT"

mkdir -p "$(dirname -- "$OUTPUT_PATH")"
cp "$BOOTSTRAP_BUNDLE/states/ParaLLEl N64/Paper Mario (USA).state" "$OUTPUT_PATH"

mkdir -p "$VERIFY_BUNDLE/states/ParaLLEl N64"
cp "$OUTPUT_PATH" "$VERIFY_BUNDLE/states/ParaLLEl N64/Paper Mario (USA).state"

PARALLEL_N64_GFX_PLUGIN_OVERRIDE="parallel" \
"$REPO_ROOT/tools/adapters/retroarch_stdin_session.sh" \
  --bundle-dir "$VERIFY_BUNDLE" \
  --mode off \
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

if [[ -f "$VERIFY_BUNDLE/traces/paper-mario-gamestatus.core-memory.txt" ]]; then
  scenario_decode_paper_mario_semantic_state \
    "$VERIFY_BUNDLE" \
    "$VERIFY_BUNDLE/traces/paper-mario-game-status.json"
fi

VERIFY_CAPTURE="$(find "$VERIFY_BUNDLE/captures" -maxdepth 1 -type f | head -n1)"
if [[ -z "$VERIFY_CAPTURE" ]]; then
  echo "[remint] verification capture missing." >&2
  exit 1
fi

VERIFY_SEMANTIC="$VERIFY_BUNDLE/traces/paper-mario-game-status.json"
if [[ ! -f "$VERIFY_SEMANTIC" ]]; then
  echo "[remint] verification semantic JSON missing." >&2
  exit 1
fi

OUTPUT_SHA256="$(scenario_sha256_file "$OUTPUT_PATH")"
VERIFY_SHA256="$(scenario_sha256_file "$VERIFY_CAPTURE")"
SELECTED_SLOT_HAS_DATA="$(jq -r '.paper_mario_us.filemenu.selected_slot_has_data' "$VERIFY_SEMANTIC")"
CURRENT_MENU="$(jq -r '.paper_mario_us.filemenu.current_menu_name' "$VERIFY_SEMANTIC")"
INIT_SYMBOL="$(jq -r '.paper_mario_us.cur_game_mode.init_symbol' "$VERIFY_SEMANTIC")"
STEP_SYMBOL="$(jq -r '.paper_mario_us.cur_game_mode.step_symbol' "$VERIFY_SEMANTIC")"

echo "[remint] authoritative state sha256: $OUTPUT_SHA256"
echo "[remint] verify capture sha256: $VERIFY_SHA256"
echo "[remint] verify selected_slot_has_data: $SELECTED_SLOT_HAS_DATA"
echo "[remint] verify current_menu: $CURRENT_MENU"
echo "[remint] verify callbacks: $INIT_SYMBOL / $STEP_SYMBOL"

if [[ "$SELECTED_SLOT_HAS_DATA" != "true" ]]; then
  echo "[remint] selected_slot_has_data mismatch." >&2
  exit 1
fi
if [[ "$CURRENT_MENU" != "FILE_MENU_MAIN" ]]; then
  echo "[remint] current_menu mismatch: $CURRENT_MENU" >&2
  exit 1
fi
if [[ "$INIT_SYMBOL" != "state_init_file_select" || "$STEP_SYMBOL" != "state_step_file_select" ]]; then
  echo "[remint] callback mismatch: $INIT_SYMBOL / $STEP_SYMBOL" >&2
  exit 1
fi

echo "[remint] save-backed file-select authority verified."
