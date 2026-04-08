#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-reuse-XXXXXX)"
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
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$BUNDLE_DIR" \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR" >/dev/null

python3 - "$OUTPUT_DIR/hts2phrb-report.json" <<'PY'
import json
import sys
from pathlib import Path

report_path = Path(sys.argv[1])
report = json.loads(report_path.read_text())
report.pop("request_signature", None)
report_path.write_text(json.dumps(report, indent=2) + "\n")
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$BUNDLE_DIR" \
  --reuse-existing \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR" >/dev/null

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$BUNDLE_DIR" \
  --reuse-existing \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR" >/dev/null

python3 - "$OUTPUT_DIR" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
report = json.loads((out_dir / "hts2phrb-report.json").read_text())
(out_dir / "reused-report.json").write_text(json.dumps(report, indent=2) + "\n")
PY

python3 - "$TRACE_DIR/hires-evidence.json" <<'PY'
import json
import sys
from pathlib import Path

evidence_path = Path(sys.argv[1])
evidence = json.loads(evidence_path.read_text())
families = (((evidence.get("ci_palette_probe") or {}).get("families")) or [])
families.append(
    {
        "low32": "22222222",
        "fs": "258",
        "mode": "loadtile",
        "wh": "2x2",
        "pcrc": "ccccdddd",
        "active_pool": "compatibility",
    }
)
evidence["debug_mutation_marker"] = "bundle-edited-" + ("x" * 4096)
evidence_path.write_text(json.dumps(evidence, indent=2) + "\n")
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$BUNDLE_DIR" \
  --reuse-existing \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR" >/dev/null

python3 - "$OUTPUT_DIR" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
report = json.loads((out_dir / "hts2phrb-report.json").read_text())
(out_dir / "bundle-mutated-report.json").write_text(json.dumps(report, indent=2) + "\n")
Path(report["report_path"]).unlink()
Path(report["summary_path"]).unlink()
Path(report["binary_package"]["output_path"]).unlink()
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$BUNDLE_DIR" \
  --reuse-existing \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR" >/dev/null

python3 - "$OUTPUT_DIR" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
reused_report = json.loads((out_dir / "reused-report.json").read_text())
report = json.loads((out_dir / "hts2phrb-report.json").read_text())
progress = json.loads((out_dir / "hts2phrb-progress.json").read_text())
summary_text = (out_dir / "hts2phrb-summary.md").read_text()
bundle_mutated_report = json.loads((out_dir / "bundle-mutated-report.json").read_text())

if reused_report["conversion_outcome"] != "promotable-runtime-package":
    raise SystemExit(f"unexpected outcome after complete reuse: {reused_report['conversion_outcome']!r}")
if not reused_report.get("reused_existing", False):
    raise SystemExit(f"expected reused_existing=true for complete reuse, got {reused_report!r}")
if not reused_report.get("pre_request_signature"):
    raise SystemExit(f"expected pre_request_signature on reused report, got {reused_report!r}")

if bundle_mutated_report["requested_family_count"] != 2:
    raise SystemExit(f"expected bundle mutation to invalidate reuse and rebuild with 2 families, got {bundle_mutated_report!r}")
if bundle_mutated_report.get("reused_existing", False):
    raise SystemExit(f"expected bundle mutation to force rebuild, got {bundle_mutated_report!r}")
if (
    (bundle_mutated_report.get("pre_request_signature") or {}).get("bundle_fingerprint")
    == (reused_report.get("pre_request_signature") or {}).get("bundle_fingerprint")
):
    raise SystemExit("expected bundle fingerprint to change after mutating hires-evidence.json")

if report["conversion_outcome"] != bundle_mutated_report["conversion_outcome"]:
    raise SystemExit(
        "unexpected outcome after partial-stage reuse: "
        f"{report['conversion_outcome']!r} vs mutated {bundle_mutated_report['conversion_outcome']!r}"
    )
if report.get("reused_existing", False):
    raise SystemExit(f"expected rebuilt report after partial-stage reuse, got {report!r}")
if report.get("runtime_overlay_mode") != "auto" or not report.get("runtime_overlay_built"):
    raise SystemExit(f"unexpected runtime overlay state after partial-stage reuse: {report!r}")
if not report.get("request_signature") or not report.get("pre_request_signature"):
    raise SystemExit(f"expected request signatures in rebuilt report, got {report!r}")
if report.get("gate_failures"):
    raise SystemExit(f"expected no gate failures after partial-stage reuse, got {report['gate_failures']!r}")
expected_reused_stages = [
    "build_migration_plan",
    "build_canonical_loader_manifest",
    "build_bindings",
    "build_runtime_loader_manifest",
]
if report.get("reused_stage_names") != expected_reused_stages:
    raise SystemExit(f"unexpected reused stages: {report.get('reused_stage_names')!r}")
for stage_name in expected_reused_stages:
    if float((report.get("stage_timings_ms") or {}).get(stage_name, -1.0)) != 0.0:
        raise SystemExit(f"expected reused stage timing of 0.0 for {stage_name}, got {report.get('stage_timings_ms')!r}")
if progress.get("status") != "complete":
    raise SystemExit(f"expected complete progress state after rebuild, got {progress!r}")
if progress.get("reused_existing", False):
    raise SystemExit(f"did not expect reused_existing in rebuilt progress, got {progress!r}")
if progress.get("reused_stage_names") != expected_reused_stages:
    raise SystemExit(f"unexpected progress reused stages: {progress!r}")
if "Reused existing artifacts: `no`" not in summary_text:
    raise SystemExit(f"expected rebuilt summary to record non-report reuse, got {summary_text!r}")
PY

echo "emu_hts2phrb_reuse_existing: PASS"
