#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

MODE="off"
INPUT_MASK=""
INPUT_HOLD_FRAMES="1"
SETTLES="1,2,3,5,10,20"
PROBE_PREFIX="signal-sweep"
BASE_BUNDLE_DIR="$REPO_ROOT/artifacts/paper-mario-file-select-input-probe/off"

usage() {
  cat <<'EOF'
Usage:
  tools/scenarios/paper-mario-file-select-signal-sweep.sh [options]

Options:
  --mode off|on              Bundle mode label (default: off)
  --input-mask HEX           Required controller mask (example: 0x01)
  --input-hold-frames N      Frames to hold the input (default: 1)
  --settles CSV              Comma-separated post-input settle frames (default: 1,2,3,5,10,20)
  --probe-prefix LABEL       Prefix for bundle labels (default: signal-sweep)
  --base-bundle-dir PATH     Root directory for emitted bundles
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
    --settles)
      shift
      SETTLES="${1:-}"
      ;;
    --probe-prefix)
      shift
      PROBE_PREFIX="${1:-}"
      ;;
    --base-bundle-dir)
      shift
      BASE_BUNDLE_DIR="${1:-}"
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

if [[ -z "$INPUT_MASK" ]]; then
  echo "--input-mask is required." >&2
  exit 2
fi

printf 'settle\tcurrent_menu\tmain_state\tmain_selected\tselected_slot_has_data\tconfirm_selected\texit_mode_guess\tinput_field_fp_update\tinput_keyboard_fp_update\tconfirm_options_flags\tconfirm_options_fp_pending\tslot2_body_flags\tslot2_body_fp_pending\n'

IFS=',' read -r -a settle_values <<< "$SETTLES"
for settle in "${settle_values[@]}"; do
  bundle_dir="$BASE_BUNDLE_DIR/$(date +%Y%m%d)-${PROBE_PREFIX}-settle-${settle}"
  "$SCRIPT_DIR/paper-mario-file-select-input-probe.sh" \
    --mode "$MODE" \
    --input-mask "$INPUT_MASK" \
    --input-hold-frames "$INPUT_HOLD_FRAMES" \
    --post-input-settle "$settle" \
    --probe-label "${PROBE_PREFIX}-settle-${settle}" \
    --bundle-dir "$bundle_dir" \
    --run >/dev/null

  json="$bundle_dir/traces/paper-mario-game-status.json"
  jq -r --arg settle "$settle" '
    [
      $settle,
      (.paper_mario_us.filemenu.current_menu_name // "null"),
      (.paper_mario_us.filemenu.main_panel.state_name // "null"),
      (.paper_mario_us.filemenu.main_panel.selected_name // "null"),
      ((.paper_mario_us.filemenu.selected_slot_has_data // null) | tostring),
      (.paper_mario_us.filemenu.confirm_panel.selected_name // "null"),
      (.paper_mario_us.filemenu.exit_mode_guess_name // "null"),
      (.paper_mario_us.windows.input_field.fp_update_name // .paper_mario_us.windows.input_field.fp_update // "null"),
      (.paper_mario_us.windows.input_keyboard.fp_update_name // .paper_mario_us.windows.input_keyboard.fp_update // "null"),
      ((.paper_mario_us.windows.confirm_options.flag_names // []) | join(",")),
      (.paper_mario_us.windows.confirm_options.fp_pending_name // .paper_mario_us.windows.confirm_options.fp_pending // "null"),
      ((.paper_mario_us.windows.slot2_body.flag_names // []) | join(",")),
      (.paper_mario_us.windows.slot2_body.fp_pending_name // .paper_mario_us.windows.slot2_body.fp_pending // "null")
    ] | @tsv
  ' "$json"
done
