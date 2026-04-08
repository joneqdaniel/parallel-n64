#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

LEGACY_CACHE_PATH="${REPO_ROOT}/assets/PAPER MARIO_HIRESTEXTURES.hts"
CONTEXT_SUMMARY_PATH="${REPO_ROOT}/artifacts/paper-mario-probes/validation/20260408-full-cache-phrb-authorities-authority-context-root-provenance-promoted-round2/validation-summary.json"
OUTPUT_DIR=""
BUNDLE_ROOT=""
REUSE_EXISTING=0

usage() {
  cat <<'USAGE'
Usage:
  tools/scenarios/paper-mario-full-cache-phrb-authority-refresh.sh [options]

Options:
  --legacy-cache PATH      Legacy `.hts` cache to convert
  --context-summary PATH   Validation summary used as authority context input
  --output-dir PATH        Converter output directory
  --bundle-root PATH       Validation bundle root
  --reuse-existing         Reuse a matching existing converter artifact when possible
  -h, --help               Show this help
USAGE
}

while (($#)); do
  case "$1" in
    --legacy-cache)
      shift
      LEGACY_CACHE_PATH="${1:-}"
      ;;
    --context-summary)
      shift
      CONTEXT_SUMMARY_PATH="${1:-}"
      ;;
    --output-dir)
      shift
      OUTPUT_DIR="${1:-}"
      ;;
    --bundle-root)
      shift
      BUNDLE_ROOT="${1:-}"
      ;;
    --reuse-existing)
      REUSE_EXISTING=1
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

if [[ ! -f "$LEGACY_CACHE_PATH" ]]; then
  echo "Legacy cache not found: $LEGACY_CACHE_PATH" >&2
  exit 2
fi

if [[ ! -f "$CONTEXT_SUMMARY_PATH" ]]; then
  echo "Context summary not found: $CONTEXT_SUMMARY_PATH" >&2
  exit 2
fi

if [[ -z "$OUTPUT_DIR" || -z "$BUNDLE_ROOT" ]]; then
  timestamp="$(date +"%Y%m%d-%H%M%S")"
  if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$REPO_ROOT/artifacts/hts2phrb-review/${timestamp}-pm64-all-families-authority-context-refresh"
  fi
  if [[ -z "$BUNDLE_ROOT" ]]; then
    BUNDLE_ROOT="$REPO_ROOT/artifacts/paper-mario-probes/validation/${timestamp}-full-cache-phrb-authorities-authority-context-refresh"
  fi
fi

declare -a converter_args
converter_args=(
  --cache "$LEGACY_CACHE_PATH"
  --context-bundle "$CONTEXT_SUMMARY_PATH"
  --minimum-outcome partial-runtime-package
  --expect-context-class context-enriched
  --expect-runtime-ready-class mixed-native-and-compat
  --output-dir "$OUTPUT_DIR"
  --stdout-format json
)

if (( REUSE_EXISTING )); then
  converter_args+=(--reuse-existing)
fi

python3 "$REPO_ROOT/tools/hts2phrb.py" "${converter_args[@]}" >/dev/null

PACKAGE_PATH="$OUTPUT_DIR/package.phrb"
REPORT_PATH="$OUTPUT_DIR/hts2phrb-report.json"
if [[ ! -f "$PACKAGE_PATH" ]]; then
  echo "Missing refreshed package: $PACKAGE_PATH" >&2
  exit 1
fi
if [[ ! -f "$REPORT_PATH" ]]; then
  echo "Missing converter report: $REPORT_PATH" >&2
  exit 1
fi

"$SCRIPT_DIR/paper-mario-full-cache-phrb-authority-validation.sh" \
  --cache-path "$PACKAGE_PATH" \
  --bundle-root "$BUNDLE_ROOT"

SUMMARY_PATH="$BUNDLE_ROOT/validation-summary.json"
if [[ ! -f "$SUMMARY_PATH" ]]; then
  echo "Missing authority validation summary: $SUMMARY_PATH" >&2
  exit 1
fi

echo "[refresh] converter report: $REPORT_PATH"
echo "[refresh] validation summary: $SUMMARY_PATH"
