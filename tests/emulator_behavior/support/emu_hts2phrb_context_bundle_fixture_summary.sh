#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-context-fixtures-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"
BUNDLE_A_DIR="$TMP_DIR/bundle-a"
BUNDLE_B_DIR="$TMP_DIR/bundle-b"
SUMMARY_DIR="$TMP_DIR/summary"
SUMMARY_REPO_DIR="$TMP_DIR/summary-repo"
SUMMARY_JSON="$SUMMARY_DIR/validation-summary.json"
SUMMARY_MD="$SUMMARY_DIR/validation-summary.md"
SUMMARY_REPO_JSON="$SUMMARY_REPO_DIR/validation-summary.json"
SUMMARY_REPO_MD="$SUMMARY_REPO_DIR/validation-summary.md"
OUT_JSON="$TMP_DIR/out-json"
OUT_MD="$TMP_DIR/out-md"
OUT_DIR="$TMP_DIR/out-dir"
OUT_REPO_JSON="$TMP_DIR/out-repo-json"
OUT_REPO_MD="$TMP_DIR/out-repo-md"

mkdir -p "$BUNDLE_A_DIR/traces" "$BUNDLE_B_DIR/traces" "$SUMMARY_DIR" "$SUMMARY_REPO_DIR"

python3 - "$ROOT_DIR" "$CACHE_PATH" "$BUNDLE_A_DIR/traces/hires-evidence.json" "$BUNDLE_B_DIR/traces/hires-evidence.json" "$SUMMARY_JSON" "$SUMMARY_MD" "$SUMMARY_REPO_JSON" "$SUMMARY_REPO_MD" <<'PY'
import gzip
import json
import os
import struct
import sys
from pathlib import Path

root_dir = Path(sys.argv[1])
cache_path = Path(sys.argv[2])
bundle_a = Path(sys.argv[3])
bundle_b = Path(sys.argv[4])
summary_json = Path(sys.argv[5])
summary_md = Path(sys.argv[6])
summary_repo_json = Path(sys.argv[7])
summary_repo_md = Path(sys.argv[8])

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


def write_bundle(path, texture_crc, palette_crc, formatsize):
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


write_bundle(bundle_a, 0x11111111, 0xAAAABBBB, 258)
write_bundle(bundle_b, 0x22222222, 0xCCCCDDDD, 514)

summary = {
    "summary_title": "fixture summary",
    "all_passed": True,
    "fixtures": [
        {
            "label": "title-screen",
            "fixture_id": "paper-mario-title-screen",
            "bundle_dir": "../bundle-a",
            "passed": True,
        },
        {
            "label": "file-select",
            "fixture_id": "paper-mario-file-select",
            "bundle_dir": "../bundle-b",
            "passed": True,
        }
    ]
}
summary_json.write_text(json.dumps(summary, indent=2) + "\n")
summary_md.write_text("# validation summary\n")

summary_repo = {
    "summary_title": "fixture summary repo-root",
    "all_passed": True,
    "fixtures": [
        {
            "label": "title-screen",
            "fixture_id": "paper-mario-title-screen",
            "bundle_dir": os.path.relpath(bundle_a.parent.parent, root_dir),
            "passed": True,
        },
        {
            "label": "file-select",
            "fixture_id": "paper-mario-file-select",
            "bundle_dir": os.path.relpath(bundle_b.parent.parent, root_dir),
            "passed": True,
        }
    ]
}
summary_repo_json.write_text(json.dumps(summary_repo, indent=2) + "\n")
summary_repo_md.write_text("# validation summary repo-root\n")
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --context-bundle "$SUMMARY_JSON" \
  --stdout-format json \
  --output-dir "$OUT_JSON" \
  > "$TMP_DIR/report-json.json"

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --context-bundle "$SUMMARY_MD" \
  --stdout-format json \
  --output-dir "$OUT_MD" \
  > "$TMP_DIR/report-md.json"

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --context-bundle "$SUMMARY_DIR" \
  --stdout-format json \
  --output-dir "$OUT_DIR" \
  > "$TMP_DIR/report-dir.json"

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --context-bundle "$SUMMARY_REPO_JSON" \
  --stdout-format json \
  --output-dir "$OUT_REPO_JSON" \
  > "$TMP_DIR/report-repo-json.json"

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --context-bundle "$SUMMARY_REPO_MD" \
  --stdout-format json \
  --output-dir "$OUT_REPO_MD" \
  > "$TMP_DIR/report-repo-md.json"

python3 - "$TMP_DIR/report-json.json" "$TMP_DIR/report-md.json" "$TMP_DIR/report-dir.json" "$TMP_DIR/report-repo-json.json" "$TMP_DIR/report-repo-md.json" <<'PY'
import json
import sys
from pathlib import Path

reports = [json.loads(Path(path).read_text()) for path in sys.argv[1:]]

for report in reports:
    if report["conversion_outcome"] != "promotable-runtime-package":
        raise SystemExit(f"unexpected conversion outcome: {report['conversion_outcome']!r}")
    if report["requested_family_count"] != 2:
        raise SystemExit(f"unexpected requested family count: {report['requested_family_count']!r}")
    if report["runtime_overlay_built"]:
        raise SystemExit(f"did not expect runtime overlay build: {report!r}")
    if report["runtime_overlay_reason"] != "no-runtime-context":
        raise SystemExit(f"unexpected runtime overlay reason: {report['runtime_overlay_reason']!r}")
    if len(report.get("context_bundle_resolutions") or []) != 2:
        raise SystemExit(f"unexpected context bundle resolutions: {report.get('context_bundle_resolutions')!r}")
    if report.get("context_bundle_input_count") != 1:
        raise SystemExit(f"unexpected context bundle input count: {report.get('context_bundle_input_count')!r}")
    if report.get("context_bundle_resolution_count") != 2:
        raise SystemExit(f"unexpected expanded context bundle count: {report.get('context_bundle_resolution_count')!r}")
    if report.get("runtime_state_counts") != {"runtime-ready-package": 2}:
        raise SystemExit(f"unexpected runtime state counts: {report.get('runtime_state_counts')!r}")
    imported = report.get("imported_index_summary") or {}
    if imported.get("canonical_sampled_record_count") != 2:
        raise SystemExit(f"unexpected canonical sampled count: {imported!r}")
    if sorted(item.get("selection_reason") for item in report["context_bundle_resolutions"]) != [
        "validation-summary-fixtures",
        "validation-summary-fixtures",
    ]:
        raise SystemExit(f"unexpected context bundle resolution reasons: {report['context_bundle_resolutions']!r}")
    if sorted(item.get("input_kind") for item in report["context_bundle_resolutions"]) != [
        "fixture-validation-summary",
        "fixture-validation-summary",
    ]:
        raise SystemExit(f"unexpected context bundle input kinds: {report['context_bundle_resolutions']!r}")

repo_reports = reports[3:]
for report in repo_reports:
    modes = sorted(item.get("bundle_reference_mode") for item in report["context_bundle_resolutions"])
    if modes not in (
        ["repo-root-relative", "repo-root-relative"],
        ["summary-relative", "summary-relative"],
    ):
        raise SystemExit(f"unexpected repo-root bundle reference modes: {report['context_bundle_resolutions']!r}")
PY

echo "emu_hts2phrb_context_bundle_fixture_summary: PASS"
