#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

CACHE_PATH="${PARALLEL_RDP_HIRES_CACHE_PATH:-}"
BUNDLE_ROOT=""
RUN_PROBES=1
INPUT_MASK=""
INPUT_SEQUENCE=""
INPUT_HOLD_FRAMES="1"
INPUT_REPEAT_COUNT="1"
INTER_PULSE_SETTLE_FRAMES="5"
POST_INPUT_SETTLE_FRAMES="20"
STEP_CHUNK_FRAMES="1"
PROBE_LABEL="selected-package-validation"

usage() {
  cat <<'USAGE'
Usage:
  tools/scenarios/paper-mario-file-select-selected-package-validation.sh [options]

Options:
  --cache-path PATH        Selected PHRB package to validate (defaults to env PARALLEL_RDP_HIRES_CACHE_PATH)
  --bundle-root PATH       Root directory for emitted legacy/selected probe bundles
  --input-mask HEX         Controller mask to pulse (example: 0x01)
  --input-sequence SPEC    Comma-separated pulse sequence overriding repeat mode
  --input-hold-frames N    Frames to hold each pulse (default: 1)
  --input-repeat-count N   Number of repeated pulses when using --input-mask (default: 1)
  --inter-pulse-settle N   Frames to settle between repeated pulses (default: 5)
  --post-input-settle N    Frames to settle after final pulse (default: 20)
  --step-chunk-frames N    Maximum frames per STEP_FRAME command (default: 1)
  --probe-label LABEL      Short label for bundle metadata
  --reuse                  Reuse existing bundles instead of rerunning probes
  -h, --help               Show this help
USAGE
}

while (($#)); do
  case "$1" in
    --cache-path)
      shift
      CACHE_PATH="${1:-}"
      ;;
    --bundle-root)
      shift
      BUNDLE_ROOT="${1:-}"
      ;;
    --input-mask)
      shift
      INPUT_MASK="${1:-}"
      ;;
    --input-sequence)
      shift
      INPUT_SEQUENCE="${1:-}"
      ;;
    --input-hold-frames)
      shift
      INPUT_HOLD_FRAMES="${1:-}"
      ;;
    --input-repeat-count)
      shift
      INPUT_REPEAT_COUNT="${1:-}"
      ;;
    --inter-pulse-settle)
      shift
      INTER_PULSE_SETTLE_FRAMES="${1:-}"
      ;;
    --post-input-settle)
      shift
      POST_INPUT_SETTLE_FRAMES="${1:-}"
      ;;
    --step-chunk-frames)
      shift
      STEP_CHUNK_FRAMES="${1:-}"
      ;;
    --probe-label)
      shift
      PROBE_LABEL="${1:-}"
      ;;
    --reuse)
      RUN_PROBES=0
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

if [[ -z "$CACHE_PATH" ]]; then
  echo "--cache-path or PARALLEL_RDP_HIRES_CACHE_PATH is required." >&2
  exit 2
fi
if [[ ! -f "$CACHE_PATH" ]]; then
  echo "Selected package not found: $CACHE_PATH" >&2
  exit 2
fi
if ! scenario_require_phrb_runtime_cache "$CACHE_PATH"; then
  exit 2
fi
if [[ -z "$INPUT_MASK" && -z "$INPUT_SEQUENCE" ]]; then
  echo "--input-mask or --input-sequence is required." >&2
  exit 2
fi

if [[ -z "$BUNDLE_ROOT" ]]; then
  BUNDLE_ROOT="$REPO_ROOT/artifacts/paper-mario-file-select-validation/$(date +"%Y%m%d-%H%M%S")-${PROBE_LABEL}"
fi
mkdir -p "$BUNDLE_ROOT/legacy" "$BUNDLE_ROOT/selected"

probe_args=(
  --mode on
  --probe-label "$PROBE_LABEL"
  --post-input-settle "$POST_INPUT_SETTLE_FRAMES"
  --step-chunk-frames "$STEP_CHUNK_FRAMES"
  --run
)
if [[ -n "$INPUT_SEQUENCE" ]]; then
  probe_args+=(--input-sequence "$INPUT_SEQUENCE")
else
  probe_args+=(
    --input-mask "$INPUT_MASK"
    --input-hold-frames "$INPUT_HOLD_FRAMES"
    --input-repeat-count "$INPUT_REPEAT_COUNT"
    --inter-pulse-settle "$INTER_PULSE_SETTLE_FRAMES"
  )
fi

legacy_bundle="$BUNDLE_ROOT/legacy"
selected_bundle="$BUNDLE_ROOT/selected"

if (( RUN_PROBES )); then
  tools/scenarios/paper-mario-file-select-input-probe.sh \
    "${probe_args[@]}" \
    --bundle-dir "$legacy_bundle"

  PARALLEL_RDP_HIRES_CACHE_PATH="$CACHE_PATH" \
  PARALLEL_RDP_HIRES_SAMPLED_OBJECT_LOOKUP=1 \
  tools/scenarios/paper-mario-file-select-input-probe.sh \
    "${probe_args[@]}" \
    --bundle-dir "$selected_bundle"
fi

if [[ ! -d "$legacy_bundle" || ! -d "$selected_bundle" ]]; then
  echo "Missing bundles under $BUNDLE_ROOT" >&2
  exit 1
fi

python3 - "$CACHE_PATH" "$BUNDLE_ROOT" <<'PY'
import hashlib
import json
import math
import sys
from pathlib import Path
from PIL import Image, ImageChops

cache_path = Path(sys.argv[1])
bundle_root = Path(sys.argv[2])
legacy_dir = bundle_root / 'legacy'
selected_dir = bundle_root / 'selected'

def one_capture(bundle_dir: Path):
    captures = sorted((bundle_dir / 'captures').glob('*.png'))
    if len(captures) != 1:
        raise SystemExit(f'expected exactly one capture in {bundle_dir}/captures, found {len(captures)}')
    return captures[0]

legacy_capture = one_capture(legacy_dir)
selected_capture = one_capture(selected_dir)
legacy_hash = hashlib.sha256(legacy_capture.read_bytes()).hexdigest()
selected_hash = hashlib.sha256(selected_capture.read_bytes()).hexdigest()

legacy_img = Image.open(legacy_capture).convert('RGBA')
selected_img = Image.open(selected_capture).convert('RGBA')
diff = ImageChops.difference(legacy_img, selected_img)
hist = diff.histogram()
total_abs = sum((i % 256) * v for i, v in enumerate(hist))
total_sq = sum(((i % 256) ** 2) * v for i, v in enumerate(hist))
count = legacy_img.size[0] * legacy_img.size[1] * 4

summary = {
    'cache_path': str(cache_path),
    'cache_sha256': hashlib.sha256(cache_path.read_bytes()).hexdigest(),
    'legacy_bundle': str(legacy_dir),
    'selected_bundle': str(selected_dir),
    'matches_legacy': legacy_hash == selected_hash,
    'legacy_hash': legacy_hash,
    'selected_hash': selected_hash,
    'ae': total_abs,
    'rmse': math.sqrt(total_sq / count),
    'legacy_semantic': json.loads((legacy_dir / 'traces' / 'paper-mario-game-status.json').read_text()),
    'selected_semantic': json.loads((selected_dir / 'traces' / 'paper-mario-game-status.json').read_text()),
    'selected_hires': json.loads((selected_dir / 'traces' / 'hires-evidence.json').read_text()),
  }

summary_path = bundle_root / 'validation-summary.json'
summary_path.write_text(json.dumps(summary, indent=2) + '\n')

legacy_pm = summary['legacy_semantic'].get('paper_mario_us', {})
selected_pm = summary['selected_semantic'].get('paper_mario_us', {})
selected_probe = summary['selected_hires'].get('sampled_object_probe', {})

md = [
    '# File-Select Selected-Package Validation',
    '',
    f'- Cache: `{cache_path}`',
    f'- Cache SHA-256: `{summary["cache_sha256"]}`',
    f'- Legacy bundle: [{legacy_dir.name}]({legacy_dir})',
    f'- Selected bundle: [{selected_dir.name}]({selected_dir})',
    f'- Matches legacy: `{str(summary["matches_legacy"]).lower()}`',
    f'- Legacy hash: `{legacy_hash}`',
    f'- Selected hash: `{selected_hash}`',
    f'- AE: `{summary["ae"]}`',
    f'- RMSE: `{summary["rmse"]}`',
    f'- Legacy semantic: `{legacy_pm.get("cur_game_mode", {}).get("init_symbol")}` / `{legacy_pm.get("cur_game_mode", {}).get("step_symbol")}`',
    f'- Selected semantic: `{selected_pm.get("cur_game_mode", {}).get("init_symbol")}` / `{selected_pm.get("cur_game_mode", {}).get("step_symbol")}`',
]
if 'sampled_object_probe' in summary['selected_hires']:
    md.extend([
        f'- Selected exact hits: `{selected_probe.get("exact_hit_count")}`',
        f'- Selected conflict misses: `{selected_probe.get("exact_conflict_miss_count")}`',
        f'- Selected unresolved misses: `{selected_probe.get("exact_unresolved_miss_count")}`',
        '',
    ])
else:
    md.extend([
        '- Selected exact hits: `n/a`',
        '- Selected conflict misses: `n/a`',
        '- Selected unresolved misses: `n/a`',
        '',
    ])

(bundle_root / 'validation-summary.md').write_text('\n'.join(md) + '\n')
print(summary_path)
print(bundle_root / 'validation-summary.md')
PY

echo "[validation] complete: $BUNDLE_ROOT"
