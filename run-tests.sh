#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/build/ctest}"
PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc)}"

clean_build=0
list_only=0
declare -a ctest_args
ctest_args=(--output-on-failure)

usage() {
  cat <<'EOF'
Usage:
  run-tests.sh [options] [-- CTEST_ARGS...]

Options:
  --clean               Remove build dir before configuring
  --list                List tests without running them
  --build-dir PATH      Override build dir (default: ./build/ctest)
  -R REGEX              Pass test regex to ctest
  -h, --help            Show this help

Examples:
  ./run-tests.sh
  ./run-tests.sh --list
  ./run-tests.sh -R hires.texture_keying
  ./run-tests.sh -- --repeat until-fail:10
EOF
}

while (($#)); do
  case "$1" in
    --clean)
      clean_build=1
      ;;
    --list)
      list_only=1
      ;;
    --build-dir)
      shift
      BUILD_DIR="${1:-}"
      if [[ -z "$BUILD_DIR" ]]; then
        echo "--build-dir requires a path." >&2
        exit 2
      fi
      ;;
    -R)
      shift
      if [[ -z "${1:-}" ]]; then
        echo "-R requires a regex value." >&2
        exit 2
      fi
      ctest_args+=(-R "$1")
      ;;
    --)
      shift
      ctest_args+=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      ctest_args+=("$1")
      ;;
  esac
  shift
done

if (( clean_build )) && [[ -d "$BUILD_DIR" ]]; then
  rm -rf "$BUILD_DIR"
fi

echo "[tests] configure: $BUILD_DIR"
cmake -S "$SCRIPT_DIR" -B "$BUILD_DIR"

echo "[tests] build: $BUILD_DIR"
cmake --build "$BUILD_DIR" --parallel "$PARALLEL_JOBS"

if (( list_only )); then
  echo "[tests] list"
  ctest --test-dir "$BUILD_DIR" -N "${ctest_args[@]}"
else
  echo "[tests] run"
  ctest --test-dir "$BUILD_DIR" "${ctest_args[@]}"
fi
