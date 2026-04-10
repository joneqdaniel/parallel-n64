#!/usr/bin/env bash
set -euo pipefail

# Quick boot test: launch a game with an HTS pack, run for N seconds,
# capture the hi-res keying summary telemetry on shutdown.
#
# Usage:
#   tools/scenarios/quick-boot-hires-telemetry.sh \
#     --rom "assets/Super Mario 64 (USA).zip" \
#     --pack "assets/SUPER MARIO 64_HIRESTEXTURES.hts" \
#     [--seconds 30]

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORE_PATH="$REPO_ROOT/parallel_n64_libretro.so"
RETROARCH_BIN="/home/auro/code/RetroArch/retroarch"
RETROARCH_OPT_FILE="$HOME/.config/retroarch/config/ParaLLEl N64/ParaLLEl N64.opt"

ROM_PATH=""
PACK_PATH=""
RUN_SECONDS=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rom) ROM_PATH="$2"; shift 2 ;;
    --pack) PACK_PATH="$2"; shift 2 ;;
    --seconds) RUN_SECONDS="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ROM_PATH" || -z "$PACK_PATH" ]]; then
  echo "Usage: $0 --rom <path> --pack <path> [--seconds N]" >&2
  exit 1
fi

ROM_PATH="$(realpath "$ROM_PATH")"
PACK_PATH="$(realpath "$PACK_PATH")"

if [[ ! -f "$ROM_PATH" ]]; then
  echo "ROM not found: $ROM_PATH" >&2; exit 1
fi
if [[ ! -f "$PACK_PATH" ]]; then
  echo "Pack not found: $PACK_PATH" >&2; exit 1
fi

# Backup and patch core options to enable hirestex with legacy-only source mode
OPT_BACKUP="${RETROARCH_OPT_FILE}.boot-test-backup"
cp "$RETROARCH_OPT_FILE" "$OPT_BACKUP"
restore_opts() {
  if [[ -f "$OPT_BACKUP" ]]; then
    cp "$OPT_BACKUP" "$RETROARCH_OPT_FILE"
    rm -f "$OPT_BACKUP"
  fi
}
trap restore_opts EXIT

sed -i \
  -e 's/parallel-n64-parallel-rdp-hirestex = "[^"]*"/parallel-n64-parallel-rdp-hirestex = "enabled"/' \
  -e 's/parallel-n64-parallel-rdp-hirestex-source-mode = "[^"]*"/parallel-n64-parallel-rdp-hirestex-source-mode = "all"/' \
  -e 's/parallel-n64-gfxplugin = "[^"]*"/parallel-n64-gfxplugin = "parallel"/' \
  "$RETROARCH_OPT_FILE"

LOG_DIR="$(mktemp -d /tmp/parallel-n64-boot-test-XXXXXX)"
LOG_FILE="$LOG_DIR/retroarch.log"

echo "=== Quick Boot Hi-Res Telemetry ==="
echo "ROM:     $ROM_PATH"
echo "Pack:    $PACK_PATH"
echo "Seconds: $RUN_SECONDS"
echo "Log:     $LOG_FILE"
echo ""

# Launch RetroArch with the pack path override
PARALLEL_RDP_HIRES_CACHE_PATH="$PACK_PATH" \
PARALLEL_RDP_HIRES_DEBUG=1 \
PARALLEL_RDP_HIRES_GLIDEN64_COMPAT_CRC=1 \
  "$RETROARCH_BIN" \
  -L "$CORE_PATH" \
  "$ROM_PATH" \
  --verbose \
  > "$LOG_FILE" 2>&1 &
RA_PID=$!

echo "RetroArch PID: $RA_PID"
echo "Waiting ${RUN_SECONDS}s..."
sleep "$RUN_SECONDS"

# Graceful shutdown: send SIGINT first, then SIGTERM if needed
kill -INT "$RA_PID" 2>/dev/null || true
for i in $(seq 1 10); do
  if ! kill -0 "$RA_PID" 2>/dev/null; then break; fi
  sleep 0.5
done
if kill -0 "$RA_PID" 2>/dev/null; then
  kill -TERM "$RA_PID" 2>/dev/null || true
  sleep 1
fi

echo ""
echo "=== Hi-Res Keying Summary ==="
grep -i "Hi-res keying summary" "$LOG_FILE" || echo "(no keying summary found)"
echo ""
echo "=== Hi-Res Load/Config Lines ==="
grep -i "Hi-res\|hires\|texture.*replacement\|load.*cache\|PHRB\|\.hts\|\.htc" "$LOG_FILE" | head -30 || echo "(no hi-res lines found)"
echo ""
echo "Full log: $LOG_FILE"
