#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

CACHE_PATH="${PARALLEL_RDP_HIRES_CACHE_PATH:-}"
BUNDLE_ROOT=""
RUN_PROBES=1

usage() {
  cat <<'USAGE'
Usage:
  tools/scenarios/paper-mario-selected-package-authority-validation.sh [options]

Options:
  --cache-path PATH     Selected PHRB package to validate (defaults to env PARALLEL_RDP_HIRES_CACHE_PATH)
  --bundle-root PATH    Root directory for emitted authority bundles
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

if [[ -z "$BUNDLE_ROOT" ]]; then
  BUNDLE_ROOT="$REPO_ROOT/artifacts/paper-mario-probes/validation/$(date +"%Y%m%d-%H%M%S")-selected-package-authorities"
fi

declare -a FIXTURES=(
  "title-screen|tools/scenarios/paper-mario-title-screen.sh"
  "file-select|tools/scenarios/paper-mario-file-select.sh"
  "kmr-03-entry-5|tools/scenarios/paper-mario-kmr-03-entry-5.sh"
)

mkdir -p "$BUNDLE_ROOT"

for fixture in "${FIXTURES[@]}"; do
  IFS='|' read -r label scenario_path <<<"$fixture"
  bundle_dir="$BUNDLE_ROOT/$label"

  if (( RUN_PROBES )); then
    PARALLEL_RDP_HIRES_CACHE_PATH="$CACHE_PATH" \
    DISABLE_SCREENSHOT_VERIFY=1 \
    EXPECTED_HIRES_SUMMARY_SOURCE_MODE_ON="phrb-only" \
    EXPECTED_HIRES_MIN_SUMMARY_ENTRY_COUNT_ON="1" \
    EXPECTED_HIRES_MIN_SUMMARY_NATIVE_SAMPLED_ENTRY_COUNT_ON="1" \
    EXPECTED_HIRES_MIN_SUMMARY_SOURCE_PHRB_COUNT_ON="1" \
    "$REPO_ROOT/$scenario_path" \
      --mode on \
      --authority-mode authoritative \
      --bundle-dir "$bundle_dir" \
      --run
  fi

  if [[ ! -f "$bundle_dir/traces/fixture-verification.json" ]]; then
    echo "Missing fixture verification output: $bundle_dir/traces/fixture-verification.json" >&2
    exit 1
  fi
done

python3 - "$CACHE_PATH" "$BUNDLE_ROOT" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

cache_path = Path(sys.argv[1])
bundle_root = Path(sys.argv[2])

fixtures = [
    ("title-screen", "paper-mario-title-screen"),
    ("file-select", "paper-mario-file-select"),
    ("kmr-03-entry-5", "paper-mario-kmr-03-entry-5"),
]

summary = {
    "cache_path": str(cache_path),
    "cache_sha256": hashlib.sha256(cache_path.read_bytes()).hexdigest(),
    "all_passed": True,
    "fixtures": [],
}

for label, fixture_id in fixtures:
    bundle_dir = bundle_root / label
    verification_path = bundle_dir / "traces" / "fixture-verification.json"
    verification = json.loads(verification_path.read_text())
    actual = verification.get("actual") or {}
    failures = verification.get("failures") or []
    fixture_summary = {
        "label": label,
        "fixture_id": fixture_id,
        "bundle_dir": str(bundle_dir),
        "passed": bool(verification.get("passed")),
        "screenshot_sha256": (verification.get("checks") or {}).get("screenshot_sha256"),
        "capture_path": actual.get("capture_path"),
        "init_symbol": actual.get("init_symbol"),
        "step_symbol": actual.get("step_symbol"),
        "hires_summary": {
            "provider": actual.get("hires_summary_provider"),
            "source_mode": actual.get("hires_summary_source_mode"),
            "entry_count": actual.get("hires_summary_entry_count"),
            "native_sampled_entry_count": actual.get("hires_summary_native_sampled_entry_count"),
            "source_phrb_count": actual.get("hires_summary_source_phrb_count"),
        },
        "sampled_object_probe": {
            "exact_hit_count": actual.get("hires_exact_hit_count"),
            "exact_conflict_miss_count": actual.get("hires_exact_conflict_miss_count"),
            "exact_unresolved_miss_count": actual.get("hires_exact_unresolved_miss_count"),
        },
        "failures": failures,
    }
    summary["fixtures"].append(fixture_summary)
    if not fixture_summary["passed"]:
        summary["all_passed"] = False

summary_path = bundle_root / "validation-summary.json"
summary_path.write_text(json.dumps(summary, indent=2) + "\n")

md = [
    "# Selected-Package Authority Validation",
    "",
    f"- Cache: `{cache_path}`",
    f"- Cache SHA-256: `{summary['cache_sha256']}`",
    f"- All passed: `{str(summary['all_passed']).lower()}`",
    "",
]

for fixture in summary["fixtures"]:
    hires = fixture["hires_summary"]
    probe = fixture["sampled_object_probe"]
    md.extend([
        f"## {fixture['label']}",
        f"- Bundle: [{Path(fixture['bundle_dir']).name}]({fixture['bundle_dir']})",
        f"- Passed: `{str(fixture['passed']).lower()}`",
        f"- Screenshot hash: `{fixture['screenshot_sha256']}`",
        f"- Semantic: `{fixture['init_symbol']}` / `{fixture['step_symbol']}`",
        f"- Hi-res summary: provider `{hires.get('provider')}`, source mode `{hires.get('source_mode')}`, entries `{hires.get('entry_count')}`, native sampled `{hires.get('native_sampled_entry_count')}`, source PHRB `{hires.get('source_phrb_count')}`",
        f"- Sampled exact hits: `{probe.get('exact_hit_count')}`",
        f"- Sampled conflict misses: `{probe.get('exact_conflict_miss_count')}`",
        f"- Sampled unresolved misses: `{probe.get('exact_unresolved_miss_count')}`",
    ])
    if fixture["failures"]:
        md.append(f"- Failures: `{' | '.join(fixture['failures'])}`")
    md.append("")

(bundle_root / "validation-summary.md").write_text("\n".join(md) + "\n")
print(summary_path)
print(bundle_root / "validation-summary.md")
PY

echo "[validation] complete: $BUNDLE_ROOT"
