#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

CACHE_PATH="${PARALLEL_RDP_HIRES_CACHE_PATH:-}"
BUNDLE_ROOT=""
STEP_LIST="960 1200 1500"
RUN_PROBES=1

usage() {
  cat <<'USAGE'
Usage:
  tools/scenarios/paper-mario-title-timeout-legacy-validation.sh [options]

Options:
  --cache-path PATH     Selected PHRB package to validate (defaults to env PARALLEL_RDP_HIRES_CACHE_PATH)
  --bundle-root PATH    Root directory for emitted legacy/selected probe bundles
  --steps "..."         Space-separated timeout checkpoints (default: "960 1200 1500")
  --reuse               Reuse existing bundles instead of rerunning probes
  -h, --help            Show this help
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
    --steps)
      shift
      STEP_LIST="${1:-}"
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

if [[ -z "$BUNDLE_ROOT" ]]; then
  BUNDLE_ROOT="$REPO_ROOT/artifacts/paper-mario-probes/validation/$(date +"%Y%m%d-%H%M%S")-title-timeout-legacy-vs-selected"
fi
mkdir -p "$BUNDLE_ROOT/legacy" "$BUNDLE_ROOT/selected"

for step in $STEP_LIST; do
  legacy_bundle="$BUNDLE_ROOT/legacy/timeout-${step}"
  selected_bundle="$BUNDLE_ROOT/selected/timeout-${step}"
  if (( RUN_PROBES )); then
    DISABLE_SCREENSHOT_VERIFY=1 \
    tools/scenarios/paper-mario-title-timeout-probe.sh \
      --mode on \
      --step-frames "$step" \
      --step-chunk-frames "$step" \
      --probe-label "timeout-${step}-legacy-hts" \
      --bundle-dir "$legacy_bundle" \
      --run

    PARALLEL_RDP_HIRES_CACHE_PATH="$CACHE_PATH" \
    PARALLEL_RDP_HIRES_SAMPLED_OBJECT_LOOKUP=1 \
    DISABLE_SCREENSHOT_VERIFY=1 \
    tools/scenarios/paper-mario-title-timeout-probe.sh \
      --mode on \
      --step-frames "$step" \
      --step-chunk-frames "$step" \
      --probe-label "timeout-${step}-selected-package" \
      --bundle-dir "$selected_bundle" \
      --run
  fi

  if [[ ! -d "$legacy_bundle" || ! -d "$selected_bundle" ]]; then
    echo "Missing bundles for step $step under $BUNDLE_ROOT" >&2
    exit 1
  fi
done

python3 - "$CACHE_PATH" "$BUNDLE_ROOT" <<'PY'
import hashlib
import json
import math
import sys
from pathlib import Path
from PIL import Image, ImageChops

cache_path = Path(sys.argv[1])
bundle_root = Path(sys.argv[2])
summary = {
    'cache_path': str(cache_path),
    'cache_sha256': hashlib.sha256(cache_path.read_bytes()).hexdigest(),
    'steps': [],
}

def capture_hash(bundle_dir: Path):
    captures = sorted((bundle_dir / 'captures').glob('*'))
    if len(captures) != 1:
        raise SystemExit(f'expected exactly one capture in {bundle_dir}/captures, found {len(captures)}')
    path = captures[0]
    return path, hashlib.sha256(path.read_bytes()).hexdigest()

for legacy_dir in sorted((bundle_root / 'legacy').iterdir()):
    if not legacy_dir.is_dir() or not legacy_dir.name.startswith('timeout-'):
        continue
    step = int(legacy_dir.name.split('-', 1)[1])
    selected_dir = bundle_root / 'selected' / legacy_dir.name
    legacy_capture, legacy_hash = capture_hash(legacy_dir)
    selected_capture, selected_hash = capture_hash(selected_dir)

    legacy_img = Image.open(legacy_capture).convert('RGBA')
    selected_img = Image.open(selected_capture).convert('RGBA')
    diff = ImageChops.difference(legacy_img, selected_img)
    hist = diff.histogram()
    total_abs = sum((i % 256) * v for i, v in enumerate(hist))
    total_sq = sum(((i % 256) ** 2) * v for i, v in enumerate(hist))
    count = legacy_img.size[0] * legacy_img.size[1] * 4

    legacy_hires = json.loads((legacy_dir / 'traces' / 'hires-evidence.json').read_text())
    selected_semantic = json.loads((selected_dir / 'traces' / 'paper-mario-game-status.json').read_text())
    selected_hires = json.loads((selected_dir / 'traces' / 'hires-evidence.json').read_text())
    legacy_summary = legacy_hires.get('summary') or {}
    selected_summary = selected_hires.get('summary') or {}
    legacy_source_mode = legacy_summary.get('source_mode')
    if int(legacy_summary.get('entry_count') or 0) < 1:
        raise SystemExit(f'legacy bundle {legacy_dir} did not load any hi-res entries')
    if legacy_source_mode not in ('legacy-only', 'mixed'):
        raise SystemExit(
            f'legacy bundle {legacy_dir} expected source_mode legacy-only/mixed, found {legacy_source_mode!r}'
        )
    selected_probe = selected_hires.get('sampled_object_probe', {})

    summary['steps'].append({
        'step_frames': step,
        'legacy_bundle': str(legacy_dir),
        'selected_bundle': str(selected_dir),
        'legacy_hires_summary': legacy_summary,
        'selected_hires_summary': selected_summary,
        'legacy_hash': legacy_hash,
        'selected_hash': selected_hash,
        'matches_legacy': legacy_hash == selected_hash,
        'ae': total_abs,
        'rmse': math.sqrt(total_sq / count),
        'semantic': {
            'map_name_candidate': selected_semantic.get('paper_mario_us', {}).get('game_status', {}).get('map_name_candidate'),
            'entry_id': selected_semantic.get('paper_mario_us', {}).get('game_status', {}).get('entry_id'),
            'init_symbol': selected_semantic.get('paper_mario_us', {}).get('cur_game_mode', {}).get('init_symbol'),
            'step_symbol': selected_semantic.get('paper_mario_us', {}).get('cur_game_mode', {}).get('step_symbol'),
        },
        'sampled_object_probe': {
            'exact_hit_count': selected_probe.get('exact_hit_count'),
            'exact_conflict_miss_count': selected_probe.get('exact_conflict_miss_count'),
            'exact_unresolved_miss_count': selected_probe.get('exact_unresolved_miss_count'),
            'top_exact_hit_buckets': selected_probe.get('top_exact_hit_buckets', [])[:5],
        },
    })

summary_path = bundle_root / 'validation-summary.json'
summary_path.write_text(json.dumps(summary, indent=2) + '\n')
md = [
    '# Title Timeout Legacy-vs-Selected Validation',
    '',
    f'- Cache: `{cache_path}`',
    f'- Cache SHA-256: `{summary["cache_sha256"]}`',
    '',
]
for step in summary['steps']:
    md.extend([
        f'## {step["step_frames"]} Frames',
        f'- Legacy bundle: [{Path(step["legacy_bundle"]).name}]({step["legacy_bundle"]})',
        f'- Selected bundle: [{Path(step["selected_bundle"]).name}]({step["selected_bundle"]})',
        f'- Matches legacy: `{str(step["matches_legacy"]).lower()}`',
        f'- Legacy hash: `{step["legacy_hash"]}`',
        f'- Selected hash: `{step["selected_hash"]}`',
        f'- Legacy hi-res source mode: `{step["legacy_hires_summary"].get("source_mode")}` with `{step["legacy_hires_summary"].get("entry_count")}` entries',
        f'- Selected hi-res source mode: `{step["selected_hires_summary"].get("source_mode")}` with `{step["selected_hires_summary"].get("entry_count")}` entries',
        f'- AE: `{step["ae"]}`',
        f'- RMSE: `{step["rmse"]}`',
        f'- Semantic: `{step["semantic"]["init_symbol"]}` / `{step["semantic"]["step_symbol"]}`, map `{step["semantic"]["map_name_candidate"]}`, entry `{step["semantic"]["entry_id"]}`',
        f'- Selected exact hits: `{step["sampled_object_probe"]["exact_hit_count"]}`',
        f'- Selected conflict misses: `{step["sampled_object_probe"]["exact_conflict_miss_count"]}`',
        f'- Selected unresolved misses: `{step["sampled_object_probe"]["exact_unresolved_miss_count"]}`',
        '',
    ])
(bundle_root / 'validation-summary.md').write_text('\n'.join(md) + '\n')
print(summary_path)
print(bundle_root / 'validation-summary.md')
PY

echo "[validation] complete: $BUNDLE_ROOT"
