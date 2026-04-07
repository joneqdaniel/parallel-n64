#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

CACHE_PATH="${PARALLEL_RDP_HIRES_CACHE_PATH:-}"
BUNDLE_ROOT=""
STEP_LIST="960 1200 1500"
RUN_PROBES=1
LOADER_MANIFEST_PATH=""
TRANSPORT_REVIEW_PATH=""

usage() {
  cat <<'USAGE'
Usage:
  tools/scenarios/paper-mario-title-timeout-selected-package-validation.sh [options]

Options:
  --cache-path PATH     Selected PHRB package to validate (defaults to env PARALLEL_RDP_HIRES_CACHE_PATH)
  --bundle-root PATH    Root directory for emitted on/off probe bundles
  --loader-manifest PATH
                       Optional loader-manifest.json used to classify sampled families against the active package
  --transport-review PATH
                       Optional sampled transport review JSON used to classify whether legacy candidates exist
  --steps "..."        Space-separated timeout checkpoints (default: "960 1200 1500")
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
    --loader-manifest)
      shift
      LOADER_MANIFEST_PATH="${1:-}"
      ;;
    --transport-review)
      shift
      TRANSPORT_REVIEW_PATH="${1:-}"
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
if [[ -n "$LOADER_MANIFEST_PATH" && ! -f "$LOADER_MANIFEST_PATH" ]]; then
  echo "Loader manifest not found: $LOADER_MANIFEST_PATH" >&2
  exit 2
fi
if [[ -n "$TRANSPORT_REVIEW_PATH" && ! -f "$TRANSPORT_REVIEW_PATH" ]]; then
  echo "Transport review not found: $TRANSPORT_REVIEW_PATH" >&2
  exit 2
fi
if [[ -z "$BUNDLE_ROOT" ]]; then
  BUNDLE_ROOT="$REPO_ROOT/artifacts/paper-mario-probes/validation/$(date +"%Y%m%d-%H%M%S")-title-timeout-selected-package"
fi
mkdir -p "$BUNDLE_ROOT/on" "$BUNDLE_ROOT/off"

for step in $STEP_LIST; do
  on_bundle="$BUNDLE_ROOT/on/timeout-${step}"
  off_bundle="$BUNDLE_ROOT/off/timeout-${step}"
  if (( RUN_PROBES )); then
    DISABLE_SCREENSHOT_VERIFY=1 \
    tools/scenarios/paper-mario-title-timeout-probe.sh \
      --mode off \
      --step-frames "$step" \
      --step-chunk-frames "$step" \
      --probe-label "timeout-${step}-off-baseline" \
      --bundle-dir "$off_bundle" \
      --run

    PARALLEL_RDP_HIRES_CACHE_PATH="$CACHE_PATH" \
    PARALLEL_RDP_HIRES_SAMPLED_OBJECT_LOOKUP=1 \
    DISABLE_SCREENSHOT_VERIFY=1 \
    tools/scenarios/paper-mario-title-timeout-probe.sh \
      --mode on \
      --step-frames "$step" \
      --step-chunk-frames "$step" \
      --probe-label "timeout-${step}-selected-package" \
      --bundle-dir "$on_bundle" \
      --run
  fi
  if [[ ! -d "$on_bundle" || ! -d "$off_bundle" ]]; then
    echo "Missing bundles for step $step under $BUNDLE_ROOT" >&2
    exit 1
  fi
  if [[ -n "$LOADER_MANIFEST_PATH" || -n "$TRANSPORT_REVIEW_PATH" ]]; then
    review_cmd=(
      python3
      "$REPO_ROOT/tools/hires_sampled_selector_review.py"
      --bundle-dir "$on_bundle"
      --output "$on_bundle/traces/hires-sampled-selector-review.md"
      --output-json "$on_bundle/traces/hires-sampled-selector-review.json"
    )
    if [[ -n "$LOADER_MANIFEST_PATH" ]]; then
      review_cmd+=(--loader-manifest "$LOADER_MANIFEST_PATH")
    fi
    if [[ -n "$TRANSPORT_REVIEW_PATH" ]]; then
      review_cmd+=(--transport-review "$TRANSPORT_REVIEW_PATH")
    fi
    "${review_cmd[@]}"
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

for off_dir in sorted((bundle_root / 'off').iterdir()):
    if not off_dir.is_dir() or not off_dir.name.startswith('timeout-'):
        continue
    step = int(off_dir.name.split('-', 1)[1])
    on_dir = bundle_root / 'on' / off_dir.name
    off_capture, off_hash = capture_hash(off_dir)
    on_capture, on_hash = capture_hash(on_dir)

    off_img = Image.open(off_capture).convert('RGBA')
    on_img = Image.open(on_capture).convert('RGBA')
    diff = ImageChops.difference(off_img, on_img)
    hist = diff.histogram()
    total_abs = sum((i % 256) * v for i, v in enumerate(hist))
    total_sq = sum(((i % 256) ** 2) * v for i, v in enumerate(hist))
    count = off_img.size[0] * off_img.size[1] * 4

    on_semantic = json.loads((on_dir / 'traces' / 'paper-mario-game-status.json').read_text())
    on_hires = json.loads((on_dir / 'traces' / 'hires-evidence.json').read_text())
    hires_summary = on_hires.get('summary') or {}
    if hires_summary.get('provider') != 'on':
        raise SystemExit(f'expected on-bundle hi-res provider to be "on" in {on_dir}, found {hires_summary.get("provider")!r}')
    if hires_summary.get('source_mode') != 'phrb-only':
        raise SystemExit(f'expected selected-package source_mode=phrb-only in {on_dir}, found {hires_summary.get("source_mode")!r}')
    if int(hires_summary.get('native_sampled_entry_count') or 0) < 1:
        raise SystemExit(f'expected native sampled entries in {on_dir}, found {hires_summary.get("native_sampled_entry_count")!r}')
    if int((hires_summary.get('source_counts') or {}).get('phrb') or 0) < 1:
        raise SystemExit(f'expected PHRB-backed entries in {on_dir}, found {(hires_summary.get("source_counts") or {}).get("phrb")!r}')
    review_md = on_dir / 'traces' / 'hires-sampled-selector-review.md'
    review_json = on_dir / 'traces' / 'hires-sampled-selector-review.json'
    summary['steps'].append({
        'step_frames': step,
        'off_bundle': str(off_dir),
        'on_bundle': str(on_dir),
        'off_hash': off_hash,
        'on_hash': on_hash,
        'matches_off': off_hash == on_hash,
        'ae': total_abs,
        'rmse': math.sqrt(total_sq / count),
        'semantic': {
            'map_name_candidate': on_semantic.get('paper_mario_us', {}).get('game_status', {}).get('map_name_candidate'),
            'entry_id': on_semantic.get('paper_mario_us', {}).get('game_status', {}).get('entry_id'),
            'init_symbol': on_semantic.get('paper_mario_us', {}).get('cur_game_mode', {}).get('init_symbol'),
            'step_symbol': on_semantic.get('paper_mario_us', {}).get('cur_game_mode', {}).get('step_symbol'),
        },
        'hires_summary': hires_summary,
        'sampled_object_probe': {
            'exact_hit_count': on_hires.get('sampled_object_probe', {}).get('exact_hit_count'),
            'exact_miss_count': on_hires.get('sampled_object_probe', {}).get('exact_miss_count'),
            'exact_conflict_miss_count': on_hires.get('sampled_object_probe', {}).get('exact_conflict_miss_count'),
            'exact_unresolved_miss_count': on_hires.get('sampled_object_probe', {}).get('exact_unresolved_miss_count'),
            'top_exact_hit_buckets': on_hires.get('sampled_object_probe', {}).get('top_exact_hit_buckets', [])[:5],
            'top_exact_conflict_miss_buckets': on_hires.get('sampled_object_probe', {}).get('top_exact_conflict_miss_buckets', [])[:5],
            'top_exact_unresolved_miss_buckets': on_hires.get('sampled_object_probe', {}).get('top_exact_unresolved_miss_buckets', [])[:5],
        },
        'sampled_selector_review': {
            'markdown_path': str(review_md) if review_md.is_file() else None,
            'json_path': str(review_json) if review_json.is_file() else None,
        },
    })

summary_path = bundle_root / 'validation-summary.json'
summary_path.write_text(json.dumps(summary, indent=2) + '\n')
md = [
    '# Title Timeout Selected-Package Validation',
    '',
    f'- Cache: `{cache_path}`',
    f'- Cache SHA-256: `{summary["cache_sha256"]}`',
    '',
]
for step in summary['steps']:
    md.extend([
        f'## {step["step_frames"]} Frames',
        f'- On bundle: [{Path(step["on_bundle"]).name}]({step["on_bundle"]})',
        f'- Off bundle: [{Path(step["off_bundle"]).name}]({step["off_bundle"]})',
        f'- Matches off: `{str(step["matches_off"]).lower()}`',
        f'- On hash: `{step["on_hash"]}`',
        f'- Off hash: `{step["off_hash"]}`',
        f'- AE: `{step["ae"]}`',
        f'- RMSE: `{step["rmse"]}`',
        f'- Semantic: `{step["semantic"]["init_symbol"]}` / `{step["semantic"]["step_symbol"]}`, map `{step["semantic"]["map_name_candidate"]}`, entry `{step["semantic"]["entry_id"]}`',
    ])
    hires_summary = step.get('hires_summary') or {}
    summary_line = f'- Hi-res summary: provider `{hires_summary.get("provider")}`'
    if hires_summary.get('source_mode') is not None:
        summary_line += f', source mode `{hires_summary.get("source_mode")}`'
    if hires_summary.get('entry_count') is not None:
        summary_line += (
            f', entries `{hires_summary.get("entry_count")}`'
            f', native sampled `{hires_summary.get("native_sampled_entry_count")}`'
            f', compat `{hires_summary.get("compat_entry_count")}`'
            f', sampled families `{hires_summary.get("sampled_family_count")}`'
            f', source PHRB `{(hires_summary.get("source_counts") or {}).get("phrb")}`'
        )
    md.extend([
        summary_line,
        f'- Sampled exact hits: `{step["sampled_object_probe"]["exact_hit_count"]}`',
        f'- Sampled exact misses: `{step["sampled_object_probe"]["exact_miss_count"]}`',
        f'- Sampled conflict misses: `{step["sampled_object_probe"]["exact_conflict_miss_count"]}`',
        f'- Sampled unresolved misses: `{step["sampled_object_probe"]["exact_unresolved_miss_count"]}`',
    ])
    review_md = step.get('sampled_selector_review', {}).get('markdown_path')
    review_json = step.get('sampled_selector_review', {}).get('json_path')
    if review_md:
        md.append(f'- Sampled selector review: [{Path(review_md).name}]({review_md})')
    if review_json:
        md.append(f'- Sampled selector review JSON: [{Path(review_json).name}]({review_json})')
    md.append('')
(bundle_root / 'validation-summary.md').write_text('\n'.join(md) + '\n')
print(summary_path)
print(bundle_root / 'validation-summary.md')
PY

echo "[validation] complete: $BUNDLE_ROOT"
