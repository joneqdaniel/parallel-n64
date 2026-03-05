#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JOBS="${JOBS:-$(nproc)}"
BUILD_TYPE="${BUILD_TYPE:-release}"
HAVE_PARALLEL="${HAVE_PARALLEL:-1}"
HAVE_PARALLEL_RSP="${HAVE_PARALLEL_RSP:-1}"
DO_CLEAN=0
declare -a passthrough_args=()

usage() {
  cat <<'EOF'
Usage:
  run-build.sh [options] [-- MAKE_ARGS...]

Options:
  --clean                 Run `make clean` before building
  --jobs N                Parallel jobs (default: nproc)
  --debug                 Build with DEBUG=1
  --release               Build with DEBUG=0 (default)
  --no-parallel-rsp       Build with HAVE_PARALLEL_RSP=0
  --parallel-rsp          Build with HAVE_PARALLEL_RSP=1
  -h, --help              Show this help

Notes:
  - Defaults are tuned for this fork:
    HAVE_PARALLEL=1 HAVE_PARALLEL_RSP=1
  - Additional make args can be passed after `--`.
EOF
}

while (($#)); do
  case "$1" in
    --clean)
      DO_CLEAN=1
      ;;
    --jobs)
      shift
      JOBS="${1:-}"
      if [[ -z "$JOBS" ]]; then
        echo "--jobs requires a value." >&2
        exit 2
      fi
      ;;
    --debug)
      BUILD_TYPE="debug"
      ;;
    --release)
      BUILD_TYPE="release"
      ;;
    --no-parallel-rsp)
      HAVE_PARALLEL_RSP=0
      ;;
    --parallel-rsp)
      HAVE_PARALLEL_RSP=1
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

MAKE_DEBUG=0
if [[ "$BUILD_TYPE" == "debug" ]]; then
  MAKE_DEBUG=1
fi

cd "$SCRIPT_DIR"

if (( DO_CLEAN )); then
  echo "[build] clean"
  make clean
fi

echo "[build] make -j$JOBS HAVE_PARALLEL=$HAVE_PARALLEL HAVE_PARALLEL_RSP=$HAVE_PARALLEL_RSP DEBUG=$MAKE_DEBUG"
make -j"$JOBS" \
  HAVE_PARALLEL="$HAVE_PARALLEL" \
  HAVE_PARALLEL_RSP="$HAVE_PARALLEL_RSP" \
  DEBUG="$MAKE_DEBUG" \
  "${passthrough_args[@]}"

echo "[build] output: $SCRIPT_DIR/parallel_n64_libretro.so"
