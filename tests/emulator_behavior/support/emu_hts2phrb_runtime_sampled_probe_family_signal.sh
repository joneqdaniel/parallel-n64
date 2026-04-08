#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-sampled-signal-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"
BUNDLE_DIR="$TMP_DIR/bundle"
TRACE_DIR="$BUNDLE_DIR/traces"
OUT_DIR="$TMP_DIR/out"

mkdir -p "$TRACE_DIR"

python3 - "$CACHE_PATH" "$TRACE_DIR/hires-evidence.json" <<'PY'
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
    (0x11111111, 0xAAAABBBB, 258),
    (0x22222222, 0xCCCCDDDD, 258),
]

with gzip.open(cache_path, "wb") as fp:
    fp.write(struct.pack("<i", TXCACHE_FORMAT_VERSION))
    fp.write(struct.pack("<i", 0))
    for texture_crc, palette_crc, formatsize in records:
        checksum64 = (palette_crc << 32) | texture_crc
        payload = bytes([
            0x10, 0x20, 0x30, 0xFF,
            0x40, 0x50, 0x60, 0xFF,
            0x70, 0x80, 0x90, 0xFF,
            0xA0, 0xB0, 0xC0, 0xFF,
        ])
        fp.write(struct.pack("<Q", checksum64))
        fp.write(struct.pack("<IIIHHB", 2, 2, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, 1))
        fp.write(struct.pack("<H", formatsize))
        fp.write(struct.pack("<I", len(payload)))
        fp.write(payload)

evidence = {
    "ci_palette_probe": {
        "families": [
            {
                "low32": "11111111",
                "fs": "258",
                "mode": "loadtile",
                "wh": "2x2",
                "pcrc": "aaaabbbb",
                "active_pool": "exact"
            },
            {
                "low32": "22222222",
                "fs": "258",
                "mode": "loadtile",
                "wh": "2x2",
                "pcrc": "ccccdddd",
                "active_pool": "exact"
            }
        ],
        "usages": [],
        "emulated_tmem": []
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
                    "fs": "258",
                    "sampled_low32": "aaaaaaaa",
                    "sampled_entry_pcrc": "aaaabbbb",
                    "sampled_sparse_pcrc": "aaaabbbb",
                    "sampled_entry_count": "1",
                    "sampled_used_count": "1",
                    "entry_hit": "0",
                    "sparse_hit": "0",
                    "family": "1",
                    "unique_repl_dims": "1",
                    "sample_repl": "2x2"
                },
                "upload_low32s": [{"value": "11111111"}],
                "upload_pcrcs": [{"value": "aaaabbbb"}]
            },
            {
                "fields": {
                    "draw_class": "triangle",
                    "cycle": "1cycle",
                    "fmt": "2",
                    "siz": "0",
                    "off": "0",
                    "stride": "16",
                    "wh": "32x32",
                    "fs": "2",
                    "sampled_low32": "bbbbbbbb",
                    "sampled_entry_pcrc": "12345678",
                    "sampled_sparse_pcrc": "87654321",
                    "sampled_entry_count": "8",
                    "sampled_used_count": "4",
                    "entry_hit": "0",
                    "sparse_hit": "0",
                    "family": "0",
                    "unique_repl_dims": "0",
                    "sample_repl": "0x0"
                },
                "upload_low32s": [{"value": "22222222"}],
                "upload_pcrcs": [{"value": "ccccdddd"}]
            }
        ]
    }
}

evidence_path.write_text(json.dumps(evidence, indent=2) + "\n")
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$BUNDLE_DIR" \
  --stdout-format json \
  --output-dir "$OUT_DIR" \
  > "$TMP_DIR/report.json"

python3 - "$TMP_DIR/report.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text())

if report["conversion_outcome"] != "promotable-runtime-package":
    raise SystemExit(f"unexpected conversion outcome: {report['conversion_outcome']!r}")
if report["requested_family_count"] != 2:
    raise SystemExit(f"unexpected requested family count: {report['requested_family_count']!r}")
if report["package_manifest_runtime_ready_native_sampled_record_count"] != 1:
    raise SystemExit(
        f"unexpected native sampled record count: {report['package_manifest_runtime_ready_native_sampled_record_count']!r}"
    )
if report["package_manifest_runtime_ready_compat_record_count"] != 1:
    raise SystemExit(
        f"unexpected compat runtime-ready record count: {report['package_manifest_runtime_ready_compat_record_count']!r}"
    )
families = {item["family_key"]: item for item in report["requested_family_states"]["families"]}
safe = families.get("11111111:fs258")
unsafe = families.get("22222222:fs258")
if safe is None or unsafe is None:
    raise SystemExit(f"missing requested family states: {families!r}")
if safe["canonical_record_count"] != 1 or not safe["runtime_ready_package_record"]:
    raise SystemExit(f"safe family did not promote as expected: {safe!r}")
if unsafe["canonical_record_count"] != 1 or not unsafe["runtime_ready_package_record"]:
    raise SystemExit(f"unsafe family did not remain runtime-ready via compat path as expected: {unsafe!r}")

manifest = json.loads(Path(report["output_dir"]).joinpath("package", "package-manifest.json").read_text())
canonical_sampled = [
    record for record in manifest["records"]
    if record.get("record_kind") == "canonical-sampled"
]
if len(canonical_sampled) != 1:
    raise SystemExit(f"unexpected canonical sampled record count in manifest: {len(canonical_sampled)!r}")
record = canonical_sampled[0]
if record.get("policy_key") != "legacy-low32-11111111-fs258":
    raise SystemExit(f"unexpected promoted policy key: {record!r}")
if record.get("sampled_object_id") != "sampled-fmt2-siz1-off0-stride2-wh2x2-fs258-low32aaaaaaaa":
    raise SystemExit(f"unexpected promoted sampled object id: {record!r}")
PY

echo "emu_hts2phrb_runtime_sampled_probe_family_signal: PASS"
