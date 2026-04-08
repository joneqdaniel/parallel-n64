#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-context-groups-XXXXXX)"
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

texture_crc = 0x44444444
palette_crc = 0xABCD1234
checksum64 = (palette_crc << 32) | texture_crc

with gzip.open(cache_path, "wb") as fp:
    fp.write(struct.pack("<i", TXCACHE_FORMAT_VERSION))
    fp.write(struct.pack("<i", 0))
    payload = bytes([
        0x10, 0x20, 0x30, 0xFF,
        0x40, 0x50, 0x60, 0xFF,
        0x70, 0x80, 0x90, 0xFF,
        0xA0, 0xB0, 0xC0, 0xFF,
    ])
    fp.write(struct.pack("<Q", checksum64))
    fp.write(struct.pack("<IIIHHB", 2, 2, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, 1))
    fp.write(struct.pack("<H", 0))
    fp.write(struct.pack("<I", len(payload)))
    fp.write(payload)

evidence_path.write_text(json.dumps({
    "ci_palette_probe": {"families": [], "usages": [], "emulated_tmem": []},
    "sampled_object_probe": {
        "groups": [
            {
                "draw_class": "triangle",
                "cycle": "1cycle",
                "fmt": "2",
                "siz": "1",
                "off": "0",
                "stride": "2",
                "wh": "2x2",
                "fs": "258",
                "sampled_low32": "44444444",
                "sampled_entry_pcrc": "abcd1234",
                "sampled_sparse_pcrc": "abcd1234",
                "sampled_entry_count": "1",
                "sampled_used_count": "1",
                "upload_low32": "44444444",
                "upload_pcrc": "abcd1234"
            }
        ],
        "top_groups": []
    }
}, indent=2) + "\n")
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --context-bundle "$BUNDLE_DIR" \
  --stdout-format json \
  --output-dir "$OUT_DIR" \
  > "$TMP_DIR/report.json"

python3 - "$TMP_DIR/report.json" "$OUT_DIR/package/package-manifest.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text())
package_manifest = json.loads(Path(sys.argv[2]).read_text())

if report["conversion_outcome"] != "promotable-runtime-package":
    raise SystemExit(f"unexpected conversion outcome: {report['conversion_outcome']!r}")
records = package_manifest.get("records", [])
if len(records) != 1:
    raise SystemExit(f"unexpected record count: {len(records)}")
record = records[0]
if record.get("record_kind") not in {"canonical-sampled", "exact-authority-family"}:
    raise SystemExit(f"unexpected record kind: {record.get('record_kind')!r}")
identity = record.get("canonical_identity") or {}
if str(identity.get("sampled_low32") or "").lower() != "44444444":
    raise SystemExit(f"unexpected sampled_low32: {identity!r}")
expected_formatsize = 258 if record.get("record_kind") == "canonical-sampled" else 0
if int(identity.get("formatsize", -1)) != expected_formatsize:
    raise SystemExit(f"unexpected formatsize for {record.get('record_kind')!r}: {identity!r}")
PY

echo "emu_hts2phrb_context_bundle_groups_fallback: PASS"
