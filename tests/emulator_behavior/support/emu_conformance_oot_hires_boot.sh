#!/usr/bin/env bash
set -euo pipefail

# OoT hi-res boot conformance test.
# Boots OoT with the PHRB pack for 45s, captures keying summary,
# asserts provider=on, entries > 40000, compat_draw_hits > 0,
# and CI palette CRC hits > 0 (OoT uses CI textures extensively).

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

CACHE_PATH_DEFAULT="$REPO_ROOT/artifacts/hts2phrb/oot-reloaded/package.phrb"
CACHE_PATH="${EMU_RUNTIME_OOT_PHRB:-$CACHE_PATH_DEFAULT}"
ROM_PATH_DEFAULT="$REPO_ROOT/assets/Legend of Zelda, The - Ocarina of Time (USA).zip"
ROM_PATH="${EMU_RUNTIME_OOT_ROM:-$ROM_PATH_DEFAULT}"

if [[ "${EMU_ENABLE_RUNTIME_CONFORMANCE:-0}" != "1" ]]; then
  echo "SKIP: set EMU_ENABLE_RUNTIME_CONFORMANCE=1 to run OoT hi-res boot conformance."
  exit 77
fi

if [[ ! -f "$CACHE_PATH" ]]; then
  echo "SKIP: OoT PHRB package not found at $CACHE_PATH (set EMU_RUNTIME_OOT_PHRB to override)."
  exit 77
fi

if [[ ! -f "$ROM_PATH" ]]; then
  echo "SKIP: OoT ROM not found at $ROM_PATH (set EMU_RUNTIME_OOT_ROM to override)."
  exit 77
fi

CORE_PATH="$REPO_ROOT/parallel_n64_libretro.so"
if [[ ! -f "$CORE_PATH" ]]; then
  echo "SKIP: libretro core not found at $CORE_PATH."
  exit 77
fi

RETROARCH_BIN="${RETROARCH_BIN:-/home/auro/code/RetroArch/retroarch}"
RETROARCH_BASE_CONFIG="${RETROARCH_BASE_CONFIG:-/home/auro/code/RetroArch/retroarch.cfg}"
RETROARCH_OPT_FILE="${RETROARCH_OPT_FILE:-$HOME/.config/retroarch/config/ParaLLEl N64/ParaLLEl N64.opt}"
if [[ ! -x "$RETROARCH_BIN" ]]; then
  echo "SKIP: RetroArch binary not found at $RETROARCH_BIN."
  exit 77
fi
if [[ ! -f "$RETROARCH_OPT_FILE" ]]; then
  echo "SKIP: core options file not found at $RETROARCH_OPT_FILE."
  exit 77
fi

RUN_SECONDS=45
LOG_DIR="$(mktemp -d /tmp/oot-hires-boot-XXXXXX)"
LOG_FILE="$LOG_DIR/retroarch.log"

# Backup and patch core options
OPT_BACKUP="$LOG_DIR/opt-backup"
cp "$RETROARCH_OPT_FILE" "$OPT_BACKUP"
restore_opts() {
  if [[ -f "$OPT_BACKUP" ]]; then
    cp "$OPT_BACKUP" "$RETROARCH_OPT_FILE"
  fi
}

cleanup() {
  local rc=$?
  restore_opts
  if [[ $rc -eq 0 ]]; then
    rm -rf "$LOG_DIR"
  else
    echo "[conformance] log dir: $LOG_DIR"
  fi
  exit "$rc"
}
trap cleanup EXIT

sed -i \
  -e 's/parallel-n64-parallel-rdp-hirestex = "[^"]*"/parallel-n64-parallel-rdp-hirestex = "enabled"/' \
  -e 's/parallel-n64-parallel-rdp-hirestex-source-mode = "[^"]*"/parallel-n64-parallel-rdp-hirestex-source-mode = "all"/' \
  -e 's/parallel-n64-gfxplugin = "[^"]*"/parallel-n64-gfxplugin = "parallel"/' \
  "$RETROARCH_OPT_FILE"

PARALLEL_RDP_HIRES_CACHE_PATH="$CACHE_PATH" \
PARALLEL_RDP_HIRES_GLIDEN64_COMPAT_CRC=1 \
  "$RETROARCH_BIN" \
  --verbose \
  --config "$RETROARCH_BASE_CONFIG" \
  -L "$CORE_PATH" \
  "$ROM_PATH" \
  > "$LOG_FILE" 2>&1 &
RA_PID=$!

sleep "$RUN_SECONDS"

kill -INT "$RA_PID" 2>/dev/null || true
for i in $(seq 1 10); do
  if ! kill -0 "$RA_PID" 2>/dev/null; then break; fi
  sleep 0.5
done
if kill -0 "$RA_PID" 2>/dev/null; then
  kill -TERM "$RA_PID" 2>/dev/null || true
  sleep 1
fi
wait "$RA_PID" 2>/dev/null || true

SUMMARY_LINE="$(grep "Hi-res keying summary" "$LOG_FILE" || true)"
if [[ -z "$SUMMARY_LINE" ]]; then
  echo "FAIL: no keying summary found in log." >&2
  exit 1
fi

python3 - "$SUMMARY_LINE" <<'PY'
import re
import sys

line = sys.argv[1]

def extract(key):
    m = re.search(rf'{key}=(\d+)', line)
    return int(m.group(1)) if m else 0

def extract_str(key):
    m = re.search(rf'{key}=(\S+)', line)
    return m.group(1) if m else ""

provider = extract_str("provider")
entries = extract("entries")
compat_draw_hits = extract("compat_draw_hits")
ci_hits = extract("compat_draw_ci_hits")
ci_attempts = extract("compat_draw_ci_attempts")

errors = []
if provider != "on":
    errors.append(f"provider={provider}, expected on")
if entries < 40000:
    errors.append(f"entries={entries}, expected > 40000")
if compat_draw_hits < 1:
    errors.append(f"compat_draw_hits={compat_draw_hits}, expected > 0")
if ci_attempts < 1:
    errors.append(f"compat_draw_ci_attempts={ci_attempts}, expected > 0 (OoT uses CI textures)")
if ci_hits < 1:
    errors.append(f"compat_draw_ci_hits={ci_hits}, expected > 0 (OoT CI textures should match)")

if errors:
    for e in errors:
        print(f"FAIL: {e}", file=sys.stderr)
    sys.exit(1)

print(f"OoT hi-res boot: provider={provider} entries={entries} "
      f"compat_draw_hits={compat_draw_hits} ci_hits={ci_hits}/{ci_attempts}")
PY

echo "emu_conformance_oot_hires_boot: PASS ($CACHE_PATH)"
