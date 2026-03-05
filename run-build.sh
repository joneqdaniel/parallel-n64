#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JOBS="${JOBS:-$(nproc)}"
BUILD_TYPE="${BUILD_TYPE:-release}"
HAVE_PARALLEL="${HAVE_PARALLEL:-1}"
HAVE_PARALLEL_RSP="${HAVE_PARALLEL_RSP:-1}"
AUTO_CLEAN="${RUN_BUILD_AUTO_CLEAN:-1}"
STATE_DIR="$SCRIPT_DIR/.build"
STATE_FILE="$STATE_DIR/run-build.last-fingerprint"
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
  - Automatically runs `make clean` when effective build flags change.
    Set `RUN_BUILD_AUTO_CLEAN=0` to disable this behavior.
  - Additional make args can be passed after `--`.
EOF
}

compute_build_fingerprint() {
  {
    printf 'HAVE_PARALLEL=%s\n' "$HAVE_PARALLEL"
    printf 'HAVE_PARALLEL_RSP=%s\n' "$HAVE_PARALLEL_RSP"
    printf 'DEBUG=%s\n' "$MAKE_DEBUG"
    for arg in "${passthrough_args[@]}"; do
      printf 'ARG=%s\n' "$arg"
    done
  } | sha256sum | awk '{ print $1 }'
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

BUILD_FINGERPRINT="$(compute_build_fingerprint)"

cd "$SCRIPT_DIR"

if (( DO_CLEAN )); then
  echo "[build] clean"
  make clean
fi

mkdir -p "$STATE_DIR"
LAST_FINGERPRINT=""
if [[ -f "$STATE_FILE" ]]; then
  LAST_FINGERPRINT="$(<"$STATE_FILE")"
fi

if [[ "$AUTO_CLEAN" != "0" && "$LAST_FINGERPRINT" != "$BUILD_FINGERPRINT" && "$DO_CLEAN" -eq 0 ]]; then
  echo "[build] auto-clean: build flags changed"
  make clean
fi

echo "[build] make -j$JOBS HAVE_PARALLEL=$HAVE_PARALLEL HAVE_PARALLEL_RSP=$HAVE_PARALLEL_RSP DEBUG=$MAKE_DEBUG"
make -j"$JOBS" \
  HAVE_PARALLEL="$HAVE_PARALLEL" \
  HAVE_PARALLEL_RSP="$HAVE_PARALLEL_RSP" \
  DEBUG="$MAKE_DEBUG" \
  "${passthrough_args[@]}"

printf '%s\n' "$BUILD_FINGERPRINT" > "$STATE_FILE"

echo "[build] output: $SCRIPT_DIR/parallel_n64_libretro.so"
