#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_RETROARCH="/home/auro/code/mupen/RetroArch-upstream/retroarch"
DEFAULT_ROM_DIR="/home/auro/code/n64_roms"
DEFAULT_ROM_NAME="Paper Mario (USA).zip"
REFERENCE_CORE="$SCRIPT_DIR/builds/parallel_n64_libretro.reference.so"

use_reference=0
menu_mode=0
retroarch_bin="${RETROARCH_BIN:-$DEFAULT_RETROARCH}"
rom_dir="${ROM_DIR:-$DEFAULT_ROM_DIR}"
explicit_core=""
rom_path=""
declare -a passthrough_args=()

usage() {
  cat <<'EOF'
Usage:
  run-n64.sh [options] [ROM_PATH] [-- RETROARCH_ARGS...]

Options:
  --reference         Use reference core build (builds/parallel_n64_libretro.reference.so)
  --core PATH         Use an explicit core path
  --retroarch PATH    Use an explicit RetroArch binary path
  --rom-dir PATH      ROM base directory for relative ROM paths (default: /home/auro/code/n64_roms)
  --menu              Launch RetroArch menu without content
  --list-cores        Print discovered non-reference core builds
  -h, --help          Show this help

Behavior:
  - Default core: newest non-reference parallel_n64_libretro*.so under this repo/builds.
  - If ROM_PATH is omitted, defaults to "Paper Mario (USA).zip" in ROM dir.
EOF
}

list_non_reference_cores() {
  local -a roots=("$SCRIPT_DIR")
  if [[ -d "$SCRIPT_DIR/builds" ]]; then
    roots+=("$SCRIPT_DIR/builds")
  fi

  find "${roots[@]}" -maxdepth 2 -type f -name 'parallel_n64_libretro*.so' \
    ! -name '*reference*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk '{ $1=""; sub(/^ /, ""); print }'
}

pick_latest_core() {
  local selected
  selected="$(list_non_reference_cores | head -n 1 || true)"
  if [[ -z "$selected" ]]; then
    return 1
  fi
  printf '%s\n' "$selected"
}

resolve_rom_path() {
  local input="$1"
  local base_dir="$2"

  if [[ -f "$input" ]]; then
    printf '%s\n' "$input"
    return 0
  fi

  if [[ -f "$base_dir/$input" ]]; then
    printf '%s\n' "$base_dir/$input"
    return 0
  fi

  return 1
}

while (($#)); do
  case "$1" in
    --reference)
      use_reference=1
      ;;
    --core)
      shift
      explicit_core="${1:-}"
      ;;
    --retroarch)
      shift
      retroarch_bin="${1:-}"
      ;;
    --rom-dir)
      shift
      rom_dir="${1:-}"
      ;;
    --menu)
      menu_mode=1
      ;;
    --list-cores)
      list_non_reference_cores
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      passthrough_args+=("$@")
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -z "$rom_path" ]]; then
        rom_path="$1"
      else
        passthrough_args+=("$1")
      fi
      ;;
  esac
  shift
done

if [[ ! -x "$retroarch_bin" ]]; then
  echo "RetroArch binary not executable: $retroarch_bin" >&2
  exit 1
fi

if [[ -n "$explicit_core" ]]; then
  core_path="$explicit_core"
elif (( use_reference )); then
  core_path="$REFERENCE_CORE"
else
  if ! core_path="$(pick_latest_core)"; then
    echo "No non-reference parallel core builds found." >&2
    exit 1
  fi
fi

if [[ ! -f "$core_path" ]]; then
  echo "Core file not found: $core_path" >&2
  exit 1
fi

if [[ -z "$rom_path" && "$menu_mode" -eq 0 ]]; then
  rom_path="$DEFAULT_ROM_NAME"
fi

declare -a cmd
cmd=("$retroarch_bin" -L "$core_path")

if (( menu_mode )); then
  cmd+=(--menu)
fi

if [[ -n "$rom_path" ]]; then
  if ! resolved_rom="$(resolve_rom_path "$rom_path" "$rom_dir")"; then
    echo "ROM not found: $rom_path" >&2
    exit 1
  fi
  cmd+=("$resolved_rom")
fi

cmd+=("${passthrough_args[@]}")

echo "Using core: $core_path"
exec "${cmd[@]}"
