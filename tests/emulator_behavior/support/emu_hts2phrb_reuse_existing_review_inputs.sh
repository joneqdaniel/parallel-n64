#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-reuse-review-inputs-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"
BUNDLE_DIR="$TMP_DIR/bundle"
TRACE_DIR="$BUNDLE_DIR/traces"
OUTPUT_DIR="$TMP_DIR/out"

mkdir -p "$TRACE_DIR"

python3 - "$CACHE_PATH" "$TRACE_DIR/hires-evidence.json" "$TMP_DIR/duplicate-review.json" "$TMP_DIR/alias-group-review.json" <<'PY'
import gzip
import json
import struct
import sys
from pathlib import Path

cache_path = Path(sys.argv[1])
evidence_path = Path(sys.argv[2])
duplicate_review_path = Path(sys.argv[3])
alias_review_path = Path(sys.argv[4])

TXCACHE_FORMAT_VERSION = 0x08000000
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401
GL_RGBA8 = 0x8058

texture_crc = 0x11111111
formatsize = 258
entries = [
    (0xAAAABBBB, bytes([
        0x10, 0x20, 0x30, 0xFF,
        0x40, 0x50, 0x60, 0xFF,
        0x70, 0x80, 0x90, 0xFF,
        0xA0, 0xB0, 0xC0, 0xFF,
    ])),
    (0xCCCCDDDD, bytes([
        0x10, 0x20, 0x30, 0xFF,
        0x40, 0x50, 0x60, 0xFF,
        0x70, 0x80, 0x90, 0xFF,
        0xA0, 0xB0, 0xC0, 0xFF,
    ])),
    (0xEEEEFFFF, bytes([
        0x10, 0x20, 0x30, 0xFF,
        0x40, 0x50, 0x60, 0xFF,
        0x70, 0x80, 0x90, 0xFF,
        0xA0, 0xB0, 0xC0, 0xFF,
    ])),
]

with gzip.open(cache_path, "wb") as fp:
    fp.write(struct.pack("<i", TXCACHE_FORMAT_VERSION))
    fp.write(struct.pack("<i", 0))
    for palette_crc, payload in entries:
        checksum64 = (palette_crc << 32) | texture_crc
        fp.write(struct.pack("<Q", checksum64))
        fp.write(struct.pack("<IIIHHB", 2, 2, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, 1))
        fp.write(struct.pack("<H", formatsize))
        fp.write(struct.pack("<I", len(payload)))
        fp.write(payload)

evidence = {
    "ci_palette_probe": {
        "families": [
            {
                "low32": f"{texture_crc:08x}",
                "fs": str(formatsize),
                "mode": "loadtile",
                "wh": "2x2",
                "pcrc": f"{entries[0][0]:08x}",
                "active_pool": "exact",
            }
        ],
        "usages": [],
        "emulated_tmem": [],
    },
    "sampled_object_probe": {
        "top_groups": [
            {
                "fields": {
                    "draw_class": "texrect",
                    "cycle": "1cycle",
                    "fmt": "2",
                    "siz": "1",
                    "off": "0",
                    "stride": "2",
                    "wh": "2x2",
                    "fs": str(formatsize),
                    "sampled_low32": f"{texture_crc:08x}",
                    "sampled_entry_pcrc": f"{entries[0][0]:08x}",
                    "sampled_sparse_pcrc": f"{entries[0][0]:08x}",
                    "sampled_entry_count": "1",
                    "sampled_used_count": "1",
                },
                "upload_low32s": [{"value": f"{texture_crc:08x}"}],
                "upload_pcrcs": [{"value": f"{entries[0][0]:08x}"}],
            }
        ]
    },
}
evidence_path.write_text(json.dumps(evidence, indent=2) + "\n")

policy_key = f"legacy-low32-{texture_crc:08x}-fs{formatsize}"
kept_a = f"legacy-{texture_crc:08x}-{entries[0][0]:08x}-fs{formatsize}-2x2"
drop_b = f"legacy-{texture_crc:08x}-{entries[1][0]:08x}-fs{formatsize}-2x2"
alias_c = f"legacy-{texture_crc:08x}-{entries[2][0]:08x}-fs{formatsize}-2x2"

duplicate_review = {
    "sampled_low32": f"{texture_crc:08x}",
    "selector": "0000000000000000",
    "recommendation": "keep-runtime-winner-rule-and-defer-offline-dedupe",
    "duplicate_bucket": {
        "policy": policy_key,
        "replacement_id": kept_a,
    },
    "unique_selector_replacement_ids": [kept_a, drop_b],
}
duplicate_review_path.write_text(json.dumps(duplicate_review, indent=2) + "\n")

alias_review = {
    "sampled_low32": f"{texture_crc:08x}",
    "policy_key": policy_key,
    "recommendation": "keep-selectors-distinct-and-consider-asset-level-dedupe",
    "suggested_canonical_replacement_id": kept_a,
    "suggested_alias_replacement_ids": [alias_c],
}
alias_review_path.write_text(json.dumps(alias_review, indent=2) + "\n")
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$BUNDLE_DIR" \
  --runtime-overlay-mode never \
  --duplicate-review "$TMP_DIR/duplicate-review.json" \
  --alias-group-review "$TMP_DIR/alias-group-review.json" \
  --reuse-existing \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR" \
  > "$TMP_DIR/first.json"

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$BUNDLE_DIR" \
  --runtime-overlay-mode never \
  --duplicate-review "$TMP_DIR/duplicate-review.json" \
  --alias-group-review "$TMP_DIR/alias-group-review.json" \
  --reuse-existing \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR" \
  > "$TMP_DIR/second.json"

python3 - "$TMP_DIR/alias-group-review.json" <<'PY'
import json
import sys
from pathlib import Path

review_path = Path(sys.argv[1])
review = json.loads(review_path.read_text())
review["suggested_canonical_replacement_id"] = "legacy-11111111-eeeeffff-fs258-2x2"
review["suggested_alias_replacement_ids"] = ["legacy-11111111-aaaabbbb-fs258-2x2"]
review_path.write_text(json.dumps(review, indent=2) + "\n")
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$BUNDLE_DIR" \
  --runtime-overlay-mode never \
  --duplicate-review "$TMP_DIR/duplicate-review.json" \
  --alias-group-review "$TMP_DIR/alias-group-review.json" \
  --reuse-existing \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR" \
  > "$TMP_DIR/third.json"

python3 - "$TMP_DIR/first.json" "$TMP_DIR/second.json" "$TMP_DIR/third.json" "$OUTPUT_DIR/loader-manifest.json" <<'PY'
import json
import sys
from pathlib import Path

first = json.loads(Path(sys.argv[1]).read_text())
second = json.loads(Path(sys.argv[2]).read_text())
third = json.loads(Path(sys.argv[3]).read_text())
loader_manifest = json.loads(Path(sys.argv[4]).read_text())

if first.get("reused_existing"):
    raise SystemExit(f"FAIL: initial conversion should not be reused, got {first!r}.")
if not second.get("reused_existing"):
    raise SystemExit(f"FAIL: unchanged review inputs should reuse existing output, got {second!r}.")
if third.get("reused_existing"):
    raise SystemExit(f"FAIL: changed alias review should invalidate reuse, got {third!r}.")

if second.get("duplicate_review_change_count") != 1 or third.get("duplicate_review_change_count") != 1:
    raise SystemExit(f"FAIL: unexpected duplicate review change counts second={second!r} third={third!r}.")
if second.get("alias_group_review_change_count") != 1 or third.get("alias_group_review_change_count") != 1:
    raise SystemExit(f"FAIL: unexpected alias review change counts second={second!r} third={third!r}.")

record = loader_manifest["records"][0]
replacement_ids = [candidate.get("replacement_id") for candidate in (record.get("asset_candidates") or [])]
if replacement_ids != [
    "legacy-11111111-eeeeffff-fs258-2x2",
    "legacy-11111111-eeeeffff-fs258-2x2",
]:
    raise SystemExit(f"FAIL: mutated alias review did not rebuild to the new canonical pair {replacement_ids!r}.")

print("emu_hts2phrb_reuse_existing_review_inputs: PASS")
PY
