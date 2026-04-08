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

(tmp_dir / "package-manifest.json").write_text(json.dumps({
    "records": [
        {
            "policy_key": "surface-7701ac09",
            "canonical_identity": {
                "sampled_low32": "7701ac09",
            },
            "asset_candidates": [
                {
                    "replacement_id": "legacy-2cf87740-00000000-fs0-1600x16",
                    "legacy_texture_crc": "2cf87740",
                    "selector_checksum64": "000000002cf87740",
                    "variant_group_id": "surface-7701ac09-000000002cf87740",
                    "materialized_path": "assets/legacy-2cf87740-00000000-fs0-1600x16.png",
                },
                {
                    "replacement_id": "legacy-844144ad-00000000-fs0-1600x16",
                    "legacy_texture_crc": "844144ad",
                    "selector_checksum64": "0000000071c71cdd",
                    "variant_group_id": "surface-7701ac09-0000000071c71cdd",
                    "materialized_path": "assets/legacy-844144ad-00000000-fs0-1600x16.png",
                },
                {
                    "replacement_id": "legacy-844144ad-00000000-fs0-1600x16",
                    "legacy_texture_crc": "844144ad",
                    "selector_checksum64": "00000000844144ad",
                    "variant_group_id": "surface-7701ac09-00000000844144ad",
                    "materialized_path": "assets/legacy-844144ad-00000000-fs0-1600x16.png",
                },
                {
                    "replacement_id": "legacy-e0dc03d0-00000000-fs0-1600x16",
                    "legacy_texture_crc": "e0dc03d0",
                    "selector_checksum64": "00000000e0dc03d0",
                    "variant_group_id": "surface-7701ac09-00000000e0dc03d0",
                    "materialized_path": "assets/legacy-e0dc03d0-00000000-fs0-1600x16.png",
                },
            ],
            "duplicate_pixel_groups": [
                {
                    "alpha_normalized_pixel_sha256": "shared-alpha-hash",
                    "replacement_ids": [
                        "legacy-2cf87740-00000000-fs0-1600x16",
                        "legacy-844144ad-00000000-fs0-1600x16",
                        "legacy-844144ad-00000000-fs0-1600x16",
                        "legacy-e0dc03d0-00000000-fs0-1600x16",
                    ],
                }
            ],
        }
    ]
}, indent=2) + "\n")
PY

python3 "$REPO_ROOT/tools/hires_sampled_alias_group_review.py" \
  --package-manifest "$TMP_DIR/package-manifest.json" \
  --sampled-low32 7701ac09 \
  --alpha-hash shared-alpha-hash \
  --output "$TMP_DIR/review.md" \
  --output-json "$TMP_DIR/review.json"

python3 - "$TMP_DIR/review.json" "$TMP_DIR/review.md" <<'PY'
import json
import sys
from pathlib import Path

review = json.loads(Path(sys.argv[1]).read_text())
markdown = Path(sys.argv[2]).read_text()

if review.get("recommendation") != "keep-selectors-distinct-and-consider-asset-level-dedupe":
    raise SystemExit(f"FAIL: unexpected recommendation {review!r}.")
if review.get("selector_row_count") != 4:
    raise SystemExit(f"FAIL: unexpected selector row count {review!r}.")
if review.get("duplicate_selectors") != []:
    raise SystemExit(f"FAIL: selector-local duplicates should already be gone {review!r}.")
if review.get("suggested_canonical_replacement_id") != "legacy-844144ad-00000000-fs0-1600x16":
    raise SystemExit(f"FAIL: unexpected suggested canonical id {review!r}.")
if review.get("suggested_alias_replacement_ids") != [
    "legacy-2cf87740-00000000-fs0-1600x16",
    "legacy-e0dc03d0-00000000-fs0-1600x16",
]:
    raise SystemExit(f"FAIL: unexpected alias ids {review!r}.")
if review.get("unique_group_replacement_ids") != [
    "legacy-2cf87740-00000000-fs0-1600x16",
    "legacy-844144ad-00000000-fs0-1600x16",
    "legacy-e0dc03d0-00000000-fs0-1600x16",
]:
    raise SystemExit(f"FAIL: unexpected unique replacement ids {review!r}.")
reasons = set(review.get("reasons") or [])
for reason in (
    "group-spans-distinct-selectors-only",
    "no-selector-local-duplicate-conflicts-remain",
    "group-still-contains-repeated-replacement-id-members",
    "group-still-spans-multiple-replacement-ids",
):
    if reason not in reasons:
        raise SystemExit(f"FAIL: missing reason {reason!r} in {reasons!r}.")
for snippet in (
    "# Sampled Alias Group Review",
    "keep-selectors-distinct-and-consider-asset-level-dedupe",
    "0000000071c71cdd",
):
    if snippet not in markdown:
        raise SystemExit(f"FAIL: markdown missing {snippet!r}.")

print("emu_hires_sampled_alias_group_review_contract: PASS")
PY
