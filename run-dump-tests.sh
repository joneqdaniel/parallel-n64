#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
validator_bin="${RDP_VALIDATE_DUMP_BIN:-}"
dump_dir="${RDP_DUMP_CORPUS_DIR:-$SCRIPT_DIR/tests/rdp_dumps}"
provision_validator=0
capture_if_missing=0
capture_output="${RDP_CAPTURE_OUTPUT:-$dump_dir/local/paper_mario_smoke.rdp}"
capture_output_explicit=0
capture_rom="${RDP_CAPTURE_ROM:-/home/auro/code/n64_roms/Paper Mario (USA).zip}"
capture_frames="${RDP_CAPTURE_FRAMES:-180}"
strict_composition=0
required_tags_csv="${RDP_DUMP_REQUIRED_TAGS:-}"
declare -a passthrough_args=()

usage() {
  cat <<'USAGE'
Usage:
  run-dump-tests.sh [options] [-- CTEST_ARGS...]

Options:
  --validator PATH     Path to rdp-validate-dump binary
  --dump-dir PATH      Dump corpus directory (default: ./tests/rdp_dumps)
  --provision-validator
                       Build validator automatically if missing
  --capture-if-missing Generate one Angrylion dump if dump dir is empty
  --capture-output PATH
                       Output dump path used by --capture-if-missing
  --capture-rom PATH   ROM path used by --capture-if-missing
  --capture-frames N   Max frames used by --capture-if-missing (default: 180)
  --strict-composition Enable strict manifest composition gate
  --required-tags CSV  Override required manifest tags (e.g. smoke,sync,depth)
  -h, --help           Show this help

Examples:
  ./run-dump-tests.sh
  ./run-dump-tests.sh --validator /opt/parallel-rdp/rdp-validate-dump
  ./run-dump-tests.sh --provision-validator --capture-if-missing
  ./run-dump-tests.sh --strict-composition --required-tags smoke,sync
  ./run-dump-tests.sh --dump-dir ./local_dumps -- --output-on-failure
USAGE
}

while (($#)); do
  case "$1" in
    --validator)
      shift
      validator_bin="${1:-}"
      if [[ -z "$validator_bin" ]]; then
        echo "--validator requires a path." >&2
        exit 2
      fi
      ;;
    --dump-dir)
      shift
      dump_dir="${1:-}"
      if [[ -z "$dump_dir" ]]; then
        echo "--dump-dir requires a path." >&2
        exit 2
      fi
      ;;
    --provision-validator)
      provision_validator=1
      ;;
    --capture-if-missing)
      capture_if_missing=1
      ;;
    --capture-output)
      shift
      capture_output="${1:-}"
      capture_output_explicit=1
      if [[ -z "$capture_output" ]]; then
        echo "--capture-output requires a path." >&2
        exit 2
      fi
      ;;
    --capture-rom)
      shift
      capture_rom="${1:-}"
      if [[ -z "$capture_rom" ]]; then
        echo "--capture-rom requires a path." >&2
        exit 2
      fi
      ;;
    --capture-frames)
      shift
      capture_frames="${1:-}"
      if [[ -z "$capture_frames" ]]; then
        echo "--capture-frames requires a value." >&2
        exit 2
      fi
      ;;
    --strict-composition)
      strict_composition=1
      ;;
    --required-tags)
      shift
      required_tags_csv="${1:-}"
      if [[ -z "$required_tags_csv" ]]; then
        echo "--required-tags requires a CSV value." >&2
        exit 2
      fi
      ;;
    --)
      shift
      passthrough_args+=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      passthrough_args+=("$1")
      ;;
  esac
  shift
done

if [[ -n "$validator_bin" ]]; then
  export RDP_VALIDATE_DUMP_BIN="$validator_bin"
fi
export RDP_DUMP_CORPUS_DIR="$dump_dir"
if (( strict_composition )); then
  export RDP_DUMP_STRICT_COMPOSITION=1
fi
if [[ -n "$required_tags_csv" ]]; then
  export RDP_DUMP_REQUIRED_TAGS="$required_tags_csv"
fi

if (( ! capture_output_explicit )); then
  capture_output="${RDP_DUMP_CORPUS_DIR}/local/paper_mario_smoke.rdp"
fi

if [[ -z "${RDP_VALIDATE_DUMP_BIN:-}" && (( provision_validator )) ]]; then
  RDP_VALIDATE_DUMP_BIN="$("$SCRIPT_DIR/tools/provision-rdp-validate-dump.sh")"
  export RDP_VALIDATE_DUMP_BIN
fi

mkdir -p "$RDP_DUMP_CORPUS_DIR"

if (( capture_if_missing )); then
  if ! find "$RDP_DUMP_CORPUS_DIR" -maxdepth 1 -type f -name '*.rdp' | read -r _; then
    "$SCRIPT_DIR/tools/capture-rdp-dump.sh" \
      --output "$capture_output" \
      --rom "$capture_rom" \
      --frames "$capture_frames"
  fi
fi

echo "[dump-tests] validator: ${RDP_VALIDATE_DUMP_BIN:-<auto>}" 
echo "[dump-tests] corpus: $RDP_DUMP_CORPUS_DIR"
echo "[dump-tests] strict-composition: ${RDP_DUMP_STRICT_COMPOSITION:-0}"
echo "[dump-tests] required-tags: ${RDP_DUMP_REQUIRED_TAGS:-<default>}"

"$SCRIPT_DIR/run-tests.sh" -R emu.dump "${passthrough_args[@]}"
