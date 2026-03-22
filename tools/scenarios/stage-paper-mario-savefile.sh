#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

SOURCE_PATH="/home/auro/.config/retroarch/saves/ParaLLEl N64/Paper Mario (USA).srm"
OUTPUT_PATH="$REPO_ROOT/assets/savefiles/paper-mario-local/ParaLLEl N64/Paper Mario (USA).srm"

usage() {
  cat <<'EOF'
Usage:
  tools/scenarios/stage-paper-mario-savefile.sh [options]

Options:
  --source-path PATH  Source .srm to stage
  --output-path PATH  Destination path under gitignored assets
  -h, --help          Show this help

Notes:
  - This is an intentional staging helper for future Paper Mario fixtures.
  - It copies a local savefile into the repo's gitignored assets area and prints its SHA-256.
  - Tracked runtime scenarios should prefer an intentional staged savefile over an implicit global one.
EOF
}

while (($#)); do
  case "$1" in
    --source-path)
      shift
      SOURCE_PATH="${1:-}"
      if [[ -z "$SOURCE_PATH" ]]; then
        echo "--source-path requires a value." >&2
        exit 2
      fi
      ;;
    --output-path)
      shift
      OUTPUT_PATH="${1:-}"
      if [[ -z "$OUTPUT_PATH" ]]; then
        echo "--output-path requires a value." >&2
        exit 2
      fi
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

if [[ ! -f "$SOURCE_PATH" ]]; then
  echo "Source savefile not found: $SOURCE_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname -- "$OUTPUT_PATH")"
cp "$SOURCE_PATH" "$OUTPUT_PATH"

echo "[savefile] source: $SOURCE_PATH"
echo "[savefile] output: $OUTPUT_PATH"
echo "[savefile] sha256: $(scenario_sha256_file "$OUTPUT_PATH")"
