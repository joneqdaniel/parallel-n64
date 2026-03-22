#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
MANIFEST="$REPO_ROOT/tools/fixtures/paper-mario-hos-05-entry-3.yaml"
FIXTURE_ID="paper-mario-hos-05-entry-3"
MODE="off"
AUTHORITY_MODE="bootstrap"
DRY_RUN=1
BUNDLE_DIR=""

usage() {
  cat <<'EOF'
Usage:
  tools/scenarios/paper-mario-hos-05-entry-3.sh [options]

Options:
  --mode off|on       Evidence bundle mode label (default: off)
  --authority-mode bootstrap|authoritative|auto
                      Reserved for future runtime support (default: bootstrap)
  --bundle-dir PATH   Output bundle directory
  --run               Reserved; this fixture is not runnable yet
  -h, --help          Show this help
EOF
}

while (($#)); do
  case "$1" in
    --mode)
      shift
      MODE="${1:-}"
      if [[ "$MODE" != "off" && "$MODE" != "on" ]]; then
        echo "--mode must be 'off' or 'on'." >&2
        exit 2
      fi
      ;;
    --authority-mode)
      shift
      AUTHORITY_MODE="${1:-}"
      if [[ "$AUTHORITY_MODE" != "auto" && "$AUTHORITY_MODE" != "authoritative" && "$AUTHORITY_MODE" != "bootstrap" ]]; then
        echo "--authority-mode must be 'auto', 'authoritative', or 'bootstrap'." >&2
        exit 2
      fi
      ;;
    --bundle-dir)
      shift
      BUNDLE_DIR="${1:-}"
      if [[ -z "$BUNDLE_DIR" ]]; then
        echo "--bundle-dir requires a value." >&2
        exit 2
      fi
      ;;
    --run)
      DRY_RUN=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ -z "$BUNDLE_DIR" ]]; then
  BUNDLE_DIR="$(scenario_default_bundle_dir "$REPO_ROOT" "$FIXTURE_ID" "$MODE")"
fi

ROM_PATH="$REPO_ROOT/assets/Paper Mario (USA).zip"
PACK_PATH="$REPO_ROOT/assets/PAPER MARIO_HIRESTEXTURES.hts"
RETROARCH_PATH="/home/auro/code/RetroArch"
AUTHORITY_GRAPH_PATH="$REPO_ROOT/tools/fixtures/paper-mario-authority-graph.yaml"
AUTHORITY_NODE_ID="hos_05_entry_3_idle"
BOOTSTRAP_PARENT_FIXTURE_ID="paper-mario-file-select"
REMINT_SCRIPT="tools/scenarios/remint-paper-mario-hos-05-entry-3-authority.sh"

scenario_prepare_bundle_dirs "$BUNDLE_DIR"

cat > "$BUNDLE_DIR/bundle.json" <<EOF
{
  "fixture_id": "$FIXTURE_ID",
  "mode": "$MODE",
  "manifest_path": "$MANIFEST",
  "bundle_dir": "$BUNDLE_DIR",
  "created_at": "$(date -Iseconds)",
  "runtime_rules": {
    "internal_scale": "4x",
    "serial_execution": true,
    "display_required": true
  },
  "inputs": {
    "rom_path": "$ROM_PATH",
    "rom_sha256": "$(scenario_sha256_file "$ROM_PATH")",
    "hires_pack_path": "$PACK_PATH",
    "hires_pack_sha256": "$(scenario_sha256_file "$PACK_PATH")",
    "retroarch_path": "$RETROARCH_PATH"
  },
  "fixture_authority": {
    "authority_mode_requested": "$AUTHORITY_MODE",
    "authority_mode_used": "none",
    "authority_graph_path": "$AUTHORITY_GRAPH_PATH",
    "authority_node_id": "$AUTHORITY_NODE_ID",
    "bootstrap_parent_fixture_id": "$BOOTSTRAP_PARENT_FIXTURE_ID",
    "remint_script": "$REMINT_SCRIPT",
    "authoritative_state_path": "",
    "authoritative_state_present": false,
    "authoritative_state_sha256": "missing",
    "bootstrap_state_path": "",
    "bootstrap_state_present": false,
    "bootstrap_state_sha256": "missing",
    "active_state_path": "",
    "active_state_sha256": "missing",
    "post_load_settle_frames": 3
  },
  "status": {
    "phase": "phase-0",
    "scenario_state": "planned_fixture_scaffold",
    "runtime_executed": false
  }
}
EOF

cat > "$BUNDLE_DIR/config.env" <<EOF
FIXTURE_ID=$FIXTURE_ID
MODE=$MODE
MANIFEST_PATH=$MANIFEST
ROM_PATH=$ROM_PATH
HIRES_PACK_PATH=$PACK_PATH
RETROARCH_PATH=$RETROARCH_PATH
AUTHORITY_MODE_REQUESTED=$AUTHORITY_MODE
AUTHORITY_MODE_USED=none
AUTHORITY_GRAPH_PATH=$AUTHORITY_GRAPH_PATH
AUTHORITY_NODE_ID=$AUTHORITY_NODE_ID
BOOTSTRAP_PARENT_FIXTURE_ID=$BOOTSTRAP_PARENT_FIXTURE_ID
REMINT_SCRIPT=$REMINT_SCRIPT
AUTHORITATIVE_STATE_PATH=
AUTHORITATIVE_STATE_PRESENT=0
AUTHORITATIVE_STATE_SHA256=missing
BOOTSTRAP_STATE_PATH=
BOOTSTRAP_STATE_PRESENT=0
BOOTSTRAP_STATE_SHA256=missing
ACTIVE_STATE_PATH=
ACTIVE_STATE_SHA256=missing
POST_LOAD_SETTLE_FRAMES=3
INTERNAL_SCALE=4x
SERIAL_EXECUTION=1
DISPLAY_REQUIRED=1
EOF

cat > "$BUNDLE_DIR/README.md" <<EOF
# $FIXTURE_ID

- Mode: \`$MODE\`
- Manifest: [paper-mario-hos-05-entry-3.yaml]($MANIFEST)
- Internal scale: \`4x\`
- Execution rule: one emulator-facing run at a time
- Status: planned fixture scaffold

This bundle documents the next Paper Mario ladder target before its bootstrap
route or authoritative steady-state savestate exists.
EOF

scenario_print_header "$FIXTURE_ID" "$MODE" "$BUNDLE_DIR" "$MANIFEST"

if (( DRY_RUN )); then
  echo "[scenario] dry-run complete; this fixture is intentionally modeled before runtime implementation."
  exit 0
fi

echo "[scenario] runtime route for hos_05 ENTRY_3 is not implemented yet." >&2
echo "[scenario] define and verify the bootstrap path from file select before using --run." >&2
exit 1
