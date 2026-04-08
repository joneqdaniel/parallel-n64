#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

python3 - "$TMP_DIR" <<'PY'
import json
import sys
from pathlib import Path

tmp_dir = Path(sys.argv[1])

def write_summary(path: Path, *, ae: int, rmse: float, hit_rows: list[tuple[str, int]], exact_hits: int, exact_conflict: int, exact_unresolved: int):
    path.write_text(json.dumps({
        "cache_path": str(path.with_suffix(".phrb")),
        "cache_sha256": path.stem,
        "steps": [
            {
                "step_frames": 960,
                "selected_hash": f"{path.stem}-selected",
                "legacy_hash": f"{path.stem}-legacy",
                "matches_legacy": False,
                "ae": ae,
                "rmse": rmse,
                "semantic": {
                    "map_name_candidate": "kmr_03",
                    "entry_id": 5,
                    "init_symbol": "state_init_world",
                    "step_symbol": "state_step_world",
                },
                "sampled_object_probe": {
                    "exact_hit_count": exact_hits,
                    "exact_conflict_miss_count": exact_conflict,
                    "exact_unresolved_miss_count": exact_unresolved,
                    "top_exact_hit_buckets": [
                        {
                            "count": count,
                            "fields": {
                                "sampled_low32": "1b8530fb",
                                "reason": reason,
                                "key": "52e0d2531b8530fb",
                                "repl": "1184x24",
                            },
                            "sample_detail": f"{reason} x {count}",
                        }
                        for reason, count in hit_rows
                    ],
                },
            }
        ],
    }, indent=2) + "\n")

write_summary(
    tmp_dir / "flat-summary.json",
    ae=1659865,
    rmse=1.3326554039,
    hit_rows=[("sampled-sparse-exact", 1056)],
    exact_hits=26804,
    exact_conflict=2112,
    exact_unresolved=57024,
)
write_summary(
    tmp_dir / "dual-summary.json",
    ae=34094281,
    rmse=10.8172496800,
    hit_rows=[("sampled-sparse-exact", 1056), ("sampled-sparse-ordered-surface", 1056)],
    exact_hits=56108,
    exact_conflict=0,
    exact_unresolved=528,
)
write_summary(
    tmp_dir / "ordered-summary.json",
    ae=126937490,
    rmse=19.8116065828,
    hit_rows=[("sampled-sparse-ordered-surface", 2112)],
    exact_hits=56108,
    exact_conflict=0,
    exact_unresolved=528,
)

(tmp_dir / "surface-package.json").write_text(json.dumps({
    "surface_count": 1,
    "surfaces": [
        {
            "canonical_identity": {
                "sampled_low32": "1b8530fb",
                "draw_class": "texrect",
                "cycle": "copy",
                "formatsize": 258,
            },
            "surface": {
                "sampled_low32": "1b8530fb",
                "shape_hint": "rotating-stream-edge-dwell",
                "slot_count": 34,
                "replacement_ids": ["r0", "r1", "r2"],
                "unresolved_sequences": [
                    {
                        "sequence_index": 33,
                        "upload_key": "77e5f3760b110a9b",
                    }
                ],
                "surface_tile_dims": "296x6",
            },
        }
    ],
}, indent=2) + "\n")

(tmp_dir / "live-pool-review.json").write_text(json.dumps({
    "runtime_sample_policy": "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb-pool",
    "runtime_sample_replacement_id": "legacy-038a968c-9afc43ab-fs0-1184x24",
    "runtime_sampled_object": "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb",
    "pool_recommendation": "defer-runtime-pool-semantics",
    "runtime_shape_recommendation": "keep-flat-runtime-binding",
    "recommendation_reasons": [
        "shape_hint=rotating-stream-edge-dwell",
        "ordered_surface_unresolved_slots=1",
        "tail_dwell_aligns_with_unresolved_slot",
    ],
    "sequence_summary": {
        "shape_hint": "rotating-stream-edge-dwell",
        "dominant_delta": 1,
        "dominant_delta_count": 32,
    },
    "surface_map_summary": {
        "slot_count": 34,
        "mapped_candidate_count": 33,
        "unresolved_count": 1,
        "candidate_count": 33,
        "resolved_ratio": 0.9705882353,
    },
    "edge_review": {
        "edge_only": True,
        "unresolved_count": 1,
    },
    "tail_dwell": {
        "present": True,
        "run_length": 4,
        "aligns_with_unresolved_slot": True,
    },
}, indent=2) + "\n")
PY

python3 "$REPO_ROOT/tools/hires_pool_regression_review.py" \
  --sampled-low32 1b8530fb \
  --flat-summary "$TMP_DIR/flat-summary.json" \
  --dual-summary "$TMP_DIR/dual-summary.json" \
  --ordered-summary "$TMP_DIR/ordered-summary.json" \
  --surface-package "$TMP_DIR/surface-package.json" \
  --live-pool-review "$TMP_DIR/live-pool-review.json" \
  --output "$TMP_DIR/review.md" \
  --output-json "$TMP_DIR/review.json"

python3 - "$TMP_DIR/review.json" "$TMP_DIR/review.md" <<'PY'
import json
import sys
from pathlib import Path

review = json.loads(Path(sys.argv[1]).read_text())
markdown = Path(sys.argv[2]).read_text()

recommendation = review.get("recommendation") or {}
if recommendation.get("recommendation") != "keep-flat-runtime-binding":
    raise SystemExit(f"FAIL: unexpected recommendation {recommendation!r}.")
if recommendation.get("pool_follow_up") != "defer-runtime-pool-semantics":
    raise SystemExit(f"FAIL: unexpected pool follow-up {recommendation!r}.")
reasons = set(recommendation.get("reasons") or [])
expected_reasons = {
    "surface-adds-1b85-hit-modes-with-worse-frame-error",
    "ordered-only-increases-1b85-coverage-while-regressing-further",
    "surface-package-keeps-1-unresolved-tail-slot",
    "live-stream-shape-is-rotating-stream-edge-dwell",
    "live-tail-dwell-still-aligns-with-unresolved-slot",
    "live-review=keep-flat-runtime-binding",
}
if not expected_reasons.issubset(reasons):
    raise SystemExit(f"FAIL: missing recommendation reasons in {reasons!r}.")

cases = review.get("cases") or []
if [case.get("label") for case in cases] != ["flat", "dual", "ordered-only"]:
    raise SystemExit(f"FAIL: unexpected case order {cases!r}.")
if cases[0].get("family_total_hits") != 1056:
    raise SystemExit(f"FAIL: unexpected flat family hit count {cases[0]!r}.")
if cases[1].get("family_total_hits") != 2112:
    raise SystemExit(f"FAIL: unexpected dual family hit count {cases[1]!r}.")
if cases[2].get("family_reason_counts") != [{"reason": "sampled-sparse-ordered-surface", "count": 2112}]:
    raise SystemExit(f"FAIL: unexpected ordered reason counts {cases[2]!r}.")

surface = review.get("surface_package") or {}
if surface.get("unresolved_sequence_count") != 1:
    raise SystemExit(f"FAIL: unexpected surface unresolved count {surface!r}.")
if (surface.get("first_unresolved_sequence") or {}).get("upload_key") != "77e5f3760b110a9b":
    raise SystemExit(f"FAIL: unexpected first unresolved sequence {surface!r}.")

live = review.get("live_pool_review") or {}
if live.get("runtime_sample_replacement_id") != "legacy-038a968c-9afc43ab-fs0-1184x24":
    raise SystemExit(f"FAIL: unexpected live replacement id {live!r}.")

for snippet in (
    "# Sampled Pool Regression Review",
    "## Historical Comparison",
    "## Surface Package",
    "## Live Pool Review",
    "keep-flat-runtime-binding",
):
    if snippet not in markdown:
        raise SystemExit(f"FAIL: markdown missing {snippet!r}.")

print("emu_hires_pool_regression_review_contract: PASS")
PY
