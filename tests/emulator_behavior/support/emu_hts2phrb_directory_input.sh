#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-directory-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_DIR="$TMP_DIR/cache"
BUNDLE_DIR="$TMP_DIR/bundle"
TRACE_DIR="$BUNDLE_DIR/traces"
OUTPUT_DIR="$TMP_DIR/out"

mkdir -p "$CACHE_DIR" "$TRACE_DIR"

CURRENT_CACHE_PATH="$CACHE_DIR/PAPER MARIO_HIRESTEXTURES.htc"
ARCHIVE_CACHE_PATH="$CACHE_DIR/PAPER MARIO_HIRESTEXTURES.pre-v401-14774f23.htc"

python3 - "$CURRENT_CACHE_PATH" "$ARCHIVE_CACHE_PATH" "$TRACE_DIR/hires-evidence.json" <<'PY'
import gzip
import json
import struct
import sys
from pathlib import Path

current_cache_path = Path(sys.argv[1])
archive_cache_path = Path(sys.argv[2])
evidence_path = Path(sys.argv[3])

TXCACHE_FORMAT_VERSION = 0x08000000
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401
GL_RGBA8 = 0x8058


def write_htc(path: Path, texture_crc: int, palette_crc: int, formatsize: int):
    checksum64 = (palette_crc << 32) | texture_crc
    payload = bytes([
        0x10, 0x20, 0x30, 0xFF,
        0x40, 0x50, 0x60, 0xFF,
        0x70, 0x80, 0x90, 0xFF,
        0xA0, 0xB0, 0xC0, 0xFF,
    ])
    with gzip.open(path, "wb") as fp:
        fp.write(struct.pack("<i", TXCACHE_FORMAT_VERSION))
        fp.write(struct.pack("<i", 0))
        fp.write(struct.pack("<Q", checksum64))
        fp.write(struct.pack("<IIIHHB", 2, 2, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, 1))
        fp.write(struct.pack("<H", formatsize))
        fp.write(struct.pack("<I", len(payload)))
        fp.write(payload)


write_htc(current_cache_path, 0x11111111, 0xAAAABBBB, 258)
write_htc(archive_cache_path, 0x22222222, 0xCCCCDDDD, 258)

evidence = {
    "ci_palette_probe": {
        "families": [
            {
                "low32": "11111111",
                "fs": "258",
                "mode": "loadtile",
                "wh": "2x2",
                "pcrc": "aaaabbbb",
                "active_pool": "compatibility"
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
                    "sampled_low32": "11111111",
                    "sampled_entry_pcrc": "aaaabbbb",
                    "sampled_sparse_pcrc": "aaaabbbb",
                    "sampled_entry_count": "1",
                    "sampled_used_count": "1"
                },
                "upload_low32s": [
                    {"value": "11111111"}
                ],
                "upload_pcrcs": [
                    {"value": "aaaabbbb"}
                ]
            }
        ]
    }
}
evidence_path.write_text(json.dumps(evidence, indent=2) + "\n")
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_DIR" \
  --bundle "$BUNDLE_DIR" \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR"

python3 - "$OUTPUT_DIR" "$CACHE_DIR" "$CURRENT_CACHE_PATH" "$ARCHIVE_CACHE_PATH" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
cache_dir = Path(sys.argv[2])
current_cache_path = Path(sys.argv[3])
archive_cache_path = Path(sys.argv[4])

report = json.loads((out_dir / "hts2phrb-report.json").read_text())

if report["binding_count"] != 1 or report["unresolved_count"] != 0:
    raise SystemExit(f"unexpected binding state: {report!r}")
if report["cache_input_path"] != str(cache_dir):
    raise SystemExit(f"unexpected cache_input_path: {report['cache_input_path']!r}")
if report["cache_path"] != str(current_cache_path):
    raise SystemExit(f"unexpected resolved cache path: {report['cache_path']!r}")
if report["cache_input_kind"] != "directory":
    raise SystemExit(f"unexpected cache input kind: {report['cache_input_kind']!r}")
if report["cache_selection_reason"] != "directory-ranked-current-first":
    raise SystemExit(f"unexpected cache selection reason: {report['cache_selection_reason']!r}")
if report["resolved_cache_storage"] != "htc":
    raise SystemExit(f"unexpected resolved cache storage: {report['resolved_cache_storage']!r}")

resolution = report.get("cache_resolution") or {}
if resolution.get("candidate_count") != 2:
    raise SystemExit(f"unexpected candidate count: {resolution!r}")
if resolution.get("resolved_path") != str(current_cache_path):
    raise SystemExit(f"unexpected resolved path in resolution: {resolution!r}")
if resolution.get("candidate_paths") != [str(current_cache_path), str(archive_cache_path)]:
    raise SystemExit(f"unexpected candidate paths: {resolution.get('candidate_paths')!r}")

warnings = report.get("warnings") or []
if len(warnings) != 1 or "Resolved legacy cache input from 2 directory candidates" not in warnings[0]:
    raise SystemExit(f"unexpected warnings: {warnings!r}")
PY

echo "emu_hts2phrb_directory_input: PASS"
