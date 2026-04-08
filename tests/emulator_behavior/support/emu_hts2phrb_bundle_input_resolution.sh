#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-bundle-input-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"
BUNDLE_DIR="$TMP_DIR/bundle"
TRACE_DIR="$BUNDLE_DIR/traces"
SUMMARY_DIR="$TMP_DIR/summary-root"
SUMMARY_CWD_DIR="$TMP_DIR/summary-root-cwd"
SUMMARY_JSON="$SUMMARY_DIR/validation-summary.json"
SUMMARY_MD="$SUMMARY_DIR/validation-summary.md"
SUMMARY_CWD_JSON="$SUMMARY_CWD_DIR/validation-summary.json"
SUMMARY_CWD_MD="$SUMMARY_CWD_DIR/validation-summary.md"
OUT_EVIDENCE="$TMP_DIR/out-evidence"
OUT_SUMMARY_JSON="$TMP_DIR/out-summary-json"
OUT_SUMMARY_MD="$TMP_DIR/out-summary-md"
OUT_SUMMARY_CWD_JSON="$TMP_DIR/out-summary-cwd-json"
OUT_SUMMARY_CWD_MD="$TMP_DIR/out-summary-cwd-md"

mkdir -p "$TRACE_DIR" "$SUMMARY_DIR" "$SUMMARY_CWD_DIR"

python3 - "$CACHE_PATH" "$TRACE_DIR/hires-evidence.json" "$SUMMARY_JSON" "$SUMMARY_MD" "$SUMMARY_CWD_JSON" "$SUMMARY_CWD_MD" <<'PY'
import gzip
import json
import struct
import sys
from pathlib import Path

cache_path = Path(sys.argv[1])
evidence_path = Path(sys.argv[2])
summary_json = Path(sys.argv[3])
summary_md = Path(sys.argv[4])
summary_cwd_json = Path(sys.argv[5])
summary_cwd_md = Path(sys.argv[6])

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
                    "fs": str(formatsize),
                    "sampled_low32": f"{texture_crc:08x}",
                    "sampled_entry_pcrc": f"{palette_crc:08x}",
                    "sampled_sparse_pcrc": f"{palette_crc:08x}",
                    "sampled_entry_count": "1",
                    "sampled_used_count": "1"
                },
                "upload_low32s": [
                    {"value": f"{texture_crc:08x}"}
                ],
                "upload_pcrcs": [
                    {"value": f"{palette_crc:08x}"}
                ]
            }
        ]
    }
}
evidence_path.write_text(json.dumps(evidence, indent=2) + "\n")

summary = {
    "cache_path": "dummy.phrb",
    "steps": [
        {
            "step_frames": 960,
            "off_bundle": "../bundle",
            "on_bundle": "../bundle"
        }
    ]
}
summary_json.write_text(json.dumps(summary, indent=2) + "\n")
summary_md.write_text("# validation summary\n")

summary_cwd = {
    "cache_path": "dummy.phrb",
    "steps": [
        {
            "step_frames": 960,
            "off_bundle": "bundle",
            "on_bundle": "bundle"
        }
    ]
}
summary_cwd_json.write_text(json.dumps(summary_cwd, indent=2) + "\n")
summary_cwd_md.write_text("# validation summary cwd\n")
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$TRACE_DIR/hires-evidence.json" \
  --stdout-format json \
  --output-dir "$OUT_EVIDENCE" \
  > "$TMP_DIR/evidence.json"

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$SUMMARY_JSON" \
  --stdout-format json \
  --output-dir "$OUT_SUMMARY_JSON" \
  > "$TMP_DIR/summary.json"

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$SUMMARY_MD" \
  --stdout-format json \
  --output-dir "$OUT_SUMMARY_MD" \
  > "$TMP_DIR/summary-md.json"

pushd "$TMP_DIR" >/dev/null
python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$SUMMARY_CWD_JSON" \
  --stdout-format json \
  --output-dir "$OUT_SUMMARY_CWD_JSON" \
  > "$TMP_DIR/summary-cwd.json"

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$SUMMARY_CWD_MD" \
  --stdout-format json \
  --output-dir "$OUT_SUMMARY_CWD_MD" \
  > "$TMP_DIR/summary-cwd-md.json"
popd >/dev/null

python3 - "$TMP_DIR" "$BUNDLE_DIR" "$TRACE_DIR/hires-evidence.json" "$SUMMARY_JSON" "$SUMMARY_MD" "$SUMMARY_CWD_JSON" "$SUMMARY_CWD_MD" <<'PY'
import json
import sys
from pathlib import Path

tmp_dir = Path(sys.argv[1])
bundle_dir = Path(sys.argv[2])
hires_path = Path(sys.argv[3])
summary_json = Path(sys.argv[4])
summary_md = Path(sys.argv[5])
summary_cwd_json = Path(sys.argv[6])
summary_cwd_md = Path(sys.argv[7])

evidence = json.loads((tmp_dir / "evidence.json").read_text())
summary = json.loads((tmp_dir / "summary.json").read_text())
summary_md_report = json.loads((tmp_dir / "summary-md.json").read_text())
summary_cwd = json.loads((tmp_dir / "summary-cwd.json").read_text())
summary_cwd_md_report = json.loads((tmp_dir / "summary-cwd-md.json").read_text())

for report in (evidence, summary, summary_md_report, summary_cwd, summary_cwd_md_report):
    if report["binding_count"] != 1 or report["unresolved_count"] != 0:
        raise SystemExit(f"unexpected binding state: {report!r}")
    if report["resolved_bundle_path"] != str(bundle_dir):
        raise SystemExit(f"unexpected resolved bundle path: {report['resolved_bundle_path']!r}")

if evidence["bundle_resolution"]["input_kind"] != "hires-evidence-json":
    raise SystemExit(f"unexpected evidence bundle resolution: {evidence['bundle_resolution']!r}")
if evidence["bundle_resolution"]["resolved_hires_path"] != str(hires_path):
    raise SystemExit(f"unexpected evidence hires path: {evidence['bundle_resolution']!r}")

if summary["bundle_resolution"]["input_kind"] != "validation-summary":
    raise SystemExit(f"unexpected summary bundle resolution: {summary['bundle_resolution']!r}")
if summary["bundle_resolution"]["selection_reason"] != "validation-summary-single-step":
    raise SystemExit(f"unexpected summary selection reason: {summary['bundle_resolution']!r}")
if summary["bundle_resolution"]["selected_step_frames"] != 960:
    raise SystemExit(f"unexpected summary step selection: {summary['bundle_resolution']!r}")
if summary["bundle_path"] != str(summary_json):
    raise SystemExit(f"unexpected raw bundle path: {summary['bundle_path']!r}")
if summary["bundle_resolution"].get("bundle_reference_mode") != "summary-relative":
    raise SystemExit(f"unexpected summary bundle reference mode: {summary['bundle_resolution']!r}")

if summary_md_report["bundle_resolution"]["selection_reason"] != "validation-summary-single-step":
    raise SystemExit(f"unexpected markdown summary selection: {summary_md_report['bundle_resolution']!r}")
if summary_md_report["bundle_path"] != str(summary_md):
    raise SystemExit(f"unexpected markdown raw bundle path: {summary_md_report['bundle_path']!r}")
if summary_md_report["bundle_resolution"].get("bundle_reference_mode") != "summary-relative":
    raise SystemExit(f"unexpected markdown summary bundle reference mode: {summary_md_report['bundle_resolution']!r}")

if summary_cwd["bundle_resolution"]["selection_reason"] != "validation-summary-single-step":
    raise SystemExit(f"unexpected cwd summary selection: {summary_cwd['bundle_resolution']!r}")
if summary_cwd["bundle_path"] != str(summary_cwd_json):
    raise SystemExit(f"unexpected cwd raw bundle path: {summary_cwd['bundle_path']!r}")
if summary_cwd["bundle_resolution"].get("bundle_reference_mode") != "cwd-relative":
    raise SystemExit(f"unexpected cwd summary bundle reference mode: {summary_cwd['bundle_resolution']!r}")

if summary_cwd_md_report["bundle_resolution"]["selection_reason"] != "validation-summary-single-step":
    raise SystemExit(f"unexpected cwd markdown selection: {summary_cwd_md_report['bundle_resolution']!r}")
if summary_cwd_md_report["bundle_path"] != str(summary_cwd_md):
    raise SystemExit(f"unexpected cwd markdown raw bundle path: {summary_cwd_md_report['bundle_path']!r}")
if summary_cwd_md_report["bundle_resolution"].get("bundle_reference_mode") != "cwd-relative":
    raise SystemExit(f"unexpected cwd markdown bundle reference mode: {summary_cwd_md_report['bundle_resolution']!r}")
PY

echo "emu_hts2phrb_bundle_input_resolution: PASS"
