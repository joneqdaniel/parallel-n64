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
ALT_SOURCE_CACHE_PATH=""
CROSS_SCENE_GUARD_EVIDENCE=()
PACKAGE_MANIFEST_PATH=""
POOL_REGRESSION_SAMPLE_LOW32="1b8530fb"
POOL_REGRESSION_FLAT_SUMMARY=""
POOL_REGRESSION_DUAL_SUMMARY=""
POOL_REGRESSION_ORDERED_SUMMARY=""
POOL_REGRESSION_SURFACE_PACKAGE=""

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
  --alternate-source-cache PATH
                       Optional legacy cache used to seed review-only alternate-source candidates
                       for candidate-free sampled families
  --package-manifest PATH
                       Optional selected package-manifest.json used to review duplicate families
  --cross-scene-guard-evidence LABEL=PATH
                       Optional guard-scene hires-evidence.json used to check whether
                       candidate-free families are still cross-scene shared before promotion.
                       Pass multiple times.
  --pool-regression-sampled-low32 HEX
                       sampled_low32 family for optional historical pool regression review
                       (default: 1b8530fb)
  --pool-regression-flat-summary PATH
                       Optional historical flat validation-summary.json for the pool regression review
  --pool-regression-dual-summary PATH
                       Optional historical flat+surface validation-summary.json for the pool regression review
  --pool-regression-ordered-summary PATH
                       Optional historical ordered-only validation-summary.json for the pool regression review
  --pool-regression-surface-package PATH
                       Optional historical surface-package.json for the pool regression review
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
    --alternate-source-cache)
      shift
      ALT_SOURCE_CACHE_PATH="${1:-}"
      ;;
    --package-manifest)
      shift
      PACKAGE_MANIFEST_PATH="${1:-}"
      ;;
    --cross-scene-guard-evidence)
      shift
      CROSS_SCENE_GUARD_EVIDENCE+=("${1:-}")
      ;;
    --pool-regression-sampled-low32)
      shift
      POOL_REGRESSION_SAMPLE_LOW32="${1:-}"
      ;;
    --pool-regression-flat-summary)
      shift
      POOL_REGRESSION_FLAT_SUMMARY="${1:-}"
      ;;
    --pool-regression-dual-summary)
      shift
      POOL_REGRESSION_DUAL_SUMMARY="${1:-}"
      ;;
    --pool-regression-ordered-summary)
      shift
      POOL_REGRESSION_ORDERED_SUMMARY="${1:-}"
      ;;
    --pool-regression-surface-package)
      shift
      POOL_REGRESSION_SURFACE_PACKAGE="${1:-}"
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
if [[ -n "$ALT_SOURCE_CACHE_PATH" && ! -f "$ALT_SOURCE_CACHE_PATH" ]]; then
  echo "Alternate-source cache not found: $ALT_SOURCE_CACHE_PATH" >&2
  exit 2
fi
if [[ -n "$PACKAGE_MANIFEST_PATH" && ! -f "$PACKAGE_MANIFEST_PATH" ]]; then
  echo "Package manifest not found: $PACKAGE_MANIFEST_PATH" >&2
  exit 2
fi
for required_path in \
  "$POOL_REGRESSION_FLAT_SUMMARY" \
  "$POOL_REGRESSION_DUAL_SUMMARY" \
  "$POOL_REGRESSION_ORDERED_SUMMARY" \
  "$POOL_REGRESSION_SURFACE_PACKAGE"; do
  if [[ -n "$required_path" && ! -f "$required_path" ]]; then
    echo "Pool regression input not found: $required_path" >&2
    exit 2
  fi
done
for labeled_path in "${CROSS_SCENE_GUARD_EVIDENCE[@]}"; do
  if [[ "$labeled_path" != *=* ]]; then
    echo "Expected LABEL=PATH for --cross-scene-guard-evidence, got: $labeled_path" >&2
    exit 2
  fi
  guard_path="${labeled_path#*=}"
  if [[ ! -f "$guard_path" ]]; then
    echo "Cross-scene guard evidence not found: $guard_path" >&2
    exit 2
  fi
done
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
    PARALLEL_RDP_HIRES_RUNTIME_SOURCE_MODE="${PARALLEL_RDP_HIRES_RUNTIME_SOURCE_MODE:-phrb-only}" \
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

    if [[ -n "$TRANSPORT_REVIEW_PATH" && -f "$on_bundle/traces/hires-sampled-selector-review.json" ]]; then
      if python3 - "$on_bundle/traces/hires-sampled-selector-review.json" "$POOL_REGRESSION_SAMPLE_LOW32" <<'PY'
import json
import sys
from pathlib import Path

review = json.loads(Path(sys.argv[1]).read_text())
target = str(sys.argv[2]).lower()
for row in review.get("pool_families", []):
    if str(row.get("sampled_low32") or "").lower() == target:
        raise SystemExit(0)
raise SystemExit(1)
PY
      then
        python3 "$REPO_ROOT/tools/hires_sampled_pool_review.py" \
          --bundle-dir "$on_bundle" \
          --selector-review "$on_bundle/traces/hires-sampled-selector-review.json" \
          --transport-review "$TRANSPORT_REVIEW_PATH" \
          --sampled-low32 "$POOL_REGRESSION_SAMPLE_LOW32" \
          --allow-missing-draw-sequence \
          --output "$on_bundle/traces/hires-sampled-pool-review-${POOL_REGRESSION_SAMPLE_LOW32}.md" \
          --output-json "$on_bundle/traces/hires-sampled-pool-review-${POOL_REGRESSION_SAMPLE_LOW32}.json"
      fi
    fi

    if [[ -n "$TRANSPORT_REVIEW_PATH" && -n "$ALT_SOURCE_CACHE_PATH" && -f "$on_bundle/traces/hires-sampled-selector-review.json" ]]; then
      python3 "$REPO_ROOT/tools/hires_seed_alternate_source_review.py" \
        --review "$TRANSPORT_REVIEW_PATH" \
        --selector-review "$on_bundle/traces/hires-sampled-selector-review.json" \
        --cache "$ALT_SOURCE_CACHE_PATH" \
        --output-json "$on_bundle/traces/hires-alternate-source-review.json" \
        --output-markdown "$on_bundle/traces/hires-alternate-source-review.md"
    fi

    if [[ ${#CROSS_SCENE_GUARD_EVIDENCE[@]} -gt 0 && -f "$on_bundle/traces/hires-sampled-selector-review.json" ]]; then
      mapfile -t cross_scene_families < <(
        python3 - "$on_bundle/traces/hires-sampled-selector-review.json" <<'PY'
import json
import sys
from pathlib import Path

review = json.loads(Path(sys.argv[1]).read_text())
seen = set()
for row in review.get("unresolved", []):
    if row.get("package_status") != "absent-from-package":
        continue
    if row.get("transport_status") != "legacy-transport-candidate-free":
        continue
    sampled_low32 = str(row.get("sampled_low32") or "").lower()
    if not sampled_low32 or sampled_low32 in seen:
        continue
    seen.add(sampled_low32)
    print(sampled_low32)
PY
      )
      if [[ ${#cross_scene_families[@]} -gt 0 ]]; then
        cross_scene_cmd=(
          python3
          "$REPO_ROOT/tools/hires_sampled_cross_scene_review.py"
          --evidence "timeout=$on_bundle/traces/hires-evidence.json"
          --target-label timeout
          --output-json "$on_bundle/traces/hires-sampled-cross-scene-review.json"
          --output-markdown "$on_bundle/traces/hires-sampled-cross-scene-review.md"
        )
        for labeled_path in "${CROSS_SCENE_GUARD_EVIDENCE[@]}"; do
          cross_scene_cmd+=(--evidence "$labeled_path")
          cross_scene_cmd+=(--guard-label "${labeled_path%%=*}")
        done
        for sampled_low32 in "${cross_scene_families[@]}"; do
          cross_scene_cmd+=(--sampled-low32 "$sampled_low32")
        done
        "${cross_scene_cmd[@]}"
      fi
    fi

    if [[ -f "$on_bundle/traces/hires-alternate-source-review.json" && -f "$on_bundle/traces/hires-sampled-cross-scene-review.json" ]]; then
      python3 "$REPO_ROOT/tools/hires_alternate_source_activation_review.py" \
        --alternate-source-review "$on_bundle/traces/hires-alternate-source-review.json" \
        --cross-scene-review "$on_bundle/traces/hires-sampled-cross-scene-review.json" \
        --output-json "$on_bundle/traces/hires-alternate-source-activation-review.json" \
        --output-markdown "$on_bundle/traces/hires-alternate-source-activation-review.md"
    fi

    if [[ -f "$on_bundle/traces/hires-sampled-selector-review.json" ]]; then
      seam_cmd=(
        python3
        "$REPO_ROOT/tools/hires_runtime_seam_register.py"
        --bundle-dir "$on_bundle"
        --selector-review "$on_bundle/traces/hires-sampled-selector-review.json"
        --output "$on_bundle/traces/hires-runtime-seam-register.md"
        --output-json "$on_bundle/traces/hires-runtime-seam-register.json"
      )
      if [[ -f "$on_bundle/traces/hires-alternate-source-review.json" ]]; then
        seam_cmd+=(--alternate-source-review "$on_bundle/traces/hires-alternate-source-review.json")
      fi
      if [[ -f "$on_bundle/traces/hires-sampled-cross-scene-review.json" ]]; then
        seam_cmd+=(--cross-scene-review "$on_bundle/traces/hires-sampled-cross-scene-review.json")
      fi
      if [[ -f "$on_bundle/traces/hires-alternate-source-activation-review.json" ]]; then
        seam_cmd+=(--alternate-source-activation-review "$on_bundle/traces/hires-alternate-source-activation-review.json")
      fi
      "${seam_cmd[@]}"
    fi

    if [[ -n "$PACKAGE_MANIFEST_PATH" && -f "$on_bundle/traces/hires-runtime-seam-register.json" ]]; then
      while IFS=$'\t' read -r sampled_low32 selector; do
        [[ -n "$sampled_low32" ]] || continue
        python3 "$REPO_ROOT/tools/hires_sampled_duplicate_review.py" \
          --runtime-seam-register "$on_bundle/traces/hires-runtime-seam-register.json" \
          --package-manifest "$PACKAGE_MANIFEST_PATH" \
          --sampled-low32 "$sampled_low32" \
          --selector "$selector" \
          --output "$on_bundle/traces/hires-sampled-duplicate-review-${sampled_low32}.md" \
          --output-json "$on_bundle/traces/hires-sampled-duplicate-review-${sampled_low32}.json"
      done < <(
        python3 - "$on_bundle/traces/hires-runtime-seam-register.json" <<'PY'
import json
import sys
from pathlib import Path

register = json.loads(Path(sys.argv[1]).read_text())
for row in register.get("sampled_duplicate_families", []):
    sampled_low32 = str(row.get("sampled_low32") or "").lower()
    selector = str(row.get("selector") or "").lower()
    if not sampled_low32 or not selector:
        continue
    print(f"{sampled_low32}\t{selector}")
PY
      )
    fi

    if [[ -n "$POOL_REGRESSION_FLAT_SUMMARY" && -n "$POOL_REGRESSION_DUAL_SUMMARY" && -n "$POOL_REGRESSION_ORDERED_SUMMARY" && -n "$POOL_REGRESSION_SURFACE_PACKAGE" ]]; then
      pool_regression_review_json="$on_bundle/traces/hires-sampled-pool-regression-review-${POOL_REGRESSION_SAMPLE_LOW32}.json"
      pool_regression_review_md="$on_bundle/traces/hires-sampled-pool-regression-review-${POOL_REGRESSION_SAMPLE_LOW32}.md"
      live_pool_review_json="$on_bundle/traces/hires-sampled-pool-review-${POOL_REGRESSION_SAMPLE_LOW32}.json"
      if [[ -f "$live_pool_review_json" ]]; then
        python3 "$REPO_ROOT/tools/hires_pool_regression_review.py" \
          --sampled-low32 "$POOL_REGRESSION_SAMPLE_LOW32" \
          --flat-summary "$POOL_REGRESSION_FLAT_SUMMARY" \
          --dual-summary "$POOL_REGRESSION_DUAL_SUMMARY" \
          --ordered-summary "$POOL_REGRESSION_ORDERED_SUMMARY" \
          --surface-package "$POOL_REGRESSION_SURFACE_PACKAGE" \
          --live-pool-review "$live_pool_review_json" \
          --output "$pool_regression_review_md" \
          --output-json "$pool_regression_review_json"
      fi
    fi
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
    if hires_summary.get('source_policy') != 'phrb-only':
        raise SystemExit(f'expected selected-package source_policy=phrb-only in {on_dir}, found {hires_summary.get("source_policy")!r}')
    if int(hires_summary.get('native_sampled_entry_count') or 0) < 1:
        raise SystemExit(f'expected native sampled entries in {on_dir}, found {hires_summary.get("native_sampled_entry_count")!r}')
    if int((hires_summary.get('source_counts') or {}).get('phrb') or 0) < 1:
        raise SystemExit(f'expected PHRB-backed entries in {on_dir}, found {(hires_summary.get("source_counts") or {}).get("phrb")!r}')
    review_md = on_dir / 'traces' / 'hires-sampled-selector-review.md'
    review_json = on_dir / 'traces' / 'hires-sampled-selector-review.json'
    alternate_source_review_json = on_dir / 'traces' / 'hires-alternate-source-review.json'
    alternate_source_activation_review_json = on_dir / 'traces' / 'hires-alternate-source-activation-review.json'
    cross_scene_review_json = on_dir / 'traces' / 'hires-sampled-cross-scene-review.json'
    seam_register_json = on_dir / 'traces' / 'hires-runtime-seam-register.json'
    pool_regression_review_json = next(iter(sorted((on_dir / 'traces').glob('hires-sampled-pool-regression-review-*.json'))), None)
    alternate_source_review_data = {}
    if alternate_source_review_json.is_file():
        alternate_source_review_data = json.loads(alternate_source_review_json.read_text())
    cross_scene_review_data = {}
    if cross_scene_review_json.is_file():
        cross_scene_review_data = json.loads(cross_scene_review_json.read_text())
    alternate_source_activation_review_data = {}
    if alternate_source_activation_review_json.is_file():
        alternate_source_activation_review_data = json.loads(alternate_source_activation_review_json.read_text())
    seam_register_data = {}
    if seam_register_json.is_file():
        seam_register_data = json.loads(seam_register_json.read_text())
    pool_regression_review_data = {}
    if pool_regression_review_json and pool_regression_review_json.is_file():
        pool_regression_review_data = json.loads(pool_regression_review_json.read_text())
    pool_reviews = []
    duplicate_reviews = []
    for pool_json in sorted((on_dir / 'traces').glob('hires-sampled-pool-review-*.json')):
        pool_review = json.loads(pool_json.read_text())
        pool_md = pool_json.with_suffix('.md')
        pool_reviews.append({
            'sampled_low32': pool_review.get('sampled_low32'),
            'review_status': pool_review.get('review_status') or 'complete',
            'pool_recommendation': pool_review.get('pool_recommendation'),
            'runtime_shape_recommendation': pool_review.get('runtime_shape_recommendation'),
            'runtime_sample_replacement_id': pool_review.get('runtime_sample_replacement_id'),
            'runtime_sample_policy': pool_review.get('runtime_sample_policy'),
            'json_path': str(pool_json),
            'markdown_path': str(pool_md) if pool_md.is_file() else None,
        })
    for duplicate_json in sorted((on_dir / 'traces').glob('hires-sampled-duplicate-review-*.json')):
        duplicate_review = json.loads(duplicate_json.read_text())
        duplicate_md = duplicate_json.with_suffix('.md')
        duplicate_reviews.append({
            'sampled_low32': duplicate_review.get('sampled_low32'),
            'selector': duplicate_review.get('selector'),
            'recommendation': duplicate_review.get('recommendation'),
            'active_replacement_id': (duplicate_review.get('duplicate_bucket') or {}).get('replacement_id'),
            'selector_candidate_count': duplicate_review.get('selector_candidate_count'),
            'unique_selector_pixel_hash_count': len(duplicate_review.get('unique_selector_pixel_hashes') or []),
            'broader_alias_replacement_ids': duplicate_review.get('broader_alias_replacement_ids') or [],
            'json_path': str(duplicate_json),
            'markdown_path': str(duplicate_md) if duplicate_md.is_file() else None,
        })
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
        'descriptor_path_counts': hires_summary.get('descriptor_path_counts') or {},
        'sampled_object_probe': {
            'exact_hit_count': on_hires.get('sampled_object_probe', {}).get('exact_hit_count'),
            'exact_miss_count': on_hires.get('sampled_object_probe', {}).get('exact_miss_count'),
            'exact_conflict_miss_count': on_hires.get('sampled_object_probe', {}).get('exact_conflict_miss_count'),
            'exact_unresolved_miss_count': on_hires.get('sampled_object_probe', {}).get('exact_unresolved_miss_count'),
            'top_exact_hit_buckets': on_hires.get('sampled_object_probe', {}).get('top_exact_hit_buckets', [])[:5],
            'top_exact_conflict_miss_buckets': on_hires.get('sampled_object_probe', {}).get('top_exact_conflict_miss_buckets', [])[:5],
            'top_exact_unresolved_miss_buckets': on_hires.get('sampled_object_probe', {}).get('top_exact_unresolved_miss_buckets', [])[:5],
        },
        'sampled_duplicate_probe': {
            'line_count': on_hires.get('sampled_duplicate_probe', {}).get('line_count'),
            'unique_bucket_count': on_hires.get('sampled_duplicate_probe', {}).get('unique_bucket_count'),
            'top_buckets': on_hires.get('sampled_duplicate_probe', {}).get('top_buckets', [])[:5],
        },
        'sampled_pool_stream_probe': {
            'line_count': on_hires.get('sampled_pool_stream_probe', {}).get('line_count'),
            'family_count': on_hires.get('sampled_pool_stream_probe', {}).get('family_count'),
            'top_families': on_hires.get('sampled_pool_stream_probe', {}).get('top_families', [])[:5],
        },
        'sampled_selector_review': {
            'markdown_path': str(review_md) if review_md.is_file() else None,
            'json_path': str(review_json) if review_json.is_file() else None,
        },
        'runtime_seam_register': {
            'markdown_path': str(on_dir / 'traces' / 'hires-runtime-seam-register.md') if (on_dir / 'traces' / 'hires-runtime-seam-register.md').is_file() else None,
            'json_path': str(seam_register_json) if seam_register_json.is_file() else None,
            'summary': seam_register_data.get('summary') or {},
            'pool_conflict_families': (seam_register_data.get('pool_conflict_families') or [])[:5],
            'sampled_duplicate_families': (seam_register_data.get('sampled_duplicate_families') or [])[:5],
        },
        'alternate_source_review': {
            'markdown_path': str(on_dir / 'traces' / 'hires-alternate-source-review.md') if (on_dir / 'traces' / 'hires-alternate-source-review.md').is_file() else None,
            'json_path': str(alternate_source_review_json) if alternate_source_review_json.is_file() else None,
            'group_count': alternate_source_review_data.get('group_count'),
            'available_group_count': alternate_source_review_data.get('available_group_count'),
            'total_candidate_count': alternate_source_review_data.get('total_candidate_count'),
            'groups': [
                {
                    'sampled_low32': (group.get('signature') or {}).get('sampled_low32'),
                    'status': group.get('alternate_source_status'),
                    'seed_dimensions': (group.get('seeded_transport_pool') or {}).get('seed_dimensions'),
                    'candidate_count': (group.get('seeded_transport_pool') or {}).get('candidate_count'),
                }
                for group in (alternate_source_review_data.get('groups') or [])[:5]
            ],
        },
        'alternate_source_activation_review': {
            'markdown_path': str(on_dir / 'traces' / 'hires-alternate-source-activation-review.md') if (on_dir / 'traces' / 'hires-alternate-source-activation-review.md').is_file() else None,
            'json_path': str(alternate_source_activation_review_json) if alternate_source_activation_review_json.is_file() else None,
            'summary': alternate_source_activation_review_data.get('summary') or {},
            'families': [
                {
                    'sampled_low32': family.get('sampled_low32'),
                    'activation_status': family.get('activation_status'),
                    'activation_recommendation': family.get('activation_recommendation'),
                    'candidate_count': family.get('candidate_count'),
                    'cross_scene_promotion_status': family.get('cross_scene_promotion_status'),
                }
                for family in (alternate_source_activation_review_data.get('families') or [])[:5]
            ],
        },
        'sampled_cross_scene_review': {
            'markdown_path': str(on_dir / 'traces' / 'hires-sampled-cross-scene-review.md') if (on_dir / 'traces' / 'hires-sampled-cross-scene-review.md').is_file() else None,
            'json_path': str(cross_scene_review_json) if cross_scene_review_json.is_file() else None,
            'target_labels': cross_scene_review_data.get('target_labels') or [],
            'guard_labels': cross_scene_review_data.get('guard_labels') or [],
            'families': [
                {
                    'sampled_low32': family.get('sampled_low32'),
                    'promotion_status': family.get('promotion_status'),
                    'shared_signature_count': family.get('shared_signature_count'),
                    'target_exclusive_signature_count': family.get('target_exclusive_signature_count'),
                    'shared_guard_labels': family.get('shared_guard_labels') or [],
                    'guard_labels_without_observation': family.get('guard_labels_without_observation') or [],
                }
                for family in (cross_scene_review_data.get('families') or [])[:5]
            ],
        },
        'sampled_pool_reviews': pool_reviews,
        'sampled_duplicate_reviews': duplicate_reviews,
        'sampled_pool_regression_review': {
            'markdown_path': str(pool_regression_review_json.with_suffix('.md')) if pool_regression_review_json and pool_regression_review_json.with_suffix('.md').is_file() else None,
            'json_path': str(pool_regression_review_json) if pool_regression_review_json and pool_regression_review_json.is_file() else None,
            'sampled_low32': pool_regression_review_data.get('sampled_low32'),
            'recommendation': (pool_regression_review_data.get('recommendation') or {}).get('recommendation'),
            'pool_follow_up': (pool_regression_review_data.get('recommendation') or {}).get('pool_follow_up'),
            'reasons': ((pool_regression_review_data.get('recommendation') or {}).get('reasons') or [])[:5],
            'case_metrics': [
                {
                    'label': case.get('label'),
                    'ae': case.get('ae'),
                    'rmse': case.get('rmse'),
                    'family_total_hits': case.get('family_total_hits'),
                    'family_reason_counts': case.get('family_reason_counts') or [],
                }
                for case in (pool_regression_review_data.get('cases') or [])[:3]
            ],
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
    if hires_summary.get('source_policy') is not None:
        summary_line += f', source policy `{hires_summary.get("source_policy")}`'
    if hires_summary.get('entry_count') is not None:
        summary_line += (
            f', entries `{hires_summary.get("entry_count")}`'
            f', native sampled `{hires_summary.get("native_sampled_entry_count")}`'
            f', compat `{hires_summary.get("compat_entry_count")}`'
            f', sampled index `{hires_summary.get("sampled_index_count")}`'
            f', sampled dupe keys `{hires_summary.get("sampled_duplicate_key_count")}`'
            f', sampled families `{hires_summary.get("sampled_family_count")}`'
            f', source PHRB `{(hires_summary.get("source_counts") or {}).get("phrb")}`'
        )
    descriptor_path_counts = step.get('descriptor_path_counts') or {}
    descriptor_detail = hires_summary.get('descriptor_path_detail_counts') or {}
    resolution_reasons = hires_summary.get('resolution_reason_counts') or {}
    if descriptor_path_counts:
        summary_line += (
            f', descriptor paths sampled `{descriptor_path_counts.get("sampled", 0)}`'
            f' / native checksum `{descriptor_path_counts.get("native_checksum", 0)}`'
            f' / generic `{descriptor_path_counts.get("generic", 0)}`'
            f' / compat `{descriptor_path_counts.get("compat", 0)}`'
        )
    if descriptor_detail:
        summary_line += (
            f', native checksum detail exact `{descriptor_detail.get("native_checksum_exact", 0)}`'
            f' / identity assisted `{descriptor_detail.get("native_checksum_identity_assisted", 0)}`'
            f' / generic fallback `{descriptor_detail.get("native_checksum_generic_fallback", 0)}`'
            f', generic detail identity assisted `{descriptor_detail.get("generic_identity_assisted", 0)}`'
            f' / plain `{descriptor_detail.get("generic_plain", 0)}`'
        )
    if resolution_reasons:
        formatted_reasons = ", ".join(
            f'`{reason}` x `{count}`'
            for reason, count in list(resolution_reasons.items())[:6]
        )
        summary_line += f', resolution reasons {formatted_reasons}'
    md.extend([
        summary_line,
        f'- Sampled exact hits: `{step["sampled_object_probe"]["exact_hit_count"]}`',
        f'- Sampled exact misses: `{step["sampled_object_probe"]["exact_miss_count"]}`',
        f'- Sampled conflict misses: `{step["sampled_object_probe"]["exact_conflict_miss_count"]}`',
        f'- Sampled unresolved misses: `{step["sampled_object_probe"]["exact_unresolved_miss_count"]}`',
    ])
    duplicate_probe = step.get('sampled_duplicate_probe') or {}
    md.append(
        f'- Sampled duplicate keys: `{duplicate_probe.get("unique_bucket_count")}` buckets, `{duplicate_probe.get("line_count")}` log lines'
    )
    for duplicate_bucket in duplicate_probe.get('top_buckets', [])[:3]:
        duplicate_fields = duplicate_bucket.get('fields') or {}
        md.append(
            '- Sampled duplicate detail: '
            f'low32 `{duplicate_fields.get("sampled_low32")}`, '
            f'palette `{duplicate_fields.get("palette_crc")}`, '
            f'fs `{duplicate_fields.get("fs")}`, '
            f'selector `{duplicate_fields.get("selector")}`, '
            f'total `{duplicate_fields.get("total_entries")}`, '
            f'active policy `{duplicate_fields.get("policy")}`, '
            f'replacement `{duplicate_fields.get("replacement_id")}`'
        )
    pool_stream_probe = step.get('sampled_pool_stream_probe') or {}
    md.append(
        f'- Sampled pool stream families: `{pool_stream_probe.get("family_count", 0)}` families, `{pool_stream_probe.get("line_count", 0)}` log lines'
    )
    for pool_family in pool_stream_probe.get('top_families', [])[:3]:
        pool_fields = pool_family.get('fields') or {}
        md.append(
            '- Sampled pool stream detail: '
            f'low32 `{pool_fields.get("sampled_low32")}`, '
            f'palette `{pool_fields.get("palette_crc")}`, '
            f'fs `{pool_fields.get("fs")}`, '
            f'observed `{pool_fields.get("observed_count")}` across `{pool_fields.get("unique_observed_selectors")}` selectors, '
            f'transitions `{pool_fields.get("transition_count")}`, '
            f'max run `{pool_fields.get("max_run")}`, '
            f'latest selector `{pool_fields.get("observed_selector")}` from `{pool_fields.get("observed_selector_source")}`'
        )
    review_md = step.get('sampled_selector_review', {}).get('markdown_path')
    review_json = step.get('sampled_selector_review', {}).get('json_path')
    if review_md:
        md.append(f'- Sampled selector review: [{Path(review_md).name}]({review_md})')
    if review_json:
        md.append(f'- Sampled selector review JSON: [{Path(review_json).name}]({review_json})')
    seam_md = step.get('runtime_seam_register', {}).get('markdown_path')
    seam_json = step.get('runtime_seam_register', {}).get('json_path')
    if seam_md:
        md.append(f'- Runtime seam register: [{Path(seam_md).name}]({seam_md})')
    if seam_json:
        md.append(f'- Runtime seam register JSON: [{Path(seam_json).name}]({seam_json})')
    alt_review = step.get('alternate_source_review') or {}
    alt_review_md = alt_review.get('markdown_path')
    alt_review_json = alt_review.get('json_path')
    if alt_review_md:
        md.append(
            f"- Alternate-source review: [{Path(alt_review_md).name}]({alt_review_md}) "
            f"-> `{alt_review.get('available_group_count')}` / `{alt_review.get('group_count')}` groups with candidates, "
            f"`{alt_review.get('total_candidate_count')}` total candidates"
        )
    if alt_review_json:
        md.append(f'- Alternate-source review JSON: [{Path(alt_review_json).name}]({alt_review_json})')
    for alt_group in alt_review.get('groups', []):
        md.append(
            f"- Alternate-source family `{alt_group.get('sampled_low32')}`: "
            f"`{alt_group.get('status')}`, dims `{alt_group.get('seed_dimensions')}`, "
            f"candidates `{alt_group.get('candidate_count')}`"
        )
    activation_review = step.get('alternate_source_activation_review') or {}
    activation_review_md = activation_review.get('markdown_path')
    activation_review_json = activation_review.get('json_path')
    activation_summary = activation_review.get('summary') or {}
    if activation_review_md:
        md.append(
            f"- Alternate-source activation review: [{Path(activation_review_md).name}]({activation_review_md}) "
            f"-> review-bounded `{activation_summary.get('review_bounded_probe_count', 0)}`, "
            f"shared-scene blocked `{activation_summary.get('shared_scene_blocked_count', 0)}`, "
            f"partial-overlap blocked `{activation_summary.get('partial_overlap_blocked_count', 0)}`"
        )
    if activation_review_json:
        md.append(f'- Alternate-source activation review JSON: [{Path(activation_review_json).name}]({activation_review_json})')
    for family in activation_review.get('families', []):
        md.append(
            f"- Alternate-source activation family `{family.get('sampled_low32')}`: "
            f"`{family.get('activation_status')}`, "
            f"`{family.get('activation_recommendation')}`, "
            f"candidates `{family.get('candidate_count')}`, "
            f"cross-scene `{family.get('cross_scene_promotion_status')}`"
        )
    cross_scene_review = step.get('sampled_cross_scene_review') or {}
    cross_scene_review_md = cross_scene_review.get('markdown_path')
    cross_scene_review_json = cross_scene_review.get('json_path')
    if cross_scene_review_md:
        md.append(f'- Cross-scene review: [{Path(cross_scene_review_md).name}]({cross_scene_review_md})')
    if cross_scene_review_json:
        md.append(f'- Cross-scene review JSON: [{Path(cross_scene_review_json).name}]({cross_scene_review_json})')
    for family in cross_scene_review.get('families', []):
        extra = []
        if family.get('shared_guard_labels'):
            extra.append(f"shared guards `{','.join(family.get('shared_guard_labels') or [])}`")
        if family.get('guard_labels_without_observation'):
            extra.append(f"absent guards `{','.join(family.get('guard_labels_without_observation') or [])}`")
        md.append(
            f"- Cross-scene family `{family.get('sampled_low32')}`: "
            f"`{family.get('promotion_status')}`, shared `{family.get('shared_signature_count')}`, "
            f"target-exclusive `{family.get('target_exclusive_signature_count')}`"
            f"{', ' + ', '.join(extra) if extra else ''}"
        )
    for pool_review in step.get('sampled_pool_reviews', []):
        if pool_review.get('markdown_path'):
            replacement_suffix = ''
            if pool_review.get('runtime_sample_replacement_id'):
                replacement_suffix = f", replacement `{pool_review.get('runtime_sample_replacement_id')}`"
            status_suffix = f", status `{pool_review.get('review_status') or 'complete'}`"
            review_label = pool_review.get('runtime_shape_recommendation') or pool_review.get('review_status') or 'unknown'
            md.append(
                f"- Sampled pool review `{pool_review.get('sampled_low32')}`: "
                f"[{Path(pool_review['markdown_path']).name}]({pool_review['markdown_path']}) "
                f"-> `{review_label}`{replacement_suffix}{status_suffix}"
            )
        if pool_review.get('json_path'):
            md.append(
                f"- Sampled pool review JSON `{pool_review.get('sampled_low32')}`: "
                f"[{Path(pool_review['json_path']).name}]({pool_review['json_path']})"
            )
    for duplicate_review in step.get('sampled_duplicate_reviews', []):
        if duplicate_review.get('markdown_path'):
            replacement_suffix = ''
            if duplicate_review.get('active_replacement_id'):
                replacement_suffix = f", active replacement `{duplicate_review.get('active_replacement_id')}`"
            md.append(
                f"- Sampled duplicate review `{duplicate_review.get('sampled_low32')}`: "
                f"[{Path(duplicate_review['markdown_path']).name}]({duplicate_review['markdown_path']}) "
                f"-> `{duplicate_review.get('recommendation')}`{replacement_suffix}"
            )
        if duplicate_review.get('json_path'):
            md.append(
                f"- Sampled duplicate review JSON `{duplicate_review.get('sampled_low32')}`: "
                f"[{Path(duplicate_review['json_path']).name}]({duplicate_review['json_path']})"
            )
    pool_regression_review = step.get('sampled_pool_regression_review') or {}
    if pool_regression_review.get('markdown_path'):
        md.append(
            f"- Sampled pool regression review: "
            f"[{Path(pool_regression_review['markdown_path']).name}]({pool_regression_review['markdown_path']}) "
            f"-> `{pool_regression_review.get('recommendation')}`"
        )
    if pool_regression_review.get('json_path'):
        md.append(
            f"- Sampled pool regression review JSON: "
            f"[{Path(pool_regression_review['json_path']).name}]({pool_regression_review['json_path']})"
        )
    for case in pool_regression_review.get('case_metrics', []):
        reasons = ", ".join(
            f"{row.get('reason')} x`{row.get('count')}`" for row in case.get('family_reason_counts') or []
        ) or "none"
        md.append(
            f"- Sampled pool regression case `{case.get('label')}`: "
            f"AE `{case.get('ae')}`, RMSE `{case.get('rmse')}`, "
            f"`{pool_regression_review.get('sampled_low32')}` hits `{case.get('family_total_hits')}`, reasons {reasons}"
        )
    md.append('')
(bundle_root / 'validation-summary.md').write_text('\n'.join(md) + '\n')
print(summary_path)
print(bundle_root / 'validation-summary.md')
PY

echo "[validation] complete: $BUNDLE_ROOT"
