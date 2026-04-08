#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

python3 - "$TMP_DIR" <<'PY'
import gzip
import json
import struct
import sys
from pathlib import Path

tmp_dir = Path(sys.argv[1])
cache_path = tmp_dir / "cache.htc"
TXCACHE_FORMAT_VERSION = 0x08000000
entries = []

def add_entry(texture_crc: int, rgba: bytes):
    entry = {
        "texture_crc": texture_crc,
        "palette_crc": 0,
        "formatsize": 0,
        "width": 4,
        "height": 1,
        "format": 32856,
        "texture_format": 6408,
        "pixel_type": 5121,
        "is_hires": 1,
        "rgba": rgba,
    }
    entries.append(entry)

rgba = bytes([
    255, 0, 0, 255,
    255, 0, 0, 255,
    255, 0, 0, 255,
    255, 0, 0, 255,
])
add_entry(0x844144ad, rgba)
add_entry(0xe0dc03d0, rgba)
add_entry(0x2cf87740, rgba)

with gzip.open(cache_path, "wb") as fp:
    fp.write(struct.pack("<i", TXCACHE_FORMAT_VERSION))
    fp.write(struct.pack("<I", 0))
    for entry in entries:
        checksum64 = (entry["palette_crc"] << 32) | entry["texture_crc"]
        fp.write(struct.pack("<Q", checksum64))
        fp.write(
            struct.pack(
                "<IIIHHB",
                entry["width"],
                entry["height"],
                entry["format"],
                entry["texture_format"],
                entry["pixel_type"],
                entry["is_hires"],
            )
        )
        fp.write(struct.pack("<H", entry["formatsize"]))
        fp.write(struct.pack("<I", len(entry["rgba"])))
        fp.write(entry["rgba"])

loader_manifest = {
    "schema_version": 1,
    "bundle_path": str(tmp_dir / "bundle"),
    "record_count": 1,
    "records": [
        {
            "policy_key": "surface-7701ac09",
            "sampled_object_id": "sampled-fmt0-siz3-off0-stride400-wh200x2-fs768-low327701ac09",
            "canonical_identity": {
                "fmt": "0",
                "siz": "3",
                "off": "0",
                "stride": "400",
                "wh": "200x2",
                "formatsize": 768,
                "sampled_low32": "7701ac09",
                "sampled_entry_pcrc": "00000000",
                "sampled_sparse_pcrc": "00000000",
            },
            "upload_low32s": [],
            "upload_pcrcs": [],
            "asset_candidate_count": 3,
            "asset_candidates": [
                {
                    "replacement_id": "legacy-844144ad-00000000-fs0-4x1",
                    "legacy_checksum64": "00000000844144ad",
                    "legacy_texture_crc": "844144ad",
                    "legacy_palette_crc": "00000000",
                    "selector_checksum64": "0000000071c71cdd",
                    "legacy_formatsize": 0,
                    "legacy_storage": "htc",
                    "legacy_source_path": str(cache_path),
                    "variant_group_id": "surface-7701ac09-0000000071c71cdd",
                    "width": 4,
                    "height": 1,
                    "format": 32856,
                    "texture_format": 6408,
                    "pixel_type": 5121,
                    "data_size": len(rgba),
                    "is_hires": True,
                },
                {
                    "replacement_id": "legacy-e0dc03d0-00000000-fs0-4x1",
                    "legacy_checksum64": "00000000e0dc03d0",
                    "legacy_texture_crc": "e0dc03d0",
                    "legacy_palette_crc": "00000000",
                    "selector_checksum64": "0000000071c71cdd",
                    "legacy_formatsize": 0,
                    "legacy_storage": "htc",
                    "legacy_source_path": str(cache_path),
                    "variant_group_id": "surface-7701ac09-0000000071c71cdd",
                    "width": 4,
                    "height": 1,
                    "format": 32856,
                    "texture_format": 6408,
                    "pixel_type": 5121,
                    "data_size": len(rgba),
                    "is_hires": True,
                },
                {
                    "replacement_id": "legacy-2cf87740-00000000-fs0-4x1",
                    "legacy_checksum64": "000000002cf87740",
                    "legacy_texture_crc": "2cf87740",
                    "legacy_palette_crc": "00000000",
                    "selector_checksum64": "000000002cf87740",
                    "legacy_formatsize": 0,
                    "legacy_storage": "htc",
                    "legacy_source_path": str(cache_path),
                    "variant_group_id": "surface-7701ac09-000000002cf87740",
                    "width": 4,
                    "height": 1,
                    "format": 32856,
                    "texture_format": 6408,
                    "pixel_type": 5121,
                    "data_size": len(rgba),
                    "is_hires": True,
                },
            ],
        }
    ],
    "unresolved_transport_cases": [],
}
(tmp_dir / "loader-manifest.json").write_text(json.dumps(loader_manifest, indent=2) + "\n")

duplicate_review = {
    "sampled_low32": "7701ac09",
    "selector": "0000000071c71cdd",
    "recommendation": "keep-runtime-winner-rule-and-defer-offline-dedupe",
    "duplicate_bucket": {
        "policy": "surface-7701ac09",
        "replacement_id": "legacy-844144ad-00000000-fs0-4x1",
    },
    "unique_selector_replacement_ids": [
        "legacy-844144ad-00000000-fs0-4x1",
        "legacy-e0dc03d0-00000000-fs0-4x1",
    ],
}
(tmp_dir / "duplicate-review.json").write_text(json.dumps(duplicate_review, indent=2) + "\n")
PY

python3 "$REPO_ROOT/tools/hires_pack_apply_duplicate_review.py" \
  --loader-manifest "$TMP_DIR/loader-manifest.json" \
  --duplicate-review "$TMP_DIR/duplicate-review.json" \
  --output-dir "$TMP_DIR/output"

python3 - "$TMP_DIR/output/loader-manifest.json" "$TMP_DIR/output/package/package-manifest.json" "$TMP_DIR/output/package.phrb" <<'PY'
import json
import sys
from pathlib import Path

loader_manifest = json.loads(Path(sys.argv[1]).read_text())
package_manifest = json.loads(Path(sys.argv[2]).read_text())
binary_path = Path(sys.argv[3])

record = loader_manifest["records"][0]
if record.get("asset_candidate_count") != 2:
    raise SystemExit(f"FAIL: unexpected deduped asset_candidate_count {record!r}.")
replacement_ids = [candidate.get("replacement_id") for candidate in record.get("asset_candidates") or []]
if replacement_ids != [
    "legacy-844144ad-00000000-fs0-4x1",
    "legacy-2cf87740-00000000-fs0-4x1",
]:
    raise SystemExit(f"FAIL: unexpected deduped replacement ids {replacement_ids!r}.")

package_record = package_manifest["records"][0]
if package_record.get("duplicate_pixel_group_count") != 1:
    raise SystemExit(f"FAIL: expected broader duplicate pixel group to remain after selector dedupe {package_record!r}.")
group_ids = (package_record.get("duplicate_pixel_groups") or [{}])[0].get("replacement_ids") or []
if group_ids != [
    "legacy-2cf87740-00000000-fs0-4x1",
    "legacy-844144ad-00000000-fs0-4x1",
]:
    raise SystemExit(f"FAIL: unexpected duplicate pixel group ids {group_ids!r}.")
if not binary_path.is_file() or binary_path.stat().st_size <= 0:
    raise SystemExit("FAIL: expected emitted binary package.")

print("emu_hires_pack_apply_duplicate_review_contract: PASS")
PY
