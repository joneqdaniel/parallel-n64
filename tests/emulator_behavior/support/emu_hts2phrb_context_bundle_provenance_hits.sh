#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-context-provenance-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"
BUNDLE_DIR="$TMP_DIR/bundle"
OUT_DIR="$TMP_DIR/out"

mkdir -p "$BUNDLE_DIR/traces" "$BUNDLE_DIR/logs"

python3 - "$CACHE_PATH" "$BUNDLE_DIR/traces/hires-evidence.json" "$BUNDLE_DIR/logs/retroarch.log" <<'PY'
import gzip
import json
import struct
import sys
from pathlib import Path

cache_path = Path(sys.argv[1])
evidence_path = Path(sys.argv[2])
log_path = Path(sys.argv[3])

TXCACHE_FORMAT_VERSION = 0x08000000
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401
GL_RGBA8 = 0x8058

texture_crc = 0x44444444
palette_crc = 0x00000000
checksum64 = (palette_crc << 32) | texture_crc
formatsize = 259
payload = bytes([
    0x10, 0x20, 0x30, 0xFF,
    0x40, 0x50, 0x60, 0xFF,
    0x70, 0x80, 0x90, 0xFF,
    0xA0, 0xB0, 0xC0, 0xFF,
])

with gzip.open(cache_path, "wb") as fp:
    fp.write(struct.pack("<i", TXCACHE_FORMAT_VERSION))
    fp.write(struct.pack("<i", 0))
    fp.write(struct.pack("<Q", checksum64))
    fp.write(struct.pack("<IIIHHB", 16, 8, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, 1))
    fp.write(struct.pack("<H", formatsize))
    fp.write(struct.pack("<I", len(payload)))
    fp.write(payload)

evidence = {
    "log_path": str(log_path),
    "ci_palette_probe": {
        "families": [
            {
                "low32": f"{texture_crc:08x}",
                "fs": str(formatsize),
                "mode": "loadtile",
                "wh": "16x8",
                "pcrc": "00000000",
                "active_pool": "exact",
            }
        ],
        "usages": [],
        "emulated_tmem": [],
    },
    "sampled_object_probe": {
        "top_groups": []
    },
    "provenance": {
        "top_buckets": []
    }
}
evidence_path.write_text(json.dumps(evidence, indent=2) + "\n")
log_path.write_text(
    "Hi-res keying provenance: "
    "outcome=hit source_class=authored-rdram provenance_class=loadtile "
    "mode=tile addr=0x24b400 tile=7 fmt=3 siz=1 pal=0 wh=16x8 "
    "key=0000000044444444 pcrc=00000000 fs=259 upload=tile cycle=2cycle copy=0 "
    "tlut=0 tlut_type=0 framebuffer=0 color_fb=0 depth_fb=0 tmem=0x800 line=16 key_xy=0x0\n"
)
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
if report["runtime_overlay_built"]:
    raise SystemExit(f"did not expect runtime overlay build: {report!r}")
if report["runtime_overlay_reason"] != "no-runtime-context":
    raise SystemExit(f"unexpected runtime overlay reason: {report['runtime_overlay_reason']!r}")

imported = report.get("imported_index_summary") or {}
if imported.get("exact_authority_count") != 1:
    raise SystemExit(f"unexpected imported exact-authority count: {imported!r}")
if imported.get("canonical_sampled_record_count") != 1:
    raise SystemExit(f"expected one canonical sampled record, got {imported!r}")
if imported.get("canonical_runtime_ready_count") != 1:
    raise SystemExit(f"expected one runtime-ready canonical record, got {imported!r}")

if report["package_manifest_runtime_ready_native_sampled_record_count"] != 1:
    raise SystemExit(
        f"expected one runtime-ready native-sampled record, got {report['package_manifest_runtime_ready_native_sampled_record_count']!r}"
    )
if report["package_manifest_runtime_ready_compat_record_count"] != 0:
    raise SystemExit(
        f"expected zero runtime-ready compat records, got {report['package_manifest_runtime_ready_compat_record_count']!r}"
    )

records = package_manifest.get("records", [])
if len(records) != 1:
    raise SystemExit(f"unexpected package records: {records!r}")
record = records[0]
if record.get("record_kind") != "canonical-sampled":
    raise SystemExit(f"expected canonical-sampled record, got {record.get('record_kind')!r}")
identity = record.get("canonical_identity") or {}
if int(identity.get("fmt") or -1) != 3 or int(identity.get("siz") or -1) != 1:
    raise SystemExit(f"unexpected canonical fmt/siz: {identity!r}")
if int(identity.get("off") or -1) != 2048 or int(identity.get("stride") or -1) != 16:
    raise SystemExit(f"unexpected canonical off/stride: {identity!r}")
if str(identity.get("wh") or "") != "16x8":
    raise SystemExit(f"unexpected canonical wh: {identity!r}")
if int(identity.get("formatsize") or -1) != 259:
    raise SystemExit(f"unexpected canonical formatsize: {identity!r}")
if str(identity.get("sampled_low32") or "").lower() != "44444444":
    raise SystemExit(f"unexpected sampled_low32: {identity!r}")
if not record.get("runtime_ready"):
    raise SystemExit(f"expected runtime_ready canonical record: {record!r}")
PY

echo "emu_hts2phrb_context_bundle_provenance_hits: PASS"
