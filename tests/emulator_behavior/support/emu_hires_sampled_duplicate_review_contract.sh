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
            "sampled_low32": "7701ac09",
            "selector": "0000000071c71cdd",
            "policy": "surface-7701ac09",
            "replacement_id": "legacy-844144ad-00000000-fs0-1600x16",
        }
    ]
}, indent=2) + "\n")

(tmp_dir / "package-manifest.json").write_text(json.dumps({
    "records": [
        {
            "policy_key": "surface-7701ac09",
            "canonical_identity": {
                "sampled_low32": "7701ac09",
            },
            "asset_candidates": [
                {
                    "replacement_id": "legacy-844144ad-00000000-fs0-1600x16",
                    "legacy_texture_crc": "844144ad",
                    "selector_checksum64": "0000000071c71cdd",
                    "variant_group_id": "surface-7701ac09-0000000071c71cdd",
                    "materialized_path": "assets/legacy-844144ad-00000000-fs0-1600x16.png",
                    "pixel_sha256": "61827be38596dd7941e48ca97760fb7a3602c704f4dbfab44d1444d06db267a4",
                    "alpha_normalized_pixel_sha256": "f627ca4c2c322f15db26152df306bd4f983f0146409b81a4341b9b340c365a16",
                },
                {
                    "replacement_id": "legacy-e0dc03d0-00000000-fs0-1600x16",
                    "legacy_texture_crc": "e0dc03d0",
                    "selector_checksum64": "0000000071c71cdd",
                    "variant_group_id": "surface-7701ac09-0000000071c71cdd",
                    "materialized_path": "assets/legacy-e0dc03d0-00000000-fs0-1600x16.png",
                    "pixel_sha256": "61827be38596dd7941e48ca97760fb7a3602c704f4dbfab44d1444d06db267a4",
                    "alpha_normalized_pixel_sha256": "f627ca4c2c322f15db26152df306bd4f983f0146409b81a4341b9b340c365a16",
                },
                {
                    "replacement_id": "legacy-2cf87740-00000000-fs0-1600x16",
                    "legacy_texture_crc": "2cf87740",
                    "selector_checksum64": "000000002cf87740",
                    "variant_group_id": "surface-7701ac09-000000002cf87740",
                    "materialized_path": "assets/legacy-2cf87740-00000000-fs0-1600x16.png",
                    "pixel_sha256": "61827be38596dd7941e48ca97760fb7a3602c704f4dbfab44d1444d06db267a4",
                    "alpha_normalized_pixel_sha256": "f627ca4c2c322f15db26152df306bd4f983f0146409b81a4341b9b340c365a16",
                },
            ],
            "duplicate_pixel_groups": [
                {
                    "alpha_normalized_pixel_sha256": "f627ca4c2c322f15db26152df306bd4f983f0146409b81a4341b9b340c365a16",
                    "replacement_ids": [
                        "legacy-2cf87740-00000000-fs0-1600x16",
                        "legacy-844144ad-00000000-fs0-1600x16",
                        "legacy-e0dc03d0-00000000-fs0-1600x16",
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
  --sampled-low32 7701ac09 \
  --selector 0000000071c71cdd \
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
if review.get("selector_candidate_count") != 2:
    raise SystemExit(f"FAIL: unexpected selector candidate count {review!r}.")
if review.get("unique_selector_pixel_hashes") != ["61827be38596dd7941e48ca97760fb7a3602c704f4dbfab44d1444d06db267a4"]:
    raise SystemExit(f"FAIL: unexpected pixel hashes {review!r}.")
if review.get("broader_alias_replacement_ids") != [
    "legacy-2cf87740-00000000-fs0-1600x16",
    "legacy-844144ad-00000000-fs0-1600x16",
    "legacy-e0dc03d0-00000000-fs0-1600x16",
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
    "# Sampled Duplicate Review",
    "keep-runtime-winner-rule-and-defer-offline-dedupe",
    "## Selector Candidates",
    "## Duplicate Pixel Groups",
):
    if snippet not in markdown:
        raise SystemExit(f"FAIL: markdown missing {snippet!r}.")

print("emu_hires_sampled_duplicate_review_contract: PASS")
PY
