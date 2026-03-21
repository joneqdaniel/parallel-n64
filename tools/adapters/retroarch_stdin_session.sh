#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  tools/adapters/retroarch_stdin_session.sh [options] --command CMD [--command CMD ...]

Required:
  --bundle-dir PATH     Output bundle directory
  --rom PATH            Content path
  --core PATH           Core path

Options:
  --mode off|on         Scenario mode label (default: off)
  --retroarch-bin PATH  RetroArch executable path
  --base-config PATH    Base RetroArch config path
  --startup-wait SEC    Seconds to wait before sending commands (default: 8)
  --command CMD         Command to send over stdin interface (repeatable)
                        Local pseudo-command: WAIT <seconds>
  -h, --help            Show this help
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

fail_if_retroarch_running() {
  if pgrep -x retroarch >/dev/null 2>&1; then
    echo "Another RetroArch process is already running. Stop it before starting a tracked runtime scenario." >&2
    pgrep -a -x retroarch >&2 || true
    exit 1
  fi
}

BUNDLE_DIR=""
ROM_PATH=""
CORE_PATH=""
MODE="off"
RETROARCH_BIN="${RETROARCH_BIN:-/home/auro/code/mupen/RetroArch-upstream/retroarch}"
BASE_CONFIG="${BASE_CONFIG:-/home/auro/code/RetroArch/retroarch.cfg}"
STARTUP_WAIT="${STARTUP_WAIT:-8}"
EXIT_WAIT="${EXIT_WAIT:-10}"
declare -a COMMANDS=()

while (($#)); do
  case "$1" in
    --bundle-dir)
      shift
      BUNDLE_DIR="${1:-}"
      ;;
    --rom)
      shift
      ROM_PATH="${1:-}"
      ;;
    --core)
      shift
      CORE_PATH="${1:-}"
      ;;
    --mode)
      shift
      MODE="${1:-}"
      ;;
    --retroarch-bin)
      shift
      RETROARCH_BIN="${1:-}"
      ;;
    --base-config)
      shift
      BASE_CONFIG="${1:-}"
      ;;
    --startup-wait)
      shift
      STARTUP_WAIT="${1:-}"
      ;;
    --command)
      shift
      COMMANDS+=("${1:-}")
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

if [[ -z "$BUNDLE_DIR" || -z "$ROM_PATH" || -z "$CORE_PATH" ]]; then
  echo "--bundle-dir, --rom, and --core are required." >&2
  exit 2
fi

if [[ ! -x "$RETROARCH_BIN" ]]; then
  echo "RetroArch binary not executable: $RETROARCH_BIN" >&2
  exit 1
fi

if [[ ! -f "$BASE_CONFIG" ]]; then
  echo "RetroArch base config not found: $BASE_CONFIG" >&2
  exit 1
fi

if [[ ! -f "$ROM_PATH" ]]; then
  echo "ROM not found: $ROM_PATH" >&2
  exit 1
fi

if [[ ! -f "$CORE_PATH" ]]; then
  echo "Core not found: $CORE_PATH" >&2
  exit 1
fi

fail_if_retroarch_running

mkdir -p "$BUNDLE_DIR"/captures "$BUNDLE_DIR"/logs "$BUNDLE_DIR"/traces "$BUNDLE_DIR"/states

APPEND_CONFIG="$BUNDLE_DIR/retroarch.append.cfg"
FIFO_PATH="$BUNDLE_DIR/retroarch.stdin"
COMMAND_LOG="$BUNDLE_DIR/logs/retroarch.commands.log"
SESSION_ENV="$BUNDLE_DIR/retroarch.session.env"
RA_LOG="$BUNDLE_DIR/logs/retroarch.log"

HIRES_VALUE="disabled"
if [[ "$MODE" == "on" ]]; then
  HIRES_VALUE="enabled"
fi

cat > "$APPEND_CONFIG" <<EOF
config_save_on_exit = "false"
stdin_cmd_enable = "true"
network_cmd_enable = "false"
state_slot = "0"
savestate_directory = "$BUNDLE_DIR/states"
screenshot_directory = "$BUNDLE_DIR/captures"
savestate_thumbnail_enable = "false"
video_fullscreen = "true"
video_windowed_fullscreen = "true"
video_fullscreen_x = "0"
video_fullscreen_y = "0"
parallel-n64-gfxplugin = "parallel"
parallel-n64-parallel-rdp-upscaling = "4x"
parallel-n64-parallel-rdp-hirestex = "$HIRES_VALUE"
parallel-n64-parallel-rdp-native-tex-rect = "enabled"
parallel-n64-parallel-rdp-native-texture-lod = "enabled"
EOF

rm -f "$FIFO_PATH"
mkfifo "$FIFO_PATH"
exec 3<> "$FIFO_PATH"

cleanup() {
  exec 3>&-
  rm -f "$FIFO_PATH"
}
trap cleanup EXIT

"$RETROARCH_BIN" \
  --verbose \
  --config "$BASE_CONFIG" \
  --appendconfig "$APPEND_CONFIG" \
  -L "$CORE_PATH" \
  "$ROM_PATH" \
  <"$FIFO_PATH" >"$RA_LOG" 2>&1 &
RA_PID=$!

cat > "$SESSION_ENV" <<EOF
RETROARCH_PID=$RA_PID
RETROARCH_BIN=$RETROARCH_BIN
BASE_CONFIG=$BASE_CONFIG
APPEND_CONFIG=$APPEND_CONFIG
STDIN_FIFO=$FIFO_PATH
ROM_PATH=$ROM_PATH
CORE_PATH=$CORE_PATH
MODE=$MODE
STARTUP_WAIT=$STARTUP_WAIT
EOF

echo "[adapter] retroarch pid: $RA_PID"
echo "[adapter] log: $RA_LOG"
echo "[adapter] appendconfig: $APPEND_CONFIG"
echo "[adapter] startup wait: ${STARTUP_WAIT}s"
sleep "$STARTUP_WAIT"

: > "$COMMAND_LOG"
for cmd in "${COMMANDS[@]}"; do
  if [[ "$cmd" =~ ^WAIT[[:space:]]+(.+)$ ]]; then
    wait_seconds="${BASH_REMATCH[1]}"
    printf '%s\n' "$cmd" >> "$COMMAND_LOG"
    echo "[adapter] wait: ${wait_seconds}s"
    sleep "$wait_seconds"
    continue
  fi

  printf '%s\n' "$cmd" >&3
  printf '%s\n' "$cmd" >> "$COMMAND_LOG"
  echo "[adapter] command: $cmd"
  sleep 1
done

if [[ -f "$BUNDLE_DIR/bundle.json" ]]; then
  sed -i 's/"scenario_state": "bundle_initialized"/"scenario_state": "runtime_attempted"/' "$BUNDLE_DIR/bundle.json"
  sed -i 's/"runtime_executed": false/"runtime_executed": true/' "$BUNDLE_DIR/bundle.json"
fi

exec 3>&-

forced_termination=0
for _ in $(seq 1 "$EXIT_WAIT"); do
  if ! kill -0 "$RA_PID" 2>/dev/null; then
    break
  fi
  sleep 1
done

if kill -0 "$RA_PID" 2>/dev/null; then
  forced_termination=1
  echo "[adapter] RetroArch did not exit after QUIT; sending SIGTERM."
  kill "$RA_PID" 2>/dev/null || true
  sleep 2
fi

exit_status=0
if wait "$RA_PID"; then
  exit_status=0
else
  exit_status=$?
fi

cat > "$BUNDLE_DIR/retroarch.run.env" <<EOF
RUNTIME_EXECUTED=1
RETROARCH_EXIT_STATUS=$exit_status
FORCED_TERMINATION=$forced_termination
EOF
