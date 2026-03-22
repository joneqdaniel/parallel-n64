#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  tools/scenarios/remint-paper-mario-hos-05-entry-3-authority.sh

Status:
  This remint helper is intentionally a placeholder.

Next work required:
  - define the deterministic route from the file-select authority to hos_05 ENTRY_3
  - verify that route with repeatable controller input and evidence bundles
  - mint an authoritative steady-state savestate
  - verify the canonical `load -> settle 3 -> capture` hash before promoting the state
EOF
}

case "${1:-}" in
  -h|--help|"")
    usage
    ;;
  *)
    echo "Unknown option: $1" >&2
    usage >&2
    exit 2
    ;;
esac

echo "[remint] hos_05 ENTRY_3 authority remint is not implemented yet." >&2
exit 1
