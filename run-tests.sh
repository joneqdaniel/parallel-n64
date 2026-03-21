#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/build/ctest}"
PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc)}"

clean_build=0
list_only=0
selected_profile="all"
build_dir_overridden=0
enable_tsan=0
enable_runtime_conformance=0
has_regex_override=0
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
  --profile NAME        Test profile: all|emu-required|emu-optional|emu-conformance|emu-runtime-conformance|emu-dump|emu-tsan
  -R REGEX              Pass test regex to ctest
  -h, --help            Show this help

Examples:
  ./run-tests.sh
  ./run-tests.sh --profile emu-required
  ./run-tests.sh --profile emu-runtime-conformance
  ./run-tests.sh --profile emu-tsan
  ./run-tests.sh --list
  ./run-tests.sh -R emu.unit.smoke
  ./run-tests.sh -- --repeat until-fail:10
EOF
}

tsan_preflight() {
  local tmpdir probe_src probe_bin build_log run_log compiler
  compiler="${CXX:-c++}"
  tmpdir="$(mktemp -d)"
  probe_src="$tmpdir/tsan_preflight.cpp"
  probe_bin="$tmpdir/tsan_preflight"
  build_log="$tmpdir/build.log"
  run_log="$tmpdir/run.log"

  cat > "$probe_src" <<'EOF'
#include <atomic>
#include <thread>

int main()
{
  std::atomic<int> value{0};
  std::thread worker([&]() { value.store(1, std::memory_order_relaxed); });
  worker.join();
  return value.load(std::memory_order_relaxed) == 1 ? 0 : 1;
}
EOF

  if ! "$compiler" -fsanitize=thread -fno-omit-frame-pointer "$probe_src" -o "$probe_bin" >"$build_log" 2>&1; then
    echo "[tests] tsan preflight compile failed with $compiler:" >&2
    sed -n '1,5p' "$build_log" >&2
    rm -rf "$tmpdir"
    return 1
  fi

  if ! "$probe_bin" >"$run_log" 2>&1; then
    echo "[tests] tsan preflight runtime check failed:" >&2
    sed -n '1,5p' "$run_log" >&2
    rm -rf "$tmpdir"
    return 1
  fi

  rm -rf "$tmpdir"
  return 0
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
      build_dir_overridden=1
      ;;
    --profile)
      shift
      selected_profile="${1:-}"
      if [[ -z "$selected_profile" ]]; then
        echo "--profile requires a value." >&2
        exit 2
      fi
      ;;
    -R)
      shift
      if [[ -z "${1:-}" ]]; then
        echo "-R requires a regex value." >&2
        exit 2
      fi
      has_regex_override=1
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

if (( has_regex_override )) && [[ "$selected_profile" != "all" ]]; then
  echo "--profile cannot be combined with -R." >&2
  exit 2
fi

case "$selected_profile" in
  all)
    ;;
  emu-required)
    ctest_args+=(-R "^emu\\.unit\\.")
    ;;
  emu-optional)
    ctest_args+=(-R "^emu\\.(conformance|dump)\\.")
    ;;
  emu-conformance)
    ctest_args+=(-R "^emu\\.conformance\\.")
    ;;
  emu-runtime-conformance)
    enable_runtime_conformance=1
    ctest_args+=(-R "^emu\\.conformance\\.(runtime_smoke_lavapipe|lavapipe_frame_hash|lavapipe_vi_filters_hash|lavapipe_vi_filters_mixed_hash|lavapipe_vi_downscale_hash|lavapipe_sm64_frame_hash)$")
    ;;
  emu-dump)
    ctest_args+=(-R "^emu\\.dump\\.")
    ;;
  emu-tsan)
    enable_tsan=1
    ctest_args+=(-R "^emu\\.unit\\.(command_ring_policy|worker_thread)$")
    ;;
  *)
    echo "Unknown --profile value: $selected_profile" >&2
    exit 2
    ;;
esac

if (( enable_tsan )) && (( !build_dir_overridden )); then
  BUILD_DIR="$SCRIPT_DIR/build/ctest-tsan"
fi

declare -a cmake_args
cmake_args=()
if (( enable_tsan )); then
  cmake_args+=(
    "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
    "-DCMAKE_C_FLAGS=-fsanitize=thread -fno-omit-frame-pointer"
    "-DCMAKE_CXX_FLAGS=-fsanitize=thread -fno-omit-frame-pointer"
    "-DCMAKE_EXE_LINKER_FLAGS=-fsanitize=thread"
    "-DCMAKE_SHARED_LINKER_FLAGS=-fsanitize=thread"
  )
fi

if (( enable_tsan )) && [[ "${EMU_TSAN_FORCE:-0}" != "1" ]]; then
  if ! tsan_preflight; then
    echo "[tests] emu-tsan skipped: ThreadSanitizer is unavailable in this environment."
    echo "[tests] set EMU_TSAN_FORCE=1 to force execution anyway."
    exit 0
  fi
fi

if (( enable_runtime_conformance )); then
  export EMU_ENABLE_RUNTIME_CONFORMANCE=1
fi

if (( clean_build )) && [[ -d "$BUILD_DIR" ]]; then
  rm -rf "$BUILD_DIR"
fi

declare -a build_args
build_args=(--parallel "$PARALLEL_JOBS")
if (( enable_tsan )); then
  build_args+=(--target emu_unit_command_ring_policy_test emu_unit_worker_thread_test)
fi

echo "[tests] profile: $selected_profile"
echo "[tests] configure: $BUILD_DIR"
cmake -S "$SCRIPT_DIR" -B "$BUILD_DIR" "${cmake_args[@]}"

echo "[tests] build: $BUILD_DIR"
cmake --build "$BUILD_DIR" "${build_args[@]}"

if (( list_only )); then
  echo "[tests] list"
  ctest --test-dir "$BUILD_DIR" -N "${ctest_args[@]}"
else
  echo "[tests] run"
  ctest --test-dir "$BUILD_DIR" "${ctest_args[@]}"
fi
