#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
RUNNER="$REPO_ROOT/tools/scenarios/paper-mario-full-cache-phrb-zero-config-refresh.sh"

if [[ ! -f "$RUNNER" ]]; then
  echo "FAIL: missing paper-mario-full-cache-phrb-zero-config-refresh.sh at $RUNNER" >&2
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

require_pattern 'python3 "$REPO_ROOT/tools/hts2phrb.py" "${converter_args[@]}" >/dev/null' \
  "full-cache zero-config refresh scenario should regenerate the PHRB through hts2phrb"
require_pattern '--minimum-outcome partial-runtime-package' \
  "full-cache zero-config refresh scenario should require partial-runtime-package output"
require_pattern '--expect-context-class zero-context' \
  "full-cache zero-config refresh scenario should require the zero-context converter class"
require_pattern '--expect-runtime-ready-class compat-only' \
  "full-cache zero-config refresh scenario should require the compat-only runtime-ready class"
require_pattern '"$SCRIPT_DIR/paper-mario-full-cache-phrb-authority-validation.sh" \' \
  "full-cache zero-config refresh scenario should validate the regenerated PHRB through the shared full-cache authority runner"
require_pattern '--reuse-existing' \
  "full-cache zero-config refresh scenario should expose reuse-existing support for repeat runs"

echo "emu_paper_mario_full_cache_phrb_zero_config_refresh_contract: PASS"
