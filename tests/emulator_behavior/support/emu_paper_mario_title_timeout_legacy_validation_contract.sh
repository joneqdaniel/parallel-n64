#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/package.phrb"
BUNDLE_ROOT="$TMP_DIR/bundles"
printf 'phrb' > "$CACHE_PATH"
mkdir -p "$BUNDLE_ROOT/legacy/timeout-960/captures" "$BUNDLE_ROOT/legacy/timeout-960/traces"
mkdir -p "$BUNDLE_ROOT/selected/timeout-960/captures" "$BUNDLE_ROOT/selected/timeout-960/traces"

python3 - "$BUNDLE_ROOT" <<'PY'
import json
import sys
from pathlib import Path
from PIL import Image

bundle_root = Path(sys.argv[1])

for side in ("legacy", "selected"):
    capture_dir = bundle_root / side / "timeout-960" / "captures"
    Image.new("RGBA", (1, 1), (255, 255, 255, 255)).save(capture_dir / f"{side}.png")

legacy_hires = {
    "summary": {
        "provider": "on",
        "source_mode": "legacy-only",
        "entry_count": 12,
        "native_sampled_entry_count": 0,
        "compat_entry_count": 12,
        "source_counts": {
            "phrb": 0,
            "hts": 12,
            "htc": 0,
        },
    }
}
(bundle_root / "legacy" / "timeout-960" / "traces" / "hires-evidence.json").write_text(
    json.dumps(legacy_hires, indent=2) + "\n"
)

selected_semantic = {
    "paper_mario_us": {
        "game_status": {
            "map_name_candidate": "kmr_03",
            "entry_id": 5,
        },
        "cur_game_mode": {
            "init_symbol": "state_init_world",
            "step_symbol": "state_step_world",
        },
    }
}
(bundle_root / "selected" / "timeout-960" / "traces" / "paper-mario-game-status.json").write_text(
    json.dumps(selected_semantic, indent=2) + "\n"
)

selected_hires = {
    "summary": {
        "provider": "on",
        "source_mode": "phrb-only",
        "entry_count": 195,
        "native_sampled_entry_count": 195,
        "compat_entry_count": 0,
        "source_counts": {
            "phrb": 195,
            "hts": 0,
            "htc": 0,
        },
    },
    "sampled_object_probe": {
        "exact_hit_count": 99,
        "exact_conflict_miss_count": 66,
        "exact_unresolved_miss_count": 591,
        "top_exact_hit_buckets": [],
    },
}
(bundle_root / "selected" / "timeout-960" / "traces" / "hires-evidence.json").write_text(
    json.dumps(selected_hires, indent=2) + "\n"
)
PY

bash "$REPO_ROOT/tools/scenarios/paper-mario-title-timeout-legacy-validation.sh" \
  --cache-path "$CACHE_PATH" \
  --bundle-root "$BUNDLE_ROOT" \
  --steps "960" \
  --reuse

SUMMARY_PATH="$BUNDLE_ROOT/validation-summary.json"
MARKDOWN_PATH="$BUNDLE_ROOT/validation-summary.md"
if [[ ! -f "$SUMMARY_PATH" ]]; then
  echo "FAIL: missing validation summary at $SUMMARY_PATH." >&2
  exit 1
fi
if [[ ! -f "$MARKDOWN_PATH" ]]; then
  echo "FAIL: missing validation markdown at $MARKDOWN_PATH." >&2
  exit 1
fi

python3 - "$SUMMARY_PATH" "$MARKDOWN_PATH" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text())
markdown = Path(sys.argv[2]).read_text()

steps = summary.get("steps") or []
if len(steps) != 1:
    raise SystemExit(f"FAIL: expected one validation step, found {len(steps)}.")

step = steps[0]
legacy = step.get("legacy_hires_summary") or {}
selected = step.get("selected_hires_summary") or {}

if legacy.get("source_mode") != "legacy-only":
    raise SystemExit(f"FAIL: expected legacy source_mode=legacy-only, got {legacy.get('source_mode')!r}.")
if int(legacy.get("entry_count") or 0) < 1:
    raise SystemExit(f"FAIL: expected legacy entry_count>0, got {legacy.get('entry_count')!r}.")
if selected.get("source_mode") != "phrb-only":
    raise SystemExit(f"FAIL: expected selected source_mode=phrb-only, got {selected.get('source_mode')!r}.")
if "Legacy hi-res source mode: `legacy-only`" not in markdown:
    raise SystemExit("FAIL: markdown summary missing legacy hi-res source mode.")
if "Selected hi-res source mode: `phrb-only`" not in markdown:
    raise SystemExit("FAIL: markdown summary missing selected hi-res source mode.")
PY

echo "emu_paper_mario_title_timeout_legacy_validation_contract: PASS"
