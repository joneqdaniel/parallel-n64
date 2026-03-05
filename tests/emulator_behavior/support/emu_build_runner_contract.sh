#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
RUNNER="$REPO_ROOT/run-build.sh"

if [[ ! -f "$RUNNER" ]]; then
  echo "FAIL: missing run-build.sh at $RUNNER" >&2
  exit 1
fi

require_pattern() {
  local pattern="$1"
  local message="$2"
  if ! rg -n --fixed-strings -- "$pattern" "$RUNNER" >/dev/null; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

# Usage/option surface for local build workflow.
require_pattern "run-build.sh [options] [-- MAKE_ARGS...]" \
  "usage text missing make passthrough contract"
require_pattern '--clean                 Run `make clean` before building' \
  "usage text missing --clean option"
require_pattern "--jobs N                Parallel jobs (default: nproc)" \
  "usage text missing --jobs option"
require_pattern "--debug                 Build with DEBUG=1" \
  "usage text missing --debug option"
require_pattern "--release               Build with DEBUG=0 (default)" \
  "usage text missing --release option"
require_pattern "--no-parallel-rsp       Build with HAVE_PARALLEL_RSP=0" \
  "usage text missing --no-parallel-rsp option"
require_pattern "--parallel-rsp          Build with HAVE_PARALLEL_RSP=1" \
  "usage text missing --parallel-rsp option"
require_pattern 'Set `RUN_BUILD_AUTO_CLEAN=0` to disable this behavior.' \
  "usage text missing RUN_BUILD_AUTO_CLEAN override note"

# Required argument guard.
require_pattern "--jobs requires a value." \
  "--jobs missing empty-value guard"

# Defaults and toggle behavior.
require_pattern 'HAVE_PARALLEL="${HAVE_PARALLEL:-1}"' \
  "default HAVE_PARALLEL wiring missing"
require_pattern 'HAVE_PARALLEL_RSP="${HAVE_PARALLEL_RSP:-1}"' \
  "default HAVE_PARALLEL_RSP wiring missing"
require_pattern 'if [[ "$BUILD_TYPE" == "debug" ]]; then' \
  "debug-mode branch missing"
require_pattern 'MAKE_DEBUG=1' \
  "debug-mode make flag mapping missing"

# Build handoff behavior.
require_pattern 'if (( DO_CLEAN )); then' \
  "clean branch guard missing"
require_pattern 'make clean' \
  "clean branch command missing"
require_pattern 'AUTO_CLEAN="${RUN_BUILD_AUTO_CLEAN:-1}"' \
  "RUN_BUILD_AUTO_CLEAN default wiring missing"
require_pattern 'STATE_FILE="$STATE_DIR/run-build.last-fingerprint"' \
  "build fingerprint state file wiring missing"
require_pattern 'BUILD_FINGERPRINT="$(compute_build_fingerprint)"' \
  "build fingerprint computation missing"
require_pattern 'sha256sum' \
  "build fingerprint hash generation missing"
require_pattern 'echo "[build] auto-clean: build flags changed"' \
  "auto-clean change detection message missing"
require_pattern 'make -j"$JOBS" \' \
  "make invocation missing jobs wiring"
require_pattern 'HAVE_PARALLEL="$HAVE_PARALLEL" \' \
  "make invocation missing HAVE_PARALLEL wiring"
require_pattern 'HAVE_PARALLEL_RSP="$HAVE_PARALLEL_RSP" \' \
  "make invocation missing HAVE_PARALLEL_RSP wiring"
require_pattern 'DEBUG="$MAKE_DEBUG" \' \
  "make invocation missing DEBUG wiring"
require_pattern '"${passthrough_args[@]}"' \
  "make passthrough args wiring missing"
require_pattern 'printf '\''%s\n'\'' "$BUILD_FINGERPRINT" > "$STATE_FILE"' \
  "build fingerprint state update missing"
require_pattern 'echo "[build] output: $SCRIPT_DIR/parallel_n64_libretro.so"' \
  "output path summary line missing"

echo "emu_build_runner_contract: PASS"
