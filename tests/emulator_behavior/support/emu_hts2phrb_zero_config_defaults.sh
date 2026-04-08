#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-zero-config-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"

python3 - "$CACHE_PATH" <<'PY'
import gzip
import struct
import sys
from pathlib import Path

cache_path = Path(sys.argv[1])

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
PY

pushd "$TMP_DIR" >/dev/null
python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  > "$TMP_DIR/stdout.json"
popd >/dev/null

python3 - "$TMP_DIR" "$CACHE_PATH" <<'PY'
import json
import hashlib
import sys
from pathlib import Path

tmp_dir = Path(sys.argv[1])
cache_path = Path(sys.argv[2])
path_tag = hashlib.sha1(str(cache_path.resolve()).encode("utf-8")).hexdigest()[:8]
expected_output_dir = tmp_dir / "artifacts" / "hts2phrb" / f"sample-{path_tag}-all-families"
report = json.loads((expected_output_dir / "hts2phrb-report.json").read_text())
progress = json.loads((expected_output_dir / "hts2phrb-progress.json").read_text())
summary_text = (expected_output_dir / "hts2phrb-summary.md").read_text()
stdout_text = (tmp_dir / "stdout.json").read_text()

if report["output_dir"] != str(expected_output_dir):
    raise SystemExit(f"unexpected default output dir: {report['output_dir']!r}")
if not report["output_dir_was_default"]:
    raise SystemExit(f"expected default output dir flag, got {report!r}")
if report["request_mode"] != "implicit-all-families":
    raise SystemExit(f"unexpected request mode: {report['request_mode']!r}")
if report["runtime_overlay_mode"] != "auto" or report["runtime_overlay_built"]:
    raise SystemExit(f"unexpected runtime overlay state: mode={report['runtime_overlay_mode']!r} built={report['runtime_overlay_built']!r}")
if report["runtime_overlay_reason"] != "no-runtime-context":
    raise SystemExit(f"unexpected runtime overlay reason: {report['runtime_overlay_reason']!r}")
if report.get("runtime_overlay_artifacts_emitted"):
    raise SystemExit(f"did not expect runtime overlay artifacts when overlay is skipped, got {report!r}")
if report.get("bindings_path") is not None or report.get("runtime_loader_manifest_path") is not None:
    raise SystemExit(f"did not expect runtime overlay artifact paths when overlay is skipped, got {report!r}")
if (expected_output_dir / "bindings.json").exists() or (expected_output_dir / "runtime-loader-manifest.json").exists():
    raise SystemExit("runtime overlay artifacts should not be emitted when runtime overlay is skipped")
if report["requested_family_count"] != 2:
    raise SystemExit(f"unexpected requested family count: {report['requested_family_count']}")
if not report.get("gate_success", False) or report.get("gate_failures"):
    raise SystemExit(f"expected no gate failures without explicit gates, got {report!r}")
if report["cache_path"] != str(cache_path):
    raise SystemExit(f"unexpected resolved cache path: {report['cache_path']!r}")
if report["package_asset_storage"] != "legacy-blobs":
    raise SystemExit(f"unexpected package asset storage: {report['package_asset_storage']!r}")
warnings = report.get("warnings") or []
if len(warnings) != 2:
    raise SystemExit(f"unexpected warnings: {warnings!r}")
if "still contains runtime-ready canonical records" not in warnings[0]:
    raise SystemExit(f"expected diagnostic warning first, got {warnings!r}")
if "defaulted to all-families inventory mode" not in warnings[1]:
    raise SystemExit(f"expected defaulted-request warning, got {warnings!r}")
if report.get("promotion_blockers"):
    raise SystemExit(f"expected no promotion blockers, got {report.get('promotion_blockers')!r}")
if report.get("summary_path") != str(expected_output_dir / "hts2phrb-summary.md"):
    raise SystemExit(f"unexpected summary path: {report.get('summary_path')!r}")
if report.get("progress_path") != str(expected_output_dir / "hts2phrb-progress.json"):
    raise SystemExit(f"unexpected progress path: {report.get('progress_path')!r}")
if report.get("family_inventory_json_path") != str(expected_output_dir / "hts2phrb-family-inventory.json"):
    raise SystemExit(f"unexpected family inventory json path: {report.get('family_inventory_json_path')!r}")
if report.get("family_inventory_markdown_path") != str(expected_output_dir / "hts2phrb-family-inventory.md"):
    raise SystemExit(f"unexpected family inventory markdown path: {report.get('family_inventory_markdown_path')!r}")
if report.get("runtime_state_counts") != {"runtime-ready-package": 2}:
    raise SystemExit(f"unexpected top-level runtime state counts: {report.get('runtime_state_counts')!r}")
if report.get("import_state_counts") != {"exact-authority": 2}:
    raise SystemExit(f"unexpected top-level import state counts: {report.get('import_state_counts')!r}")
if float(report.get("total_runtime_ms") or 0.0) <= 0.0:
    raise SystemExit(f"expected positive total_runtime_ms, got {report.get('total_runtime_ms')!r}")
if progress.get("status") != "complete":
    raise SystemExit(f"expected complete progress report, got {progress!r}")
if "Request mode: `implicit-all-families`" not in summary_text:
    raise SystemExit(f"missing request-mode summary: {summary_text!r}")
if "- Runtime overlay: `skipped` (`no-runtime-context`)" not in summary_text:
    raise SystemExit(f"missing runtime-overlay summary: {summary_text!r}")
if "- Runtime overlay artifacts emitted: `no`" not in summary_text:
    raise SystemExit(f"missing runtime-overlay artifact summary: {summary_text!r}")
if "- None" not in summary_text:
    raise SystemExit(f"expected no blocker summary: {summary_text!r}")
if "Family inventory:" not in summary_text:
    raise SystemExit(f"missing family inventory link: {summary_text!r}")
if f"hts2phrb: {report['conversion_outcome']}" not in stdout_text:
    raise SystemExit(f"missing stdout outcome summary: {stdout_text!r}")
if "runtime_overlay: skipped (no-runtime-context)" not in stdout_text:
    raise SystemExit(f"missing stdout runtime-overlay summary: {stdout_text!r}")
if "runtime_overlay_artifacts_emitted: no" not in stdout_text:
    raise SystemExit(f"missing stdout runtime-overlay artifact summary: {stdout_text!r}")
if f"report: {report['report_path']}" not in stdout_text or f"summary: {report['summary_path']}" not in stdout_text:
    raise SystemExit(f"missing stdout path summary: {stdout_text!r}")
if f"family_inventory: {report['family_inventory_markdown_path']}" not in stdout_text:
    raise SystemExit(f"missing stdout family inventory summary: {stdout_text!r}")
PY

echo "emu_hts2phrb_zero_config_defaults: PASS"
