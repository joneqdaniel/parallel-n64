#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-bundle-scoped-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"
RUN_A_ROOT="$TMP_DIR/run-a"
RUN_B_ROOT="$TMP_DIR/run-b"
RUN_A_BUNDLE_DIR="$RUN_A_ROOT/bundle"
RUN_B_BUNDLE_DIR="$RUN_B_ROOT/bundle"
RUN_A_TRACE_DIR="$RUN_A_BUNDLE_DIR/traces"
RUN_B_TRACE_DIR="$RUN_B_BUNDLE_DIR/traces"
RUN_A_SUMMARY="$RUN_A_ROOT/validation-summary.json"
RUN_B_SUMMARY="$RUN_B_ROOT/validation-summary.json"

mkdir -p "$RUN_A_TRACE_DIR" "$RUN_B_TRACE_DIR"

python3 - "$CACHE_PATH" "$RUN_A_TRACE_DIR/hires-evidence.json" "$RUN_B_TRACE_DIR/hires-evidence.json" "$RUN_A_SUMMARY" "$RUN_B_SUMMARY" <<'PY'
import gzip
import json
import struct
import sys
from pathlib import Path

cache_path = Path(sys.argv[1])
evidence_a = Path(sys.argv[2])
evidence_b = Path(sys.argv[3])
summary_a = Path(sys.argv[4])
summary_b = Path(sys.argv[5])

TXCACHE_FORMAT_VERSION = 0x08000000
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401
GL_RGBA8 = 0x8058

texture_crc = 0x11111111
palette_crc = 0xAAAABBBB
checksum64 = (palette_crc << 32) | texture_crc
formatsize = 258
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
                "pcrc": f"{palette_crc:08x}",
                "active_pool": "compatibility",
            }
        ],
        "usages": [],
        "emulated_tmem": [],
    }
}
for target in (evidence_a, evidence_b):
    target.write_text(json.dumps(evidence, indent=2) + "\n")

summary = {
    "cache_path": "dummy.phrb",
    "steps": [
        {
            "step_frames": 960,
            "off_bundle": "bundle",
            "on_bundle": "bundle",
        }
    ],
}
summary_a.write_text(json.dumps(summary, indent=2) + "\n")
summary_b.write_text(json.dumps(summary, indent=2) + "\n")
PY

pushd "$TMP_DIR" >/dev/null
python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$RUN_A_SUMMARY" \
  --stdout-format json \
  > "$TMP_DIR/run-a-report.json"

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$RUN_B_SUMMARY" \
  --stdout-format json \
  > "$TMP_DIR/run-b-report.json"
popd >/dev/null

python3 - "$TMP_DIR" "$CACHE_PATH" "$RUN_A_BUNDLE_DIR" "$RUN_B_BUNDLE_DIR" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

tmp_dir = Path(sys.argv[1])
cache_path = Path(sys.argv[2]).resolve()
bundle_a = Path(sys.argv[3]).resolve()
bundle_b = Path(sys.argv[4]).resolve()

report_a = json.loads((tmp_dir / "run-a-report.json").read_text())
report_b = json.loads((tmp_dir / "run-b-report.json").read_text())

cache_tag = hashlib.sha1(str(cache_path).encode("utf-8")).hexdigest()[:8]
bundle_a_tag = hashlib.sha1(str(bundle_a).encode("utf-8")).hexdigest()[:8]
bundle_b_tag = hashlib.sha1(str(bundle_b).encode("utf-8")).hexdigest()[:8]

expected_a = tmp_dir / "artifacts" / "hts2phrb" / f"sample-{cache_tag}-bundle-bundle-{bundle_a_tag}"
expected_b = tmp_dir / "artifacts" / "hts2phrb" / f"sample-{cache_tag}-bundle-bundle-{bundle_b_tag}"

if expected_a == expected_b:
    raise SystemExit("expected distinct default output directories for distinct bundle roots")
if report_a["output_dir"] != str(expected_a):
    raise SystemExit(f"unexpected output dir for run A: {report_a['output_dir']!r}")
if report_b["output_dir"] != str(expected_b):
    raise SystemExit(f"unexpected output dir for run B: {report_b['output_dir']!r}")
if report_a["resolved_bundle_path"] != str(bundle_a):
    raise SystemExit(f"unexpected resolved bundle path for run A: {report_a['resolved_bundle_path']!r}")
if report_b["resolved_bundle_path"] != str(bundle_b):
    raise SystemExit(f"unexpected resolved bundle path for run B: {report_b['resolved_bundle_path']!r}")
if report_a["output_dir"] == report_b["output_dir"]:
    raise SystemExit(f"bundle-scoped defaults collided: {report_a['output_dir']!r}")
if report_a["bundle_resolution"].get("bundle_reference_mode") != "summary-relative":
    raise SystemExit(f"unexpected bundle reference mode for run A: {report_a['bundle_resolution']!r}")
if report_b["bundle_resolution"].get("bundle_reference_mode") != "summary-relative":
    raise SystemExit(f"unexpected bundle reference mode for run B: {report_b['bundle_resolution']!r}")
PY

echo "emu_hts2phrb_bundle_scoped_defaults: PASS"
