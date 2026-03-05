#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-normal}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
DUMP_DIR="${RDP_DUMP_CORPUS_DIR:-$REPO_ROOT/tests/rdp_dumps}"

if [[ -n "${RDP_VALIDATE_DUMP_BIN:-}" ]]; then
  VALIDATOR="$RDP_VALIDATE_DUMP_BIN"
else
  VALIDATOR="$(command -v rdp-validate-dump || true)"
fi

if [[ -z "$VALIDATOR" || ! -x "$VALIDATOR" ]]; then
  echo "SKIP: rdp-validate-dump not found. Set RDP_VALIDATE_DUMP_BIN to override."
  exit 77
fi

if [[ ! -d "$DUMP_DIR" ]]; then
  echo "SKIP: dump corpus directory not found: $DUMP_DIR"
  exit 77
fi

mapfile -t dumps < <(find "$DUMP_DIR" -maxdepth 1 -type f -name '*.rdp' | sort)
if [[ ${#dumps[@]} -eq 0 ]]; then
  echo "SKIP: no .rdp dumps found in $DUMP_DIR"
  exit 77
fi

extra_args=()
case "$MODE" in
  normal)
    ;;
  sync-only)
    extra_args+=(--sync-only)
    ;;
  *)
    echo "FAIL: unknown mode '$MODE' (expected normal|sync-only)" >&2
    exit 2
    ;;
esac

for dump in "${dumps[@]}"; do
  echo "[emu.dump] validating: $dump (mode=$MODE)"
  "$VALIDATOR" "$dump" "${extra_args[@]}"
done

echo "emu_dump_validate: PASS (${#dumps[@]} dumps, mode=$MODE)"
