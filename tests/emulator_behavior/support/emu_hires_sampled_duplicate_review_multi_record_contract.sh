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

(tmp_dir / "seam-register.json").write_text(json.dumps({
    "sampled_duplicate_families": [
        {
            "sampled_low32": "1b8530fb",
            "selector": "05556c9778538e1e",
            "policy": "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb-pool",
            "replacement_id": "legacy-78538e1e-05556c97-fs0-1184x24",
        }
    ]
}, indent=2) + "\n")

(tmp_dir / "package-manifest.json").write_text(json.dumps({
    "records": [
        {
            "policy_key": "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb-pool",
            "canonical_identity": {
                "sampled_low32": "1b8530fb",
            },
            "asset_candidates": [
                {
                    "replacement_id": "legacy-78538e1e-05556c97-fs0-1184x24",
                    "legacy_texture_crc": "78538e1e",
                    "selector_checksum64": "05556c9778538e1e",
                    "variant_group_id": "pool-1b8530fb-05556c9778538e1e",
                    "materialized_path": "assets/pool-78538e1e.png",
                    "pixel_sha256": "shared-pixel-hash",
                    "alpha_normalized_pixel_sha256": "shared-alpha-hash",
                }
            ],
            "duplicate_pixel_groups": [],
        },
        {
            "policy_key": "surface-1b8530fb",
            "canonical_identity": {
                "sampled_low32": "1b8530fb",
            },
            "asset_candidates": [
                {
                    "replacement_id": "legacy-78538e1e-05556c97-fs0-1184x24",
                    "legacy_texture_crc": "78538e1e",
                    "selector_checksum64": "05556c9778538e1e",
                    "variant_group_id": "surface-1b8530fb-05556c9778538e1e",
                    "materialized_path": "assets/surface-78538e1e.png",
                    "pixel_sha256": "shared-pixel-hash",
                    "alpha_normalized_pixel_sha256": "shared-alpha-hash",
                }
            ],
            "duplicate_pixel_groups": [
                {
                    "alpha_normalized_pixel_sha256": "shared-alpha-hash",
                    "replacement_ids": [
                        "legacy-78538e1e-05556c97-fs0-1184x24",
                        "legacy-5f6dd165-f978d303-fs0-1184x24",
                    ],
                }
            ],
        }
    ]
}, indent=2) + "\n")
PY

python3 "$REPO_ROOT/tools/hires_sampled_duplicate_review.py" \
  --runtime-seam-register "$TMP_DIR/seam-register.json" \
  --package-manifest "$TMP_DIR/package-manifest.json" \
  --sampled-low32 1b8530fb \
  --selector 05556c9778538e1e \
  --output "$TMP_DIR/review.md" \
  --output-json "$TMP_DIR/review.json"

python3 - "$TMP_DIR/review.json" "$TMP_DIR/review.md" <<'PY'
import json
import sys
from pathlib import Path

review = json.loads(Path(sys.argv[1]).read_text())
markdown = Path(sys.argv[2]).read_text()

if review.get("recommendation") != "keep-runtime-winner-rule-and-defer-offline-dedupe":
    raise SystemExit(f"FAIL: unexpected recommendation {review!r}.")
if review.get("record_count") != 2:
    raise SystemExit(f"FAIL: expected multi-record review, got {review!r}.")
if review.get("record_policy_keys") != [
    "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb-pool",
    "surface-1b8530fb",
]:
    raise SystemExit(f"FAIL: unexpected record policy keys {review!r}.")
if review.get("selector_candidate_count") != 2:
    raise SystemExit(f"FAIL: expected two selector candidates across records, got {review!r}.")
if review.get("unique_selector_pixel_hashes") != ["shared-pixel-hash"]:
    raise SystemExit(f"FAIL: unexpected pixel hashes {review!r}.")
if review.get("broader_alias_replacement_ids") != [
    "legacy-78538e1e-05556c97-fs0-1184x24",
    "legacy-5f6dd165-f978d303-fs0-1184x24",
]:
    raise SystemExit(f"FAIL: unexpected broader alias ids {review!r}.")
reasons = set(review.get("reasons") or [])
for reason in (
    "selector-duplicate-candidates-share-identical-pixel-hash",
    "selector-duplicate-candidates-share-identical-alpha-normalized-hash",
    "duplicate-pixel-group-spans-broader-surface-assets",
):
    if reason not in reasons:
        raise SystemExit(f"FAIL: missing reason {reason!r} in {reasons!r}.")
for snippet in (
    "record_count",
    "surface-1b8530fb",
    "shared-pixel-hash",
):
    if snippet not in markdown:
        raise SystemExit(f"FAIL: markdown missing {snippet!r}.")

print("emu_hires_sampled_duplicate_review_multi_record_contract: PASS")
PY
