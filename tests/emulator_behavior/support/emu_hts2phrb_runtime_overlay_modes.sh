#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-overlay-modes-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"
BUNDLE_DIR="$TMP_DIR/bundle"
TRACE_DIR="$BUNDLE_DIR/traces"
OUT_NEVER="$TMP_DIR/out-never"
OUT_ALWAYS="$TMP_DIR/out-always"
OUT_AUTO_CONTEXT="$TMP_DIR/out-auto-context"

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
    (0x11111111, 0xAAAABBBB, 258, bytes([
        0x10, 0x20, 0x30, 0xFF,
        0x40, 0x50, 0x60, 0xFF,
        0x70, 0x80, 0x90, 0xFF,
        0xA0, 0xB0, 0xC0, 0xFF,
    ])),
    (0x22222222, 0xCCCCDDDD, 514, bytes([
        0x01, 0x02, 0x03, 0xFF,
        0x04, 0x05, 0x06, 0xFF,
        0x07, 0x08, 0x09, 0xFF,
        0x0A, 0x0B, 0x0C, 0xFF,
    ])),
]

with gzip.open(cache_path, "wb") as fp:
    fp.write(struct.pack("<i", TXCACHE_FORMAT_VERSION))
    fp.write(struct.pack("<i", 0))
    for texture_crc, palette_crc, formatsize, payload in records:
        checksum64 = (palette_crc << 32) | texture_crc
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
  --cache "$CACHE_PATH" \
  --bundle "$BUNDLE_DIR" \
  --runtime-overlay-mode never \
  --stdout-format json \
  --output-dir "$OUT_NEVER" >/dev/null

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --all-families \
  --runtime-overlay-mode always \
  --stdout-format json \
  --output-dir "$OUT_ALWAYS" >/dev/null

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --context-bundle "$BUNDLE_DIR" \
  --all-families \
  --stdout-format json \
  --output-dir "$OUT_AUTO_CONTEXT" >/dev/null

python3 - "$OUT_NEVER" "$OUT_ALWAYS" "$OUT_AUTO_CONTEXT" <<'PY'
import json
import sys
from pathlib import Path

out_never = Path(sys.argv[1])
out_always = Path(sys.argv[2])
out_auto_context = Path(sys.argv[3])

report_never = json.loads((out_never / "hts2phrb-report.json").read_text())

if report_never["runtime_overlay_mode"] != "never" or report_never["runtime_overlay_built"]:
    raise SystemExit(f"unexpected never-overlay state: {report_never!r}")
if report_never["runtime_overlay_reason"] != "disabled":
    raise SystemExit(f"unexpected never-overlay reason: {report_never['runtime_overlay_reason']!r}")
if report_never["binding_count"] != 0 or report_never["unresolved_count"] != 0:
    raise SystemExit(f"expected no bindings/unresolved for disabled overlay, got {report_never!r}")
if report_never.get("runtime_overlay_artifacts_emitted") is not False:
    raise SystemExit(f"expected disabled overlay artifacts to be omitted, got {report_never!r}")
if report_never.get("bindings_path") is not None or report_never.get("runtime_loader_manifest_path") is not None:
    raise SystemExit(f"expected no overlay artifact paths for disabled overlay, got {report_never!r}")
if (out_never / "bindings.json").exists() or (out_never / "runtime-loader-manifest.json").exists():
    raise SystemExit("disabled runtime overlay should not emit overlay artifact files")

report_always = json.loads((out_always / "hts2phrb-report.json").read_text())
bindings_always = json.loads((out_always / "bindings.json").read_text())
runtime_loader_always = json.loads((out_always / "runtime-loader-manifest.json").read_text())

if report_always["runtime_overlay_mode"] != "always" or not report_always["runtime_overlay_built"]:
    raise SystemExit(f"unexpected always-overlay state: {report_always!r}")
if report_always["runtime_overlay_reason"] != "forced":
    raise SystemExit(f"unexpected always-overlay reason: {report_always['runtime_overlay_reason']!r}")
if not report_always.get("runtime_overlay_artifacts_emitted"):
    raise SystemExit(f"expected forced overlay artifacts to be emitted, got {report_always!r}")
if report_always["binding_count"] != 0 or report_always["unresolved_count"] != 0:
    raise SystemExit(f"expected zero runtime bindings in forced inventory mode, got {report_always!r}")
warnings = report_always.get("warnings") or []
if len(warnings) != 1:
    raise SystemExit(f"unexpected forced-overlay warnings: {warnings!r}")
if "No deterministic runtime bindings were emitted" not in warnings[0]:
    raise SystemExit(f"expected runtime-overlay warning first, got {warnings!r}")
if bindings_always.get("overlay_status") is not None or runtime_loader_always.get("overlay_status") is not None:
    raise SystemExit(f"forced overlay should build normal overlay artifacts, got bindings={bindings_always!r} runtime_loader={runtime_loader_always!r}")

report_auto_context = json.loads((out_auto_context / "hts2phrb-report.json").read_text())
bindings_auto_context = json.loads((out_auto_context / "bindings.json").read_text())
runtime_loader_auto_context = json.loads((out_auto_context / "runtime-loader-manifest.json").read_text())

if report_auto_context["runtime_overlay_mode"] != "auto" or not report_auto_context["runtime_overlay_built"]:
    raise SystemExit(f"expected auto overlay to build with context bundle, got {report_auto_context!r}")
if report_auto_context["runtime_overlay_reason"] != "runtime-context-available":
    raise SystemExit(f"unexpected auto-overlay reason: {report_auto_context['runtime_overlay_reason']!r}")
if report_auto_context["binding_count"] != 1 or report_auto_context["unresolved_count"] != 0:
    raise SystemExit(f"expected one deterministic binding with no unresolved transport cases, got {report_auto_context!r}")
if not report_auto_context.get("runtime_overlay_artifacts_emitted"):
    raise SystemExit(f"expected auto overlay artifacts to be emitted, got {report_auto_context!r}")
if report_auto_context.get("bindings_path") is None or report_auto_context.get("runtime_loader_manifest_path") is None:
    raise SystemExit(f"expected emitted overlay artifact paths, got {report_auto_context!r}")
if bindings_auto_context.get("binding_count") != 1 or len(bindings_auto_context.get("bindings") or []) != 1:
    raise SystemExit(f"unexpected context-overlay bindings payload: {bindings_auto_context!r}")
if runtime_loader_auto_context.get("record_count") != 1 or runtime_loader_auto_context.get("runtime_ready_record_count") != 1:
    raise SystemExit(f"unexpected context-overlay runtime loader payload: {runtime_loader_auto_context!r}")
PY

echo "emu_hts2phrb_runtime_overlay_modes: PASS"
