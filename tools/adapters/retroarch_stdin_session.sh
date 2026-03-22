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
                        Local pseudo-commands:
                        WAIT <seconds>
                        WAIT_STATUS <state> <timeout_seconds>
                        WAIT_STATUS_FRAME <state> <min_frame> <timeout_seconds>
                        WAIT_LOG <timeout_seconds> <literal pattern>
                        WAIT_NEW_CAPTURE <timeout_seconds>
  -h, --help            Show this help
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
LOCK_FILE="${TMPDIR:-/tmp}/parallel-n64-retroarch-runtime.lock"
LOCK_FD=""

acquire_runtime_lock() {
  exec {LOCK_FD}> "$LOCK_FILE"
  if ! flock -n "$LOCK_FD"; then
    echo "Another tracked RetroArch runtime scenario is already holding the launch lock." >&2
    exit 1
  fi
}

fail_if_retroarch_running() {
  local matches
  matches="$(ps -C retroarch -o pid=,stat=,cmd= 2>/dev/null | awk '$2 !~ /^Z/ { print }' || true)"
  if [[ -n "$matches" ]]; then
    echo "Another RetroArch process is already running. Stop it before starting a tracked runtime scenario." >&2
    printf '%s\n' "$matches" >&2
    exit 1
  fi
}

BUNDLE_DIR=""
ROM_PATH=""
CORE_PATH=""
MODE="off"
RETROARCH_BIN="${RETROARCH_BIN:-/home/auro/code/RetroArch/retroarch}"
BASE_CONFIG="${BASE_CONFIG:-/home/auro/code/RetroArch/retroarch.cfg}"
STARTUP_WAIT="${STARTUP_WAIT:-8}"
EXIT_WAIT="${EXIT_WAIT:-10}"
PENDING_CAPTURE_BASELINE=""
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

acquire_runtime_lock
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
confirm_quit = "false"
state_slot = "0"
savestate_directory = "$BUNDLE_DIR/states"
screenshot_directory = "$BUNDLE_DIR/captures"
savestate_thumbnail_enable = "false"
menu_enable_widgets = "false"
notification_show_save_state = "false"
notification_show_screenshot = "false"
notification_show_screenshot_flash = "0"
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

log_size_bytes() {
  if [[ -f "$RA_LOG" ]]; then
    wc -c < "$RA_LOG"
  else
    echo 0
  fi
}

capture_file_count() {
  find "$BUNDLE_DIR/captures" -maxdepth 1 -type f | wc -l | tr -d ' '
}

timeout_ceiling_seconds() {
  awk -v timeout="$1" 'BEGIN {
    if (timeout == int(timeout)) {
      printf "%d\n", timeout
    } else {
      printf "%d\n", int(timeout) + 1
    }
  }'
}

wait_for_log_pattern_after() {
  local start_bytes="$1"
  local pattern="$2"
  local timeout_seconds="$3"
  local deadline
  deadline=$(( $(date +%s) + $(timeout_ceiling_seconds "$timeout_seconds") ))

  while (( $(date +%s) < deadline )); do
    if [[ -f "$RA_LOG" ]] && tail -c +"$((start_bytes + 1))" "$RA_LOG" 2>/dev/null | rg -F -q -- "$pattern"; then
      return 0
    fi
    sleep 0.2
  done

  return 1
}

get_last_status_line_after() {
  local start_bytes="$1"
  if [[ ! -f "$RA_LOG" ]]; then
    return 1
  fi

  tail -c +"$((start_bytes + 1))" "$RA_LOG" 2>/dev/null | rg -o "GET_STATUS [^\r\n]*" | tail -n1
}

send_retroarch_command() {
  local cmd="$1"
  printf '%s\n' "$cmd" >> "$COMMAND_LOG"
  echo "[adapter] command: $cmd"
  printf '%s\n' "$cmd" >&3
}

handle_wait_status() {
  local expected_state="$1"
  local timeout_seconds="$2"
  local deadline
  deadline=$(( $(date +%s) + $(timeout_ceiling_seconds "$timeout_seconds") ))

  while (( $(date +%s) < deadline )); do
    local start_bytes
    start_bytes="$(log_size_bytes)"
    send_retroarch_command "GET_STATUS"
    if wait_for_log_pattern_after "$start_bytes" "GET_STATUS $expected_state" 2; then
      return 0
    fi
    sleep 0.2
  done

  return 1
}

handle_wait_status_frame() {
  local expected_state="$1"
  local min_frame="$2"
  local timeout_seconds="$3"
  local deadline
  deadline=$(( $(date +%s) + $(timeout_ceiling_seconds "$timeout_seconds") ))

  while (( $(date +%s) < deadline )); do
    local start_bytes
    local status_line
    start_bytes="$(log_size_bytes)"
    send_retroarch_command "GET_STATUS"
    if wait_for_log_pattern_after "$start_bytes" "GET_STATUS " 2; then
      status_line="$(get_last_status_line_after "$start_bytes" || true)"
      if [[ "$status_line" =~ ^GET_STATUS[[:space:]]+([^[:space:]]+).*,frame=([0-9]+)$ ]]; then
        local state="${BASH_REMATCH[1]}"
        local frame="${BASH_REMATCH[2]}"
        if [[ "$state" == "$expected_state" ]] && (( frame >= min_frame )); then
          return 0
        fi
      fi
    fi
    sleep 0.2
  done

  return 1
}

handle_wait_new_capture() {
  local timeout_seconds="$1"
  local initial_count
  local deadline
  if [[ -n "$PENDING_CAPTURE_BASELINE" ]]; then
    initial_count="$PENDING_CAPTURE_BASELINE"
  else
    initial_count="$(capture_file_count)"
  fi
  deadline=$(( $(date +%s) + $(timeout_ceiling_seconds "$timeout_seconds") ))

  while (( $(date +%s) < deadline )); do
    local current_count
    current_count="$(capture_file_count)"
    if (( current_count > initial_count )); then
      PENDING_CAPTURE_BASELINE=""
      return 0
    fi
    sleep 0.2
  done

  PENDING_CAPTURE_BASELINE=""
  return 1
}

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

  if [[ "$cmd" =~ ^WAIT_STATUS[[:space:]]+([^[:space:]]+)[[:space:]]+([0-9]+([.][0-9]+)?)$ ]]; then
    expected_state="${BASH_REMATCH[1]}"
    timeout_seconds="${BASH_REMATCH[2]}"
    printf '%s\n' "$cmd" >> "$COMMAND_LOG"
    echo "[adapter] wait status: $expected_state (${timeout_seconds}s)"
    if ! handle_wait_status "$expected_state" "$timeout_seconds"; then
      echo "[adapter] WAIT_STATUS failed: $expected_state" >&2
      exit 1
    fi
    continue
  fi

  if [[ "$cmd" =~ ^WAIT_STATUS_FRAME[[:space:]]+([^[:space:]]+)[[:space:]]+([0-9]+)[[:space:]]+([0-9]+([.][0-9]+)?)$ ]]; then
    expected_state="${BASH_REMATCH[1]}"
    min_frame="${BASH_REMATCH[2]}"
    timeout_seconds="${BASH_REMATCH[3]}"
    printf '%s\n' "$cmd" >> "$COMMAND_LOG"
    echo "[adapter] wait status/frame: $expected_state frame>=$min_frame (${timeout_seconds}s)"
    if ! handle_wait_status_frame "$expected_state" "$min_frame" "$timeout_seconds"; then
      echo "[adapter] WAIT_STATUS_FRAME failed: $expected_state frame>=$min_frame" >&2
      exit 1
    fi
    continue
  fi

  if [[ "$cmd" =~ ^WAIT_LOG[[:space:]]+([0-9]+([.][0-9]+)?)[[:space:]]+(.+)$ ]]; then
    timeout_seconds="${BASH_REMATCH[1]}"
    pattern="${BASH_REMATCH[3]}"
    start_bytes="$(log_size_bytes)"
    printf '%s\n' "$cmd" >> "$COMMAND_LOG"
    echo "[adapter] wait log: ${pattern} (${timeout_seconds}s)"
    if ! wait_for_log_pattern_after "$start_bytes" "$pattern" "$timeout_seconds"; then
      echo "[adapter] WAIT_LOG failed: $pattern" >&2
      exit 1
    fi
    continue
  fi

  if [[ "$cmd" =~ ^WAIT_NEW_CAPTURE[[:space:]]+([0-9]+([.][0-9]+)?)$ ]]; then
    timeout_seconds="${BASH_REMATCH[1]}"
    printf '%s\n' "$cmd" >> "$COMMAND_LOG"
    echo "[adapter] wait new capture (${timeout_seconds}s)"
    if ! handle_wait_new_capture "$timeout_seconds"; then
      echo "[adapter] WAIT_NEW_CAPTURE failed." >&2
      exit 1
    fi
    continue
  fi

  start_bytes="$(log_size_bytes)"
  if [[ "$cmd" == "SCREENSHOT" ]]; then
    PENDING_CAPTURE_BASELINE="$(capture_file_count)"
  fi
  send_retroarch_command "$cmd"

  case "$cmd" in
    GET_STATUS)
      if ! wait_for_log_pattern_after "$start_bytes" "GET_STATUS " 5; then
        echo "[adapter] GET_STATUS acknowledgement missing." >&2
        exit 1
      fi
      ;;
    SET_PAUSE*)
      if ! wait_for_log_pattern_after "$start_bytes" "SET_PAUSE " 5; then
        echo "[adapter] SET_PAUSE acknowledgement missing." >&2
        exit 1
      fi
      ;;
    STEP_FRAME*)
      if ! wait_for_log_pattern_after "$start_bytes" "STEP_FRAME " 5; then
        echo "[adapter] STEP_FRAME acknowledgement missing." >&2
        exit 1
      fi
      ;;
    SET_INPUT_PORT*)
      if ! wait_for_log_pattern_after "$start_bytes" "SET_INPUT_PORT " 5; then
        echo "[adapter] SET_INPUT_PORT acknowledgement missing." >&2
        exit 1
      fi
      ;;
    CLEAR_INPUT_PORT*)
      if ! wait_for_log_pattern_after "$start_bytes" "CLEAR_INPUT_PORT " 5; then
        echo "[adapter] CLEAR_INPUT_PORT acknowledgement missing." >&2
        exit 1
      fi
      ;;
    GET_INPUT_PORT*)
      if ! wait_for_log_pattern_after "$start_bytes" "GET_INPUT_PORT " 5; then
        echo "[adapter] GET_INPUT_PORT acknowledgement missing." >&2
        exit 1
      fi
      ;;
    SAVE_STATE)
      if ! wait_for_log_pattern_after "$start_bytes" "[State] Saving state" 15; then
        echo "[adapter] SAVE_STATE acknowledgement missing." >&2
        exit 1
      fi
      ;;
    LOAD_STATE_SLOT*|LOAD_STATE_SLOT_PAUSED*)
      if ! wait_for_log_pattern_after "$start_bytes" "[State] Loading state" 15; then
        echo "[adapter] LOAD_STATE_SLOT acknowledgement missing." >&2
        exit 1
      fi
      ;;
  esac
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
