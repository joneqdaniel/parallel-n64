#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$REPO_ROOT/tools/fixtures/paper-mario-title-screen.yaml"
FIXTURE_ID="paper-mario-title-screen"
MODE="off"
DRY_RUN=1
BUNDLE_DIR=""

usage() {
  cat <<'EOF'
Usage:
  tools/scenarios/paper-mario-title-screen.sh [options]

Options:
  --mode off|on       Evidence bundle mode label (default: off)
  --bundle-dir PATH   Output bundle directory
  --run               Reserve bundle and continue toward runtime execution
  -h, --help          Show this help

Notes:
  - This scenario is Phase 0 scaffolding for the first strict Paper Mario fixture.
  - Emulator-facing runs are expected at 4x internal scale and one at a time.
  - The current script prepares a reproducible evidence bundle and environment summary.
EOF
}

sha256_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "missing"
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    shasum -a 256 "$path" | awk '{print $1}'
  fi
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
  timestamp="$(date +"%Y%m%d-%H%M%S")"
  BUNDLE_DIR="$REPO_ROOT/artifacts/$FIXTURE_ID/$MODE/$timestamp"
fi

ROM_PATH="$REPO_ROOT/assets/Paper Mario (USA).zip"
PACK_PATH="$REPO_ROOT/assets/PAPER MARIO_HIRESTEXTURES.hts"
RETROARCH_PATH="/home/auro/code/RetroArch"

mkdir -p "$BUNDLE_DIR"/captures "$BUNDLE_DIR"/logs "$BUNDLE_DIR"/traces

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
    "rom_sha256": "$(sha256_file "$ROM_PATH")",
    "hires_pack_path": "$PACK_PATH",
    "hires_pack_sha256": "$(sha256_file "$PACK_PATH")",
    "retroarch_path": "$RETROARCH_PATH"
  },
  "status": {
    "phase": "phase-0",
    "scenario_state": "bundle_initialized",
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
INTERNAL_SCALE=4x
SERIAL_EXECUTION=1
DISPLAY_REQUIRED=1
EOF

cat > "$BUNDLE_DIR/README.md" <<EOF
# $FIXTURE_ID

- Mode: \`$MODE\`
- Manifest: [paper-mario-title-screen.yaml]($MANIFEST)
- Internal scale: \`4x\`
- Execution rule: one emulator-facing run at a time
- Status: bundle initialized

This bundle is a Phase 0 scaffold.
Populate \`captures/\`, \`logs/\`, and \`traces/\` as runtime control and capture paths are wired in.
EOF

echo "[scenario] fixture: $FIXTURE_ID"
echo "[scenario] mode: $MODE"
echo "[scenario] bundle: $BUNDLE_DIR"
echo "[scenario] manifest: $MANIFEST"
echo "[scenario] internal scale: 4x"
echo "[scenario] execution: serial"

if (( DRY_RUN )); then
  echo "[scenario] dry-run complete; runtime launch is intentionally deferred."
else
  echo "[scenario] bundle prepared for runtime execution."
  echo "[scenario] next step: wire RetroArch control/capture into this scenario."
fi
