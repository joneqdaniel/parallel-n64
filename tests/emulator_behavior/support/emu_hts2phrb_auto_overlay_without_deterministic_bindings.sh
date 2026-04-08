#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-auto-overlay-no-bindings-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_DIR="$TMP_DIR/cache"
BUNDLE_DIR="$TMP_DIR/bundle"
TRACE_DIR="$BUNDLE_DIR/traces"
OUTPUT_DIR="$TMP_DIR/out"

mkdir -p "$CACHE_DIR" "$TRACE_DIR"

python3 - "$CACHE_DIR" "$TRACE_DIR/hires-evidence.json" <<'PY'
import gzip
import json
import struct
import sys
from pathlib import Path

cache_dir = Path(sys.argv[1])
evidence_path = Path(sys.argv[2])

TXCACHE_FORMAT_VERSION = 0x08000000
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401
GL_RGBA8 = 0x8058

texture_crc = 0x11111111
palette_crc = 0xAAAABBBB
checksum64 = (palette_crc << 32) | texture_crc
formatsize = 258
payloads = [
    bytes([0x10, 0x20, 0x30, 0xFF, 0x40, 0x50, 0x60, 0xFF, 0x70, 0x80, 0x90, 0xFF, 0xA0, 0xB0, 0xC0, 0xFF]),
    bytes([0x01, 0x02, 0x03, 0xFF, 0x04, 0x05, 0x06, 0xFF, 0x07, 0x08, 0x09, 0xFF, 0x0A, 0x0B, 0x0C, 0xFF]),
]

for index, payload in enumerate(payloads, start=1):
    path = cache_dir / f"sample{index}.htc"
    with gzip.open(path, "wb") as fp:
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
    },
    "sampled_object_probe": {
        "top_groups": []
    },
}
evidence_path.write_text(json.dumps(evidence, indent=2) + "\n")
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_DIR" \
  --bundle "$BUNDLE_DIR" \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR" >/dev/null

python3 - "$OUTPUT_DIR" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
report = json.loads((out_dir / "hts2phrb-report.json").read_text())

if report["runtime_overlay_mode"] != "auto":
    raise SystemExit(f"unexpected runtime overlay mode: {report['runtime_overlay_mode']!r}")
if report["runtime_overlay_built"]:
    raise SystemExit(f"expected auto overlay to skip when no deterministic bindings exist, got {report!r}")
if report["runtime_overlay_reason"] != "no-deterministic-bindings":
    raise SystemExit(f"unexpected runtime overlay reason: {report['runtime_overlay_reason']!r}")
if report.get("runtime_overlay_artifacts_emitted"):
    raise SystemExit(f"did not expect overlay artifacts when no deterministic bindings exist, got {report!r}")
if report.get("bindings_path") is not None or report.get("runtime_loader_manifest_path") is not None:
    raise SystemExit(f"did not expect overlay artifact paths, got {report!r}")
if (out_dir / "bindings.json").exists() or (out_dir / "runtime-loader-manifest.json").exists():
    raise SystemExit("runtime overlay artifacts should not be emitted when no deterministic bindings exist")
if report["package_manifest_record_count"] != 1 or report["package_manifest_runtime_ready_record_count"] != 1:
    raise SystemExit(f"unexpected runtime-ready package summary: {report!r}")
if report["binding_count"] != 0 or report["unresolved_count"] != 0:
    raise SystemExit(f"expected zero bindings and zero unresolved transport cases, got {report!r}")
if report["conversion_outcome"] != "promotable-runtime-package":
    raise SystemExit(f"unexpected conversion outcome: {report['conversion_outcome']!r}")
warnings = report.get("warnings") or []
if len(warnings) != 2:
    raise SystemExit(f"unexpected warnings: {warnings!r}")
if "no deterministic runtime bindings" not in warnings[0]:
    raise SystemExit(f"expected no-deterministic-bindings warning first, got {warnings!r}")
if "directory candidates" not in warnings[1]:
    raise SystemExit(f"expected directory-resolution warning second, got {warnings!r}")
family_states = report.get("requested_family_states") or {}
if family_states.get("runtime_state_counts") != {"runtime-ready-package": 1}:
    raise SystemExit(f"unexpected runtime state counts: {family_states!r}")
families = family_states.get("families") or []
if len(families) != 1 or families[0].get("family_key") != "11111111:fs258":
    raise SystemExit(f"unexpected family states: {families!r}")
if not report.get("gate_success", False) or report.get("gate_failures"):
    raise SystemExit(f"expected successful ungated conversion, got {report!r}")
PY

echo "emu_hts2phrb_auto_overlay_without_deterministic_bindings: PASS"
