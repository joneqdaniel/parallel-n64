#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-path-scope-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_DIR_A="$TMP_DIR/cache-a"
CACHE_DIR_B="$TMP_DIR/cache-b"
CACHE_PATH_A="$CACHE_DIR_A/sample.htc"
CACHE_PATH_B="$CACHE_DIR_B/sample.htc"

mkdir -p "$CACHE_DIR_A" "$CACHE_DIR_B"

python3 - "$CACHE_PATH_A" "$CACHE_PATH_B" <<'PY'
import gzip
import struct
import sys
from pathlib import Path

TXCACHE_FORMAT_VERSION = 0x08000000
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401
GL_RGBA8 = 0x8058


def write_cache(path: Path, texture_crc: int, palette_crc: int, formatsize: int) -> None:
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


write_cache(Path(sys.argv[1]), 0x11111111, 0xAAAABBBB, 258)
write_cache(Path(sys.argv[2]), 0x22222222, 0xCCCCDDDD, 514)
PY

pushd "$TMP_DIR" >/dev/null
python3 "$ROOT_DIR/tools/hts2phrb.py" --cache "$CACHE_PATH_A" > "$TMP_DIR/stdout-a.txt"
python3 "$ROOT_DIR/tools/hts2phrb.py" --cache "$CACHE_PATH_B" > "$TMP_DIR/stdout-b.txt"
popd >/dev/null

python3 - "$TMP_DIR" "$CACHE_PATH_A" "$CACHE_PATH_B" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

tmp_dir = Path(sys.argv[1])
cache_a = Path(sys.argv[2]).resolve()
cache_b = Path(sys.argv[3]).resolve()

def expected_output_dir(cache_path: Path) -> Path:
    path_tag = hashlib.sha1(str(cache_path).encode("utf-8")).hexdigest()[:8]
    return tmp_dir / "artifacts" / "hts2phrb" / f"sample-{path_tag}-all-families"

out_a = expected_output_dir(cache_a)
out_b = expected_output_dir(cache_b)
if out_a == out_b:
    raise SystemExit("expected distinct default output directories for same-named caches in different dirs")

report_a = json.loads((out_a / "hts2phrb-report.json").read_text())
report_b = json.loads((out_b / "hts2phrb-report.json").read_text())

if report_a["output_dir"] != str(out_a) or report_b["output_dir"] != str(out_b):
    raise SystemExit(f"unexpected output dirs: {report_a['output_dir']!r} {report_b['output_dir']!r}")
if report_a["cache_path"] != str(cache_a) or report_b["cache_path"] != str(cache_b):
    raise SystemExit(f"unexpected resolved cache paths: {report_a['cache_path']!r} {report_b['cache_path']!r}")
if report_a["output_dir"] == report_b["output_dir"]:
    raise SystemExit("same-named caches should not collide on default output dir")
if report_a["requested_family_count"] != 1 or report_b["requested_family_count"] != 1:
    raise SystemExit(f"unexpected family counts: {report_a['requested_family_count']} {report_b['requested_family_count']}")

stdout_a = (tmp_dir / "stdout-a.txt").read_text()
stdout_b = (tmp_dir / "stdout-b.txt").read_text()
if f"output_dir: {out_a}" not in stdout_a or f"output_dir: {out_b}" not in stdout_b:
    raise SystemExit("stdout summaries did not report path-scoped default output dirs")
PY

echo "emu_hts2phrb_path_scoped_defaults: PASS"
