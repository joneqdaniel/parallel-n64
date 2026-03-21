#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
DEFAULT_RETROARCH="/home/auro/code/RetroArch/retroarch"
DEFAULT_CORE="$REPO_ROOT/parallel_n64_libretro.so"
DEFAULT_ROM="/home/auro/code/n64_roms/Paper Mario (USA).zip"

retroarch_bin="${RETROARCH_BIN:-$DEFAULT_RETROARCH}"
core_path="${CORE_PATH:-$DEFAULT_CORE}"
rom_path="${ROM_PATH:-$DEFAULT_ROM}"
frames="${FRAMES:-180}"
timeout_seconds="${TIMEOUT_SECONDS:-30}"
output_path=""
verbose=0

usage() {
  cat <<'USAGE'
Usage:
  tools/capture-rdp-dump.sh --output PATH [options]

Options:
  --output PATH        Output .rdp path (required)
  --rom PATH           ROM path (default: Paper Mario in ~/code/n64_roms)
  --core PATH          Libretro core path (default: ./parallel_n64_libretro.so)
  --retroarch PATH     RetroArch binary path
  --frames N           Max frames to run before exit (default: 180)
  --timeout SEC        Timeout wrapper in seconds (default: 30)
  --verbose            Enable RetroArch verbose logging
  -h, --help           Show this help

Notes:
  - This script forces Angrylion via a temporary core-options file.
  - Build with HAVE_RDP_DUMP=1, otherwise no dump will be generated.
USAGE
}

while (($#)); do
  case "$1" in
    --output)
      shift
      output_path="${1:-}"
      ;;
    --rom)
      shift
      rom_path="${1:-}"
      ;;
    --core)
      shift
      core_path="${1:-}"
      ;;
    --retroarch)
      shift
      retroarch_bin="${1:-}"
      ;;
    --frames)
      shift
      frames="${1:-}"
      ;;
    --timeout)
      shift
      timeout_seconds="${1:-}"
      ;;
    --verbose)
      verbose=1
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

if [[ -z "$output_path" ]]; then
  echo "--output is required." >&2
  exit 2
fi

if [[ ! -x "$retroarch_bin" ]]; then
  echo "RetroArch binary not executable: $retroarch_bin" >&2
  exit 1
fi
if [[ ! -f "$core_path" ]]; then
  echo "Core not found: $core_path" >&2
  exit 1
fi
if [[ ! -f "$rom_path" ]]; then
  echo "ROM not found: $rom_path" >&2
  exit 1
fi

mkdir -p "$(dirname -- "$output_path")"
rm -f "$output_path"

tmp_cfg="$(mktemp)"
tmp_opt="$(mktemp)"
trap 'rm -f "$tmp_cfg" "$tmp_opt"' EXIT

cat > "$tmp_cfg" <<EOF
core_options_path = "$tmp_opt"
global_core_options = "true"
game_specific_options = "false"
config_save_on_exit = "false"
EOF

cat > "$tmp_opt" <<'EOF'
parallel-n64-gfxplugin = "angrylion"
parallel-n64-angrylion-sync = "High"
parallel-n64-angrylion-multithread = "1"
parallel-n64-angrylion-vioverlay = "Filtered"
parallel-n64-angrylion-overscan = "disabled"
EOF

declare -a cmd
cmd=("$retroarch_bin" -c "$tmp_cfg" -L "$core_path" "$rom_path" --max-frames "$frames")
if (( verbose )); then
  cmd+=(--verbose)
fi

echo "[dump-capture] output: $output_path"
echo "[dump-capture] rom: $rom_path"
echo "[dump-capture] frames: $frames"
echo "[dump-capture] core: $core_path"

set +e
RDP_DUMP="$output_path" timeout --signal=INT --kill-after=5 "$timeout_seconds"s "${cmd[@]}"
retroarch_rc=$?
set -e

if [[ ! -s "$output_path" ]]; then
  echo "Dump capture failed: output file was not produced." >&2
  echo "Hint: ensure the core was built with HAVE_RDP_DUMP=1." >&2
  exit 1
fi

size_bytes="$(wc -c < "$output_path" | tr -d ' ')"
echo "[dump-capture] success: $output_path (${size_bytes} bytes, retroarch_rc=$retroarch_rc)"
