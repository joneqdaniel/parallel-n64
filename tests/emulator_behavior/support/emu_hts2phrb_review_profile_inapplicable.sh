#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-review-profile-inapplicable-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"
BUNDLE_DIR="$TMP_DIR/bundle"
TRACE_DIR="$BUNDLE_DIR/traces"
OUTPUT_DIR="$TMP_DIR/out"

mkdir -p "$TRACE_DIR"

python3 - "$CACHE_PATH" "$TRACE_DIR/hires-evidence.json" "$TMP_DIR/duplicate-review.json" "$TMP_DIR/alias-group-review.json" "$TMP_DIR/review-profile.json" <<'PY'
import gzip
import json
import struct
import sys
from pathlib import Path

cache_path = Path(sys.argv[1])
evidence_path = Path(sys.argv[2])
duplicate_review_path = Path(sys.argv[3])
alias_review_path = Path(sys.argv[4])
review_profile_path = Path(sys.argv[5])

TXCACHE_FORMAT_VERSION = 0x08000000
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401
GL_RGBA8 = 0x8058

texture_crc = 0x7701AC09
review_crc = 0x7701AC0A
palette_crc = 0x00000000
checksum64 = (palette_crc << 32) | texture_crc
formatsize = 768
payload = bytes([
    0x11, 0x22, 0x33, 0xFF,
    0x44, 0x55, 0x66, 0xFF,
    0x77, 0x88, 0x99, 0xFF,
    0xAA, 0xBB, 0xCC, 0xFF,
])

with gzip.open(cache_path, "wb") as fp:
    fp.write(struct.pack("<i", TXCACHE_FORMAT_VERSION))
    fp.write(struct.pack("<i", 0))
    fp.write(struct.pack("<Q", checksum64))
    fp.write(struct.pack("<IIIHHB", 2, 2, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, 1))
    fp.write(struct.pack("<H", formatsize))
    fp.write(struct.pack("<I", len(payload)))
    fp.write(payload)

evidence = {
    "ci_palette_probe": {
        "families": [],
        "usages": [],
        "emulated_tmem": [],
    },
    "sampled_object_probe": {
        "top_groups": [
            {
                "fields": {
                    "draw_class": "texrect",
                    "cycle": "1cycle",
                    "fmt": "0",
                    "siz": "3",
                    "off": "0",
                    "stride": "400",
                    "wh": "200x2",
                    "fs": str(formatsize),
                    "sampled_low32": f"{texture_crc:08x}",
                    "sampled_entry_pcrc": f"{palette_crc:08x}",
                    "sampled_sparse_pcrc": f"{palette_crc:08x}",
                    "sampled_entry_count": "0",
                    "sampled_used_count": "0",
                },
                "upload_low32s": [{"value": f"{texture_crc:08x}"}],
                "upload_pcrcs": [{"value": f"{palette_crc:08x}"}],
            }
        ]
    }
}
evidence_path.write_text(json.dumps(evidence, indent=2) + "\n")

duplicate_review = {
    "sampled_low32": f"{review_crc:08x}",
    "selector": "0000000071c71cdd",
    "recommendation": "keep-runtime-winner-rule-and-defer-offline-dedupe",
    "duplicate_bucket": {
        "policy": f"surface-{review_crc:08x}",
        "replacement_id": f"legacy-{review_crc:08x}-00000000-fs{formatsize}-200x2",
    },
    "unique_selector_replacement_ids": [
        f"legacy-{review_crc:08x}-00000000-fs{formatsize}-200x2",
        f"legacy-{review_crc:08x}-11111111-fs{formatsize}-200x2",
    ],
}
duplicate_review_path.write_text(json.dumps(duplicate_review, indent=2) + "\n")

alias_review = {
    "sampled_low32": f"{review_crc:08x}",
    "policy_key": f"surface-{review_crc:08x}",
    "recommendation": "keep-selectors-distinct-and-consider-asset-level-dedupe",
    "suggested_canonical_replacement_id": f"legacy-{review_crc:08x}-00000000-fs{formatsize}-200x2",
    "suggested_alias_replacement_ids": [
        f"legacy-{review_crc:08x}-11111111-fs{formatsize}-200x2",
    ],
}
alias_review_path.write_text(json.dumps(alias_review, indent=2) + "\n")

review_profile = {
    "schema_version": 1,
    "duplicate_review_paths": [duplicate_review_path.name],
    "alias_group_review_paths": [alias_review_path.name],
}
review_profile_path.write_text(json.dumps(review_profile, indent=2) + "\n")
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$BUNDLE_DIR" \
  --review-profile "$TMP_DIR/review-profile.json" \
  --runtime-overlay-mode never \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR" \
  > "$TMP_DIR/result.json"

python3 - "$TMP_DIR/result.json" "$OUTPUT_DIR/hts2phrb-report.json" <<'PY'
import json
import sys
from pathlib import Path

result = json.loads(Path(sys.argv[1]).read_text())
report = json.loads(Path(sys.argv[2]).read_text())

for payload in (result, report):
    if payload.get("duplicate_review_change_count") != 0 or payload.get("alias_group_review_change_count") != 0:
        raise SystemExit(f"FAIL: inapplicable review inputs should not apply changes {payload!r}.")
    if payload.get("duplicate_review_skip_count") != 1 or payload.get("alias_group_review_skip_count") != 1:
        raise SystemExit(f"FAIL: inapplicable review inputs should be recorded as skipped {payload!r}.")

duplicate_skip = (report.get("duplicate_review_skips") or [{}])[0]
alias_skip = (report.get("alias_group_review_skips") or [{}])[0]
if duplicate_skip.get("skip_reason") != "record-not-in-scope":
    raise SystemExit(f"FAIL: expected duplicate skip reason record-not-in-scope, got {duplicate_skip!r}.")
if alias_skip.get("skip_reason") != "record-not-in-scope":
    raise SystemExit(f"FAIL: expected alias skip reason record-not-in-scope, got {alias_skip!r}.")
if duplicate_skip.get("record_resolution") != "record-not-in-scope":
    raise SystemExit(f"FAIL: expected duplicate review to stay out of scope, got {duplicate_skip!r}.")
if alias_skip.get("record_resolution") != "record-not-in-scope":
    raise SystemExit(f"FAIL: expected alias review to stay out of scope, got {alias_skip!r}.")
if report.get("package_manifest_record_count") != 1 or report.get("package_manifest_runtime_ready_record_count") != 1:
    raise SystemExit(f"FAIL: conversion should still emit the runtime-ready canonical record {report!r}.")
if not str(report.get("conversion_outcome") or "").endswith("runtime-package"):
    raise SystemExit(f"FAIL: expected runtime-capable conversion outcome, got {report.get('conversion_outcome')!r}.")
PY

echo "emu_hts2phrb_review_profile_inapplicable: PASS"
