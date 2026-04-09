#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-absorbed-variants-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"
BUNDLE_DIR="$TMP_DIR/bundle"
OUT_DIR="$TMP_DIR/out"

mkdir -p "$BUNDLE_DIR/traces"

python3 - "$CACHE_PATH" "$BUNDLE_DIR/traces/hires-evidence.json" <<'PY'
import gzip
import json
import struct
import sys
from pathlib import Path

cache_path = Path(sys.argv[1])
evidence_path = Path(sys.argv[2])

TXCACHE_FORMAT_VERSION = 0x08000000
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401
GL_RGBA8 = 0x8058

records = [
    (0x11111111, 0xAAAABBBB, 0),
    (0x22222222, 0xAAAABBBB, 0),
]

payload = bytes([
    0x10, 0x20, 0x30, 0xFF,
    0x40, 0x50, 0x60, 0xFF,
    0x70, 0x80, 0x90, 0xFF,
    0xA0, 0xB0, 0xC0, 0xFF,
])

with gzip.open(cache_path, "wb") as fp:
    fp.write(struct.pack("<i", TXCACHE_FORMAT_VERSION))
    fp.write(struct.pack("<i", 0))
    for texture_crc, palette_crc, formatsize in records:
        checksum64 = (palette_crc << 32) | texture_crc
        fp.write(struct.pack("<Q", checksum64))
        fp.write(struct.pack("<IIIHHB", 2, 2, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, 1))
        fp.write(struct.pack("<H", formatsize))
        fp.write(struct.pack("<I", len(payload)))
        fp.write(payload)

evidence_path.write_text(json.dumps({
    "ci_palette_probe": {"families": [], "usages": [], "emulated_tmem": []},
    "sampled_object_probe": {
        "top_groups": [
            {
                "fields": {
                    "draw_class": "texrect",
                    "cycle": "copy",
                    "fmt": "2",
                    "siz": "1",
                    "off": "0",
                    "stride": "2",
                    "wh": "2x2",
                    "fs": "258",
                    "sampled_low32": "99999999",
                    "sampled_entry_pcrc": "aaaabbbb",
                    "sampled_sparse_pcrc": "aaaabbbb",
                    "sampled_entry_count": "2",
                    "sampled_used_count": "2"
                },
                "upload_low32s": [
                    {"value": "11111111"},
                    {"value": "22222222"}
                ],
                "upload_pcrcs": [{"value": "aaaabbbb"}]
            }
        ]
    }
}, indent=2) + "\n")
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --context-bundle "$BUNDLE_DIR" \
  --stdout-format json \
  --output-dir "$OUT_DIR" \
  > "$TMP_DIR/report.json"

python3 - "$TMP_DIR/report.json" "$OUT_DIR/package/package-manifest.json" "$OUT_DIR/hts2phrb-family-inventory.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text())
package_manifest = json.loads(Path(sys.argv[2]).read_text())
family_inventory = json.loads(Path(sys.argv[3]).read_text())

records = package_manifest.get("records", [])
if len(records) != 1:
    raise SystemExit(f"expected one package record, got {len(records)}")
record = records[0]
if record.get("record_kind") != "canonical-sampled":
    raise SystemExit(f"expected canonical-sampled record, got {record.get('record_kind')!r}")

identity = record.get("canonical_identity") or {}
if str(identity.get("sampled_low32") or "").lower() != "99999999":
    raise SystemExit(f"unexpected sampled_low32: {identity!r}")

asset_candidate_low32s = sorted(
    str(candidate.get("legacy_texture_crc") or "").lower()
    for candidate in record.get("asset_candidates") or []
)
if asset_candidate_low32s != ["11111111", "22222222"]:
    raise SystemExit(f"unexpected asset candidate low32s: {asset_candidate_low32s!r}")

runtime_state_counts = family_inventory.get("runtime_state_counts") or {}
if runtime_state_counts != {"runtime-ready-package": 2}:
    raise SystemExit(f"unexpected family inventory runtime state counts: {runtime_state_counts!r}")

families = sorted(
    (
        item.get("family_key"),
        item.get("import_state"),
        item.get("runtime_state"),
        int(item.get("canonical_record_count") or 0),
        bool(item.get("runtime_ready_package_record")),
    )
    for item in (family_inventory.get("families") or [])
)
expected = [
    ("11111111:fs0", "exact-authority", "runtime-ready-package", 1, True),
    ("22222222:fs0", "exact-authority", "runtime-ready-package", 1, True),
]
if families != expected:
    raise SystemExit(f"unexpected family inventory families: {families!r}")

report_runtime_state_counts = report.get("runtime_state_counts") or {}
if report_runtime_state_counts != {"runtime-ready-package": 2}:
    raise SystemExit(f"unexpected report runtime state counts: {report_runtime_state_counts!r}")

if report.get("promotion_blockers"):
    raise SystemExit(f"expected no promotion blockers, got {report.get('promotion_blockers')!r}")
PY

echo "emu_hts2phrb_family_inventory_absorbed_variants: PASS"
