#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/package.phrb"
printf 'phrb' > "$CACHE_PATH"

mkdir -p "$TMP_DIR/bundles/on/timeout-960/captures" "$TMP_DIR/bundles/on/timeout-960/traces"
mkdir -p "$TMP_DIR/bundles/off/timeout-960/captures" "$TMP_DIR/bundles/off/timeout-960/traces"

python3 - "$TMP_DIR" <<'PY'
import json
import sys
from pathlib import Path
from PIL import Image

tmp_dir = Path(sys.argv[1])

for mode in ("on", "off"):
    capture_dir = tmp_dir / "bundles" / mode / "timeout-960" / "captures"
    Image.new("RGBA", (1, 1), (255, 255, 255, 255)).save(capture_dir / f"{mode}.png")

semantic = {
    "paper_mario_us": {
        "game_status": {
            "map_name_candidate": "kmr_03",
            "entry_id": 5,
        },
        "cur_game_mode": {
            "init_symbol": "state_init_world",
            "step_symbol": "state_step_world",
        },
    },
}
(tmp_dir / "bundles" / "on" / "timeout-960" / "traces" / "paper-mario-game-status.json").write_text(
    json.dumps(semantic, indent=2) + "\n"
)

hires = {
    "summary": {
        "provider": "on",
        "source_mode": "phrb-only",
        "entry_count": 195,
        "native_sampled_entry_count": 195,
        "compat_entry_count": 0,
        "sampled_family_count": 10,
        "source_counts": {
            "phrb": 195,
            "hts": 0,
            "htc": 0,
        },
    },
    "sampled_object_probe": {
        "exact_hit_count": 99,
        "exact_miss_count": 657,
        "exact_conflict_miss_count": 66,
        "exact_unresolved_miss_count": 591,
        "top_exact_hit_buckets": [],
        "top_exact_conflict_miss_buckets": [],
        "top_exact_unresolved_miss_buckets": [],
    },
}
(tmp_dir / "bundles" / "on" / "timeout-960" / "traces" / "hires-evidence.json").write_text(
    json.dumps(hires, indent=2) + "\n"
)
PY

bash "$REPO_ROOT/tools/scenarios/paper-mario-title-timeout-selected-package-validation.sh" \
  --cache-path "$CACHE_PATH" \
  --bundle-root "$TMP_DIR/bundles" \
  --steps "960" \
  --reuse

python3 - "$TMP_DIR/bundles/validation-summary.json" "$TMP_DIR/bundles/validation-summary.md" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text())
markdown = Path(sys.argv[2]).read_text()

steps = summary.get("steps") or []
if len(steps) != 1:
    raise SystemExit(f"FAIL: expected 1 step, found {len(steps)}.")

step = steps[0]
hires = step.get("hires_summary") or {}
if hires.get("source_mode") != "phrb-only":
    raise SystemExit(f"FAIL: unexpected source mode {hires.get('source_mode')!r}.")
if hires.get("native_sampled_entry_count") != 195:
    raise SystemExit(f"FAIL: unexpected native sampled count {hires.get('native_sampled_entry_count')!r}.")
if step.get("sampled_object_probe", {}).get("exact_conflict_miss_count") != 66:
    raise SystemExit(f"FAIL: unexpected sampled conflict misses in {step!r}.")
if "source mode `phrb-only`" not in markdown:
    raise SystemExit("FAIL: markdown summary missing source mode line.")
print("emu_paper_mario_title_timeout_selected_package_validation_contract: PASS")
PY
