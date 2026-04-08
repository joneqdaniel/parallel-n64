#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-roundtrip-XXXXXX)"
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
GL_RGB = 0x1907
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401
GL_UNSIGNED_SHORT_5_6_5 = 0x8363
GL_RGB8 = 0x8051
GL_RGBA8 = 0x8058

texture_crc = 0x11111111
palette_crc = 0xAAAABBBB
checksum64 = (palette_crc << 32) | texture_crc
formatsize = 258
payload = bytes([
    0x00, 0xF8,
    0xE0, 0x07,
    0x1F, 0x00,
    0xFF, 0xFF,
])

with gzip.open(cache_path, "wb") as fp:
    fp.write(struct.pack("<i", TXCACHE_FORMAT_VERSION))
    fp.write(struct.pack("<i", 0))
    fp.write(struct.pack("<Q", checksum64))
    fp.write(struct.pack("<IIIHHB", 2, 2, GL_RGB8, GL_RGB, GL_UNSIGNED_SHORT_5_6_5, 1))
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
  --output-dir "$OUTPUT_DIR"

python3 - "$ROOT_DIR" "$OUTPUT_DIR" "$CACHE_PATH" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
out_dir = Path(sys.argv[2])
cache_path = Path(sys.argv[3])

sys.path.insert(0, str(root / "tools"))
from hires_pack_inspect_binary_package import inspect_binary_package

report = json.loads((out_dir / "hts2phrb-report.json").read_text())
plan = json.loads((out_dir / "migration-plan.json").read_text())
loader_manifest = json.loads((out_dir / "loader-manifest.json").read_text())
runtime_loader_manifest = json.loads((out_dir / "runtime-loader-manifest.json").read_text())
bindings = json.loads((out_dir / "bindings.json").read_text())
package_manifest = json.loads((out_dir / "package" / "package-manifest.json").read_text())
binary = inspect_binary_package(Path(report["binary_package"]["output_path"]))

if binary["record_count"] != 1 or binary["asset_count"] != 1:
    raise SystemExit(f"unexpected binary counts: {binary['record_count']} records, {binary['asset_count']} assets")
if binary["version"] != 7:
    raise SystemExit(f"expected PHRB version 7, got {binary['version']}")

canonical_records = plan["imported_index"]["canonical_records"]
if len(canonical_records) != 1:
    raise SystemExit(f"expected one canonical record, got {len(canonical_records)}")
manifest_records = package_manifest["records"]
if len(manifest_records) != 1:
    raise SystemExit(f"expected one package-manifest record, got {len(manifest_records)}")
binding_records = bindings["bindings"]
if len(binding_records) != 1:
    raise SystemExit(f"expected one binding record, got {len(binding_records)}")

manifest_record = manifest_records[0]
binary_record = binary["records"][0]
binding = binding_records[0]
manifest_asset = manifest_record["asset_candidates"][0]

if binary_record["policy_key"] != manifest_record["policy_key"]:
    raise SystemExit(f"policy key mismatch: {binary_record['policy_key']} != {manifest_record['policy_key']}")
if binary_record["sampled_object_id"] != manifest_record["sampled_object_id"]:
    raise SystemExit(
        f"sampled object mismatch: {binary_record['sampled_object_id']} != {manifest_record['sampled_object_id']}"
    )
if not binary_record["runtime_ready"] or manifest_record.get("runtime_ready") is not True:
    raise SystemExit(f"expected runtime-ready record, got binary={binary_record!r} manifest={manifest_record!r}")
if binding["policy_key"] == manifest_record["policy_key"]:
    raise SystemExit(f"expected canonical package policy key to stay distinct from runtime binding proxy key: {binding!r} manifest={manifest_record!r}")
if not str(manifest_asset["materialized_path"]).endswith(".rgba"):
    raise SystemExit(f"expected hts2phrb package assets to materialize as raw rgba, got {manifest_asset!r}")

expected_identity = manifest_record["canonical_identity"]
actual_identity = binary_record["canonical_identity"]
expected_pairs = {
    "fmt": int(expected_identity["fmt"]),
    "siz": int(expected_identity["siz"]),
    "off": int(expected_identity["off"]),
    "stride": int(expected_identity["stride"]),
    "wh": expected_identity["wh"],
    "formatsize": int(expected_identity["formatsize"]),
    "sampled_low32": int(str(expected_identity["sampled_low32"]), 16),
    "sampled_entry_pcrc": int(str(expected_identity["sampled_entry_pcrc"]), 16),
    "sampled_sparse_pcrc": int(str(expected_identity["sampled_sparse_pcrc"]), 16),
}
for key, expected in expected_pairs.items():
    actual = actual_identity[key]
    if actual != expected:
        raise SystemExit(f"identity mismatch for {key}: expected {expected!r}, got {actual!r}")

if binary_record["asset_candidate_count"] != manifest_record["asset_candidate_count"]:
    raise SystemExit("asset candidate count mismatch between manifest and binary record")

asset = binary_record["asset_candidates"][0]
if asset["replacement_id"] != manifest_asset["replacement_id"]:
    raise SystemExit("replacement_id mismatch")
if asset["legacy_source_path"] != str(cache_path):
    raise SystemExit(f"unexpected legacy source path: {asset['legacy_source_path']}")
if asset["legacy_checksum64"] != manifest_asset["legacy_checksum64"]:
    raise SystemExit(f"unexpected legacy checksum64: {asset['legacy_checksum64']}")
if asset["legacy_formatsize"] != int(manifest_asset["legacy_formatsize"]):
    raise SystemExit("legacy formatsize mismatch")
if asset["selector_checksum64"] != "0000000000000000":
    raise SystemExit(f"unexpected selector checksum: {asset['selector_checksum64']}")
if asset["rgba_blob_size"] != 8:
    raise SystemExit(f"unexpected rgba blob size: {asset['rgba_blob_size']}")
if asset["format"] != 0x8051:
    raise SystemExit(f"unexpected stored format: {asset['format']}")
if asset["texture_format"] != 0x1907:
    raise SystemExit(f"unexpected stored texture format: {asset['texture_format']}")
if asset["pixel_type"] != 0x8363:
    raise SystemExit(f"unexpected stored pixel type: {asset['pixel_type']}")
if asset["width"] != 2 or asset["height"] != 2:
    raise SystemExit(f"unexpected asset dimensions: {asset['width']}x{asset['height']}")

if binding["selection_reason"] != "deterministic-singleton-source-policy":
    raise SystemExit(f"unexpected binding selection reason: {binding['selection_reason']}")
if report["binary_package"]["record_count"] != 1 or report["binary_package"]["asset_count"] != 1:
    raise SystemExit("binary package counts in report do not match round-trip expectation")
if report["package_manifest_runtime_ready_record_count"] != 1 or report["package_manifest_runtime_deferred_record_count"] != 0:
    raise SystemExit(f"unexpected package runtime-ready counts: {report!r}")
if loader_manifest["runtime_ready_record_count"] != 1 or loader_manifest["runtime_deferred_record_count"] != 0:
    raise SystemExit(f"unexpected canonical loader runtime counts: {loader_manifest!r}")
if loader_manifest["runtime_ready_record_class"] != "native-sampled-only":
    raise SystemExit(f"unexpected canonical loader runtime-ready class: {loader_manifest['runtime_ready_record_class']!r}")
if runtime_loader_manifest["runtime_ready_record_count"] != 1 or runtime_loader_manifest["runtime_deferred_record_count"] != 0:
    raise SystemExit(f"unexpected runtime loader runtime counts: {runtime_loader_manifest!r}")
if runtime_loader_manifest["runtime_ready_record_class"] != "compat-only":
    raise SystemExit(f"unexpected runtime loader runtime-ready class: {runtime_loader_manifest['runtime_ready_record_class']!r}")
if package_manifest["runtime_ready_record_class"] != "native-sampled-only" or package_manifest["runtime_deferred_record_class"] != "none":
    raise SystemExit(f"unexpected package-manifest runtime classes: {package_manifest!r}")
if report["package_dir_bytes"] <= 0 or report["package_manifest_bytes"] <= 0:
    raise SystemExit(f"expected positive package byte counts, got report={report!r}")
family_states = report.get("requested_family_states") or {}
if family_states.get("binding_family_keys") != ["11111111:fs258"]:
    raise SystemExit(f"unexpected binding family keys: {family_states!r}")
if family_states.get("transport_unresolved_family_keys"):
    raise SystemExit(f"expected no unresolved transport families: {family_states!r}")
if family_states.get("runtime_state_counts") != {"runtime-bound": 1}:
    raise SystemExit(f"unexpected runtime state counts: {family_states!r}")
if report.get("promotion_blockers"):
    raise SystemExit(f"expected no promotion blockers, got {report['promotion_blockers']!r}")
stage_timings = report.get("stage_timings_ms") or {}
if float(stage_timings.get("total", -1)) < 0:
    raise SystemExit(f"expected non-negative total stage timing, got {stage_timings!r}")
PY

echo "emu_hts2phrb_round_trip: PASS"
