#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-unresolved-review-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"
OUTPUT_DIR="$TMP_DIR/out"

python3 - "$CACHE_PATH" <<'PY'
import gzip
import struct
import sys
from pathlib import Path

cache_path = Path(sys.argv[1])

TXCACHE_FORMAT_VERSION = 0x08000000
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401
GL_RGBA8 = 0x8058

texture_crc = 0x11111111
records = [
    (0xAAAABBBB, 258, 2, 2, bytes([
        0x10, 0x20, 0x30, 0xFF,
        0x40, 0x50, 0x60, 0xFF,
        0x70, 0x80, 0x90, 0xFF,
        0xA0, 0xB0, 0xC0, 0xFF,
    ])),
    (0xCCCCDDDD, 258, 4, 4, bytes([
        0x01, 0x02, 0x03, 0xFF,
        0x04, 0x05, 0x06, 0xFF,
        0x07, 0x08, 0x09, 0xFF,
        0x0A, 0x0B, 0x0C, 0xFF,
        0x0D, 0x0E, 0x0F, 0xFF,
        0x11, 0x12, 0x13, 0xFF,
        0x14, 0x15, 0x16, 0xFF,
        0x17, 0x18, 0x19, 0xFF,
        0x1A, 0x1B, 0x1C, 0xFF,
        0x1D, 0x1E, 0x1F, 0xFF,
        0x21, 0x22, 0x23, 0xFF,
        0x24, 0x25, 0x26, 0xFF,
        0x27, 0x28, 0x29, 0xFF,
        0x2A, 0x2B, 0x2C, 0xFF,
        0x2D, 0x2E, 0x2F, 0xFF,
        0x31, 0x32, 0x33, 0xFF,
    ])),
]

with gzip.open(cache_path, "wb") as fp:
    fp.write(struct.pack("<i", TXCACHE_FORMAT_VERSION))
    fp.write(struct.pack("<i", 0))
    for palette_crc, formatsize, width, height, payload in records:
        checksum64 = (palette_crc << 32) | texture_crc
        fp.write(struct.pack("<Q", checksum64))
        fp.write(struct.pack("<IIIHHB", width, height, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, 1))
        fp.write(struct.pack("<H", formatsize))
        fp.write(struct.pack("<I", len(payload)))
        fp.write(payload)
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --all-families \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR" \
  > "$TMP_DIR/report.json"

python3 - "$TMP_DIR/report.json" "$OUTPUT_DIR/hts2phrb-unresolved-family-review.json" "$OUTPUT_DIR/hts2phrb-unresolved-family-review.md" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text())
review_json_path = Path(sys.argv[2])
review_md_path = Path(sys.argv[3])
review = json.loads(review_json_path.read_text())
summary_text = Path(report["summary_path"]).read_text()

if report["conversion_outcome"] != "canonical-package-only":
    raise SystemExit(f"unexpected conversion outcome: {report['conversion_outcome']!r}")
if report.get("runtime_state_counts") != {"canonical-only": 1}:
    raise SystemExit(f"unexpected runtime state counts: {report.get('runtime_state_counts')!r}")
if report.get("promotion_blockers") != [{"code": "canonical-only-families", "count": 1}]:
    raise SystemExit(f"unexpected promotion blockers: {report.get('promotion_blockers')!r}")
if report.get("promotion_blocker_runtime_state_counts") != {"canonical-only": 1}:
    raise SystemExit(f"unexpected blocker runtime-state counts: {report.get('promotion_blocker_runtime_state_counts')!r}")
if report.get("promotion_blocker_reason_counts") != {"exact-family-ambiguous": 1}:
    raise SystemExit(f"unexpected blocker reason counts: {report.get('promotion_blocker_reason_counts')!r}")
if report.get("promotion_blocker_reason_unclassified_family_count") != 0:
    raise SystemExit(
        "unexpected blocker reason uncovered family count: "
        f"{report.get('promotion_blocker_reason_unclassified_family_count')!r}"
    )
if report.get("unresolved_family_review_json_path") != str(review_json_path):
    raise SystemExit(f"unexpected unresolved review json path: {report.get('unresolved_family_review_json_path')!r}")
if report.get("unresolved_family_review_markdown_path") != str(review_md_path):
    raise SystemExit(f"unexpected unresolved review markdown path: {report.get('unresolved_family_review_markdown_path')!r}")

if review.get("unresolved_family_count") != 1:
    raise SystemExit(f"unexpected unresolved family count: {review!r}")
if review.get("reason_counts") != {"exact-family-ambiguous": 1}:
    raise SystemExit(f"unexpected reason counts: {review.get('reason_counts')!r}")
if review.get("runtime_state_counts") != {"canonical-only": 1}:
    raise SystemExit(f"unexpected unresolved runtime-state counts: {review.get('runtime_state_counts')!r}")
if review.get("variant_group_count_counts") != {"2": 1}:
    raise SystemExit(f"unexpected variant group counts: {review.get('variant_group_count_counts')!r}")
if review.get("candidate_replacement_count_counts") != {"2": 1}:
    raise SystemExit(f"unexpected candidate replacement counts: {review.get('candidate_replacement_count_counts')!r}")
if review.get("canonical_sampled_object_count_counts") != {"0": 1}:
    raise SystemExit(f"unexpected sampled object counts: {review.get('canonical_sampled_object_count_counts')!r}")

families = review.get("families") or []
if len(families) != 1:
    raise SystemExit(f"unexpected unresolved family entries: {families!r}")
family = families[0]
if family.get("family_key") != "11111111:fs258":
    raise SystemExit(f"unexpected family key: {family!r}")
if family.get("variant_group_dims") != ["2x2", "4x4"]:
    raise SystemExit(f"unexpected variant dims: {family!r}")
if family.get("sampled_object_ids") != []:
    raise SystemExit(f"unexpected sampled object ids: {family!r}")

if "Unresolved family review" not in summary_text or "exact-family-ambiguous" not in summary_text:
    raise SystemExit(f"summary did not include unresolved review section: {summary_text!r}")
PY

echo "emu_hts2phrb_unresolved_family_review: PASS"
