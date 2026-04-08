#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-auto-overlay-no-runtime-ready-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"
BUNDLE_DIR="$TMP_DIR/bundle"
TRACE_DIR="$BUNDLE_DIR/traces"
OUTPUT_DIR="$TMP_DIR/out"

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
                "low32": "deadbeef",
                "fs": str(formatsize),
                "mode": "loadtile",
                "wh": "2x2",
                "pcrc": "12345678",
                "active_pool": "compatibility",
            }
        ],
        "usages": [],
        "emulated_tmem": [],
    },
    "sampled_object_probe": {
        "top_groups": []
    },
}
evidence_path.write_text(json.dumps(evidence, indent=2) + "\n")
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$BUNDLE_DIR" \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR" >/dev/null

python3 - "$OUTPUT_DIR" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
report = json.loads((out_dir / "hts2phrb-report.json").read_text())
loader_manifest = json.loads((out_dir / "loader-manifest.json").read_text())
package_manifest = json.loads((out_dir / "package" / "package-manifest.json").read_text())

if report["runtime_overlay_mode"] != "auto":
    raise SystemExit(f"unexpected runtime overlay mode: {report['runtime_overlay_mode']!r}")
if report["runtime_overlay_built"]:
    raise SystemExit(f"expected auto overlay to skip when no runtime-ready records exist, got {report!r}")
if report["runtime_overlay_reason"] != "no-runtime-ready-records":
    raise SystemExit(f"unexpected runtime overlay reason: {report['runtime_overlay_reason']!r}")
if report.get("runtime_overlay_artifacts_emitted"):
    raise SystemExit(f"did not expect overlay artifacts when no runtime-ready records exist, got {report!r}")
if report.get("bindings_path") is not None or report.get("runtime_loader_manifest_path") is not None:
    raise SystemExit(f"did not expect overlay artifact paths, got {report!r}")
if (out_dir / "bindings.json").exists() or (out_dir / "runtime-loader-manifest.json").exists():
    raise SystemExit("runtime overlay artifacts should not be emitted when no runtime-ready records exist")
if report["package_manifest_record_count"] != 1:
    raise SystemExit(f"expected one canonical package record, got {report['package_manifest_record_count']!r}")
if report["package_manifest_runtime_ready_record_count"] != 0 or report["package_manifest_runtime_deferred_record_count"] != 1:
    raise SystemExit(f"unexpected runtime-ready/deferred counts: {report!r}")
if loader_manifest["runtime_ready_record_count"] != 0 or loader_manifest["runtime_deferred_record_count"] != 1:
    raise SystemExit(f"unexpected canonical loader runtime counts: {loader_manifest!r}")
if loader_manifest["runtime_deferred_record_class"] != "compat-only":
    raise SystemExit(f"unexpected canonical loader deferred class: {loader_manifest['runtime_deferred_record_class']!r}")
if package_manifest["runtime_ready_record_count"] != 0 or package_manifest["runtime_deferred_record_count"] != 1:
    raise SystemExit(f"unexpected package-manifest runtime counts: {package_manifest!r}")
if package_manifest["runtime_deferred_record_class"] != "compat-only":
    raise SystemExit(f"unexpected package-manifest deferred class: {package_manifest['runtime_deferred_record_class']!r}")
if report["conversion_outcome"] != "canonical-package-only":
    raise SystemExit(f"unexpected conversion outcome: {report['conversion_outcome']!r}")
warnings = report.get("warnings") or []
if len(warnings) != 1 or "no runtime-ready records" not in warnings[0]:
    raise SystemExit(f"unexpected warnings: {warnings!r}")
family_states = report.get("requested_family_states") or {}
if family_states.get("runtime_state_counts") != {"canonical-only": 1}:
    raise SystemExit(f"unexpected runtime state counts: {family_states!r}")
families = family_states.get("families") or []
if len(families) != 1 or families[0].get("family_key") != "deadbeef:fs258":
    raise SystemExit(f"unexpected family states: {families!r}")
if not report.get("gate_success", False) or report.get("gate_failures"):
    raise SystemExit(f"expected successful ungated conversion, got {report!r}")
PY

echo "emu_hts2phrb_auto_overlay_without_runtime_ready: PASS"
