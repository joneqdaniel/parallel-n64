#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-scale-equivalent-XXXXXX)"
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

texture_crc = 0x22222222
base_pixels = [
    (0x10, 0x20, 0x30, 0xFF),
    (0x40, 0x50, 0x60, 0xFF),
    (0x70, 0x80, 0x90, 0xFF),
    (0xA0, 0xB0, 0xC0, 0xFF),
]
payload_2x2 = bytes(channel for pixel in base_pixels for channel in pixel)

payload_4x4 = bytearray()
for row in range(2):
    left = base_pixels[row * 2]
    right = base_pixels[row * 2 + 1]
    expanded_row = [left, left, right, right]
    for _ in range(2):
        for pixel in expanded_row:
            payload_4x4.extend(pixel)

records = [
    (0xAAAABBBB, 258, 2, 2, payload_2x2),
    (0xCCCCDDDD, 258, 4, 4, bytes(payload_4x4)),
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

python3 - "$TMP_DIR/report.json" "$OUTPUT_DIR/migration-plan.json" "$OUTPUT_DIR/hts2phrb-unresolved-family-review.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text())
migration = json.loads(Path(sys.argv[2]).read_text())
review = json.loads(Path(sys.argv[3]).read_text())

if report["conversion_outcome"] != "promotable-runtime-package":
    raise SystemExit(f"unexpected conversion outcome: {report['conversion_outcome']!r}")
if report.get("import_state_counts") != {"exact-authority": 1}:
    raise SystemExit(f"unexpected import state counts: {report.get('import_state_counts')!r}")
if report.get("runtime_state_counts") != {"runtime-ready-package": 1}:
    raise SystemExit(f"unexpected runtime state counts: {report.get('runtime_state_counts')!r}")
if report.get("promotion_blockers") != []:
    raise SystemExit(f"unexpected promotion blockers: {report.get('promotion_blockers')!r}")
if report.get("promotion_blocker_reason_counts") != {}:
    raise SystemExit(f"unexpected promotion blocker reason counts: {report.get('promotion_blocker_reason_counts')!r}")
if report.get("package_manifest_runtime_ready_record_count") != 1:
    raise SystemExit(f"unexpected runtime-ready record count: {report.get('package_manifest_runtime_ready_record_count')!r}")
if report.get("unresolved_count") != 0:
    raise SystemExit(f"unexpected unresolved count: {report.get('unresolved_count')!r}")

imported_index = migration.get("imported_index") or {}
exact_authorities = imported_index.get("exact_authorities") or []
if len(exact_authorities) != 1:
    raise SystemExit(f"unexpected exact authority entries: {exact_authorities!r}")
if imported_index.get("unresolved_families") != []:
    raise SystemExit(f"unexpected unresolved families: {imported_index.get('unresolved_families')!r}")

family = exact_authorities[0]
selector_policy = family.get("selector_policy") or {}
if selector_policy.get("selection_reason") != "exact-scale-equivalent":
    raise SystemExit(f"unexpected selector policy: {selector_policy!r}")
if selector_policy.get("selected_variant_group_id") != "legacy-low32-22222222-fs258-4x4":
    raise SystemExit(f"unexpected selected variant group: {selector_policy!r}")
if family.get("candidate_replacement_ids") != ["legacy-22222222-ccccdddd-fs258-4x4"]:
    raise SystemExit(f"unexpected candidate replacements: {family.get('candidate_replacement_ids')!r}")

selection_review = (family.get("diagnostics") or {}).get("scale_equivalent_selection") or {}
if selection_review.get("collapsed_variant_group_dims") != ["2x2", "4x4"]:
    raise SystemExit(f"unexpected scale-equivalent diagnostics: {selection_review!r}")
if selection_review.get("selected_dims") != "4x4":
    raise SystemExit(f"unexpected selected dims: {selection_review!r}")
if selection_review.get("smaller_dims") != "2x2":
    raise SystemExit(f"unexpected smaller dims: {selection_review!r}")
if selection_review.get("scale_x") != 2 or selection_review.get("scale_y") != 2:
    raise SystemExit(f"unexpected scale factors: {selection_review!r}")

if review.get("unresolved_family_count") != 0:
    raise SystemExit(f"unexpected unresolved family review: {review!r}")
PY

echo "emu_hts2phrb_exact_scale_equivalent_collapse: PASS"
