#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-context-dir-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"
CONTEXT_TREE="$TMP_DIR/validation-tree"
OUT_DIR_SCAN="$TMP_DIR/out-dir-scan"
OUT_BUNDLE_EXPLICIT="$TMP_DIR/out-bundle-explicit"

mkdir -p \
  "$CONTEXT_TREE/run-a/bundle-a/traces" \
  "$CONTEXT_TREE/run-b/bundle-b/traces" \
  "$CONTEXT_TREE/run-c"

python3 - "$CACHE_PATH" \
  "$CONTEXT_TREE/run-a/bundle-a/traces/hires-evidence.json" \
  "$CONTEXT_TREE/run-b/bundle-b/traces/hires-evidence.json" \
  "$CONTEXT_TREE/run-a/validation-summary.json" \
  "$CONTEXT_TREE/run-b/validation-summary.json" \
  "$CONTEXT_TREE/run-c/validation-summary.json" \
  <<'PY'
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
summary_c_bad = Path(sys.argv[6])

TXCACHE_FORMAT_VERSION = 0x08000000
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401
GL_RGBA8 = 0x8058

records = [
    (0x11111111, 0xAAAABBBB, 258),
    (0x22222222, 0xCCCCDDDD, 514),
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


def write_evidence(path, texture_crc, palette_crc, formatsize):
    path.write_text(json.dumps({
        "ci_palette_probe": {"families": [], "usages": [], "emulated_tmem": []},
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
                    "upload_low32s": [{"value": f"{texture_crc:08x}"}],
                    "upload_pcrcs": [{"value": f"{palette_crc:08x}"}]
                }
            ]
        }
    }, indent=2) + "\n")


write_evidence(evidence_a, 0x11111111, 0xAAAABBBB, 258)
write_evidence(evidence_b, 0x22222222, 0xCCCCDDDD, 514)

# Summary A: points to bundle-a (sibling-relative)
summary_a.write_text(json.dumps({
    "summary_title": "run-a",
    "all_passed": True,
    "fixtures": [{
        "label": "fixture-a",
        "fixture_id": "fixture-a",
        "bundle_dir": "bundle-a",
        "passed": True,
    }]
}, indent=2) + "\n")

# Summary B: points to bundle-b (sibling-relative)
summary_b.write_text(json.dumps({
    "summary_title": "run-b",
    "all_passed": True,
    "fixtures": [{
        "label": "fixture-b",
        "fixture_id": "fixture-b",
        "bundle_dir": "bundle-b",
        "passed": True,
    }]
}, indent=2) + "\n")

# Summary C: intentionally broken (no bundle_dir) — should be skipped
summary_c_bad.write_text(json.dumps({
    "summary_title": "run-c-broken",
    "all_passed": True,
    "fixtures": [{
        "label": "fixture-c",
        "fixture_id": "fixture-c",
        "passed": True,
    }]
}, indent=2) + "\n")
PY

# Run with --context-dir (should discover A and B, skip C)
python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --context-dir "$CONTEXT_TREE" \
  --stdout-format json \
  --output-dir "$OUT_DIR_SCAN" \
  > "$TMP_DIR/report-dir-scan.json" \
  2> "$TMP_DIR/stderr-dir-scan.txt"

# Run with explicit --context-bundle for each good summary (baseline)
python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --context-bundle "$CONTEXT_TREE/run-a/validation-summary.json" \
  --context-bundle "$CONTEXT_TREE/run-b/validation-summary.json" \
  --stdout-format json \
  --output-dir "$OUT_BUNDLE_EXPLICIT" \
  > "$TMP_DIR/report-bundle-explicit.json"

python3 - \
  "$TMP_DIR/report-dir-scan.json" \
  "$TMP_DIR/report-bundle-explicit.json" \
  "$TMP_DIR/stderr-dir-scan.txt" \
  <<'PY'
import json
import sys
from pathlib import Path

dir_scan = json.loads(Path(sys.argv[1]).read_text())
explicit = json.loads(Path(sys.argv[2]).read_text())
stderr = Path(sys.argv[3]).read_text()

# Both should produce the same conversion outcome
if dir_scan["conversion_outcome"] != explicit["conversion_outcome"]:
    raise SystemExit(
        f"outcome mismatch: dir_scan={dir_scan['conversion_outcome']!r}, "
        f"explicit={explicit['conversion_outcome']!r}"
    )

# Both should have 2 context bundle resolutions (one per good summary)
for label, report in [("dir-scan", dir_scan), ("explicit", explicit)]:
    count = report.get("context_bundle_resolution_count")
    if count != 2:
        raise SystemExit(f"{label}: expected 2 context resolutions, got {count}")

# dir-scan should report context_bundle_input_count=1 (one --context-dir)
if dir_scan.get("context_bundle_input_count") != 1:
    raise SystemExit(
        f"dir-scan: expected input_count=1, got {dir_scan.get('context_bundle_input_count')}"
    )

# explicit should report context_bundle_input_count=2 (two --context-bundle)
if explicit.get("context_bundle_input_count") != 2:
    raise SystemExit(
        f"explicit: expected input_count=2, got {explicit.get('context_bundle_input_count')}"
    )

# dir-scan should have context_dir_paths in report
if not dir_scan.get("context_dir_paths"):
    raise SystemExit("dir-scan: missing context_dir_paths in report")

# Both should have the same native sampled record count
dir_sampled = dir_scan.get("package_manifest_runtime_ready_native_sampled_record_count")
exp_sampled = explicit.get("package_manifest_runtime_ready_native_sampled_record_count")
if dir_sampled != exp_sampled:
    raise SystemExit(
        f"native sampled mismatch: dir_scan={dir_sampled}, explicit={exp_sampled}"
    )

# Stderr should mention the skipped summary
if "context-dir: skipping" not in stderr:
    raise SystemExit(f"expected skip warning in stderr, got: {stderr!r}")
if "context-dir: discovered 2, skipped 1" not in stderr:
    raise SystemExit(f"expected discovery stats in stderr, got: {stderr!r}")

# Runtime overlay should be built for both
for label, report in [("dir-scan", dir_scan), ("explicit", explicit)]:
    if not report.get("runtime_overlay_built"):
        raise SystemExit(f"{label}: expected runtime overlay to be built")
PY

echo "emu_hts2phrb_context_dir_discovery: PASS"
