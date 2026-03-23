#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
RUNTIME_ENV="$SCRIPT_DIR/paper-mario-file-select.runtime.env"

EXPECTED_SCREENSHOT_SHA256="6fa8688b382fa1e6f0323f054861a85f593d2d47ca737bb78448e3f268ca63e3"
OUTPUT_PATH="$REPO_ROOT/assets/states/paper-mario-file-select/ParaLLEl N64/Paper Mario (USA).state"
BUNDLE_ROOT=""

usage() {
  cat <<'EOF'
Usage:
  tools/scenarios/remint-paper-mario-file-select-authority.sh [options]

Options:
  --output-path PATH  Write the reminted authoritative state here
  --bundle-root PATH  Directory for bootstrap/verify evidence bundles
  -h, --help          Show this help

Notes:
  - This script intentionally remints the authoritative Paper Mario file-select state.
  - It uses the verified bootstrap path: title-screen state -> settle 3 -> hold START for 60 frames -> advance to frame 303 -> save.
  - It then verifies the result with the canonical steady-state path: load -> settle 3 -> capture.
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

if [[ -z "${BOOTSTRAP_STATE_PATH:-}" || ! -f "${BOOTSTRAP_STATE_PATH:-}" ]]; then
  echo "Bootstrap state not found: ${BOOTSTRAP_STATE_PATH:-missing}" >&2
  exit 1
fi

if [[ -z "$BUNDLE_ROOT" ]]; then
  timestamp="$(date +"%Y%m%d-%H%M%S")"
  BUNDLE_ROOT="$REPO_ROOT/artifacts/paper-mario-file-select/remint/$timestamp"
fi

BOOTSTRAP_BUNDLE="$BUNDLE_ROOT/bootstrap"
VERIFY_BUNDLE="$BUNDLE_ROOT/verify"
BOOTSTRAP_STATE_COPY="$BOOTSTRAP_BUNDLE/states/ParaLLEl N64/Paper Mario (USA).state"

mkdir -p "$BOOTSTRAP_BUNDLE/states/ParaLLEl N64"
cp "$BOOTSTRAP_STATE_PATH" "$BOOTSTRAP_STATE_COPY"

echo "[remint] bootstrap bundle: $BOOTSTRAP_BUNDLE"
echo "[remint] verify bundle: $VERIFY_BUNDLE"
echo "[remint] output path: $OUTPUT_PATH"

INPUT_HOLD_TARGET=$(( POST_LOAD_SETTLE_FRAMES + FILE_SELECT_START_HOLD_FRAMES ))
REMAINING_FRAMES=$(( FILE_SELECT_TARGET_FRAME - INPUT_HOLD_TARGET ))

PARALLEL_N64_GFX_PLUGIN_OVERRIDE="parallel" \
"$REPO_ROOT/tools/adapters/retroarch_stdin_session.sh" \
  --bundle-dir "$BOOTSTRAP_BUNDLE" \
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
  --command "SET_INPUT_PORT 0 ${FILE_SELECT_START_MASK}" \
  --command "STEP_FRAME ${FILE_SELECT_START_HOLD_FRAMES}" \
  --command "WAIT_STATUS_FRAME PAUSED ${INPUT_HOLD_TARGET} 10" \
  --command "CLEAR_INPUT_PORT 0" \
  --command "STEP_FRAME ${REMAINING_FRAMES}" \
  --command "WAIT_STATUS_FRAME PAUSED ${FILE_SELECT_TARGET_FRAME} 10" \
  --command "SAVE_STATE" \
  --command "WAIT_SAVE_STATE" \
  --command "QUIT"

mkdir -p "$(dirname -- "$OUTPUT_PATH")"
cp "$BOOTSTRAP_STATE_COPY" "$OUTPUT_PATH"

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
  --command "GET_STATUS" \
  --command "SCREENSHOT" \
  --command "WAIT_NEW_CAPTURE 10" \
  --command "QUIT"

VERIFY_CAPTURE="$(find "$VERIFY_BUNDLE/captures" -maxdepth 1 -type f | head -n1)"
if [[ -z "$VERIFY_CAPTURE" ]]; then
  echo "[remint] verification capture missing." >&2
  exit 1
fi

VERIFY_SHA256="$(scenario_sha256_file "$VERIFY_CAPTURE")"
OUTPUT_SHA256="$(scenario_sha256_file "$OUTPUT_PATH")"

echo "[remint] authoritative state sha256: $OUTPUT_SHA256"
echo "[remint] verify capture sha256: $VERIFY_SHA256"

if [[ "$VERIFY_SHA256" != "$EXPECTED_SCREENSHOT_SHA256" ]]; then
  echo "[remint] verification capture hash mismatch." >&2
  echo "[remint] expected: $EXPECTED_SCREENSHOT_SHA256" >&2
  echo "[remint] actual:   $VERIFY_SHA256" >&2
  exit 1
fi

echo "[remint] canonical file-select authority verified."
