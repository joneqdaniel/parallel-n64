#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-reuse-manifest-backfill-XXXXXX)"
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
                "active_pool": "compatibility",
            }
        ],
        "usages": [],
        "emulated_tmem": [],
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
                    "sampled_used_count": "1",
                },
                "upload_low32s": [{"value": f"{texture_crc:08x}"}],
                "upload_pcrcs": [{"value": f"{palette_crc:08x}"}],
            }
        ]
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
manifest_paths = [
    out_dir / "loader-manifest.json",
    out_dir / "package" / "package-manifest.json",
]
for manifest_path in manifest_paths:
    manifest = json.loads(manifest_path.read_text())
    for key in [
        "runtime_ready_record_kind_counts",
        "runtime_deferred_record_kind_counts",
        "runtime_ready_native_sampled_record_count",
        "runtime_ready_compat_record_count",
        "runtime_deferred_native_sampled_record_count",
        "runtime_deferred_compat_record_count",
        "runtime_ready_record_class",
        "runtime_deferred_record_class",
    ]:
        manifest[key] = None
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

report_path = out_dir / "hts2phrb-report.json"
report = json.loads(report_path.read_text())
report["artifact_contract_version"] = 4
report["package_manifest_runtime_ready_record_class"] = None
report["package_manifest_runtime_deferred_record_class"] = None
report["package_manifest_runtime_ready_native_sampled_record_count"] = None
report["package_manifest_runtime_ready_compat_record_count"] = None
report["package_manifest_runtime_deferred_native_sampled_record_count"] = None
report["package_manifest_runtime_deferred_compat_record_count"] = None
report["total_ms"] = None
report_path.write_text(json.dumps(report, indent=2) + "\n")
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
loader_manifest = json.loads((out_dir / "loader-manifest.json").read_text())
package_manifest = json.loads((out_dir / "package" / "package-manifest.json").read_text())
summary_text = (out_dir / "hts2phrb-summary.md").read_text()

if not report.get("reused_existing", False):
    raise SystemExit(f"expected reuse after manifest backfill, got {report!r}")
if report.get("artifact_contract_version") != 5:
    raise SystemExit(f"expected report artifact version upgrade to 5, got {report.get('artifact_contract_version')!r}")
if report.get("package_manifest_runtime_ready_record_class") != "native-sampled-only":
    raise SystemExit(
        "expected backfilled report runtime-ready class of native-sampled-only, got "
        f"{report.get('package_manifest_runtime_ready_record_class')!r}"
    )
if int(report.get("package_manifest_runtime_ready_native_sampled_record_count", 0)) != 1:
    raise SystemExit(
        "expected backfilled report runtime-ready native count of 1, got "
        f"{report.get('package_manifest_runtime_ready_native_sampled_record_count')!r}"
    )
if int(report.get("package_manifest_runtime_ready_compat_record_count", -1)) != 0:
    raise SystemExit(
        "expected backfilled report runtime-ready compat count of 0, got "
        f"{report.get('package_manifest_runtime_ready_compat_record_count')!r}"
    )
if float(report.get("total_ms", -1.0)) < 0.0:
    raise SystemExit(f"expected total_ms to be backfilled to a numeric value, got {report.get('total_ms')!r}")

for manifest_name, manifest in (("loader", loader_manifest), ("package", package_manifest)):
    if manifest.get("runtime_ready_record_class") != "native-sampled-only":
        raise SystemExit(
            f"expected {manifest_name} manifest runtime-ready class of native-sampled-only, got "
            f"{manifest.get('runtime_ready_record_class')!r}"
        )
    if int(manifest.get("runtime_ready_native_sampled_record_count", 0)) != 1:
        raise SystemExit(
            f"expected {manifest_name} manifest runtime-ready native count of 1, got "
            f"{manifest.get('runtime_ready_native_sampled_record_count')!r}"
        )
    if int(manifest.get("runtime_ready_compat_record_count", -1)) != 0:
        raise SystemExit(
            f"expected {manifest_name} manifest runtime-ready compat count of 0, got "
            f"{manifest.get('runtime_ready_compat_record_count')!r}"
        )

if "Runtime-ready record class: `native-sampled-only`" not in summary_text:
    raise SystemExit(f"expected backfilled summary text, got {summary_text!r}")
if "Reused existing artifacts: `yes`" not in summary_text:
    raise SystemExit(f"expected summary reuse marker, got {summary_text!r}")
PY

echo "emu_hts2phrb_reuse_existing_manifest_summary_backfill: PASS"
