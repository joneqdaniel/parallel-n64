#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-XXXXXX)"
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
  --output-dir "$OUTPUT_DIR"

python3 - "$OUTPUT_DIR" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
report = json.loads((out_dir / "hts2phrb-report.json").read_text())
progress = json.loads((out_dir / "hts2phrb-progress.json").read_text())
loader_manifest = json.loads((out_dir / "loader-manifest.json").read_text())
runtime_loader_manifest = json.loads((out_dir / "runtime-loader-manifest.json").read_text())
package_manifest = json.loads((out_dir / "package" / "package-manifest.json").read_text())
bindings = json.loads((out_dir / "bindings.json").read_text())
plan = json.loads((out_dir / "migration-plan.json").read_text())
summary_text = (out_dir / "hts2phrb-summary.md").read_text()
family_inventory_json = out_dir / "hts2phrb-family-inventory.json"
family_inventory_md = out_dir / "hts2phrb-family-inventory.md"

if report["binding_count"] != 1:
    raise SystemExit(f"expected one binding, got {report['binding_count']}")
if report["runtime_overlay_mode"] != "auto" or not report["runtime_overlay_built"]:
    raise SystemExit(f"expected runtime overlay to build in bundle mode, got mode={report['runtime_overlay_mode']!r} built={report['runtime_overlay_built']!r}")
if report["runtime_overlay_reason"] != "runtime-context-available":
    raise SystemExit(f"unexpected runtime overlay reason: {report['runtime_overlay_reason']!r}")
if report["unresolved_count"] != 0:
    raise SystemExit(f"expected zero unresolved cases, got {report['unresolved_count']}")
if report["package_manifest_record_count"] != 1:
    raise SystemExit(f"expected one package record, got {report['package_manifest_record_count']}")
if report["package_manifest_runtime_ready_record_count"] != 1 or report["package_manifest_runtime_deferred_record_count"] != 0:
    raise SystemExit(f"unexpected package runtime-ready counts: {report!r}")
if report["package_manifest_runtime_ready_native_sampled_record_count"] != 1:
    raise SystemExit(
        f"expected one runtime-ready native-sampled record, got {report['package_manifest_runtime_ready_native_sampled_record_count']!r}"
    )
if report["package_manifest_runtime_ready_compat_record_count"] != 0:
    raise SystemExit(
        f"expected zero runtime-ready compat records, got {report['package_manifest_runtime_ready_compat_record_count']!r}"
    )
if report["package_manifest_runtime_deferred_native_sampled_record_count"] != 0 or report["package_manifest_runtime_deferred_compat_record_count"] != 0:
    raise SystemExit(
        "expected zero runtime-deferred native/compat records, "
        f"got native={report['package_manifest_runtime_deferred_native_sampled_record_count']!r} "
        f"compat={report['package_manifest_runtime_deferred_compat_record_count']!r}"
    )
if loader_manifest["runtime_ready_record_count"] != 1 or loader_manifest["runtime_deferred_record_count"] != 0:
    raise SystemExit(f"unexpected canonical loader runtime counts: {loader_manifest!r}")
if loader_manifest["runtime_ready_native_sampled_record_count"] != 1 or loader_manifest["runtime_ready_compat_record_count"] != 0:
    raise SystemExit(f"unexpected canonical loader runtime-ready class counts: {loader_manifest!r}")
if loader_manifest["runtime_ready_record_class"] != "native-sampled-only":
    raise SystemExit(f"unexpected canonical loader runtime-ready class: {loader_manifest['runtime_ready_record_class']!r}")
if runtime_loader_manifest["runtime_ready_record_count"] != 1 or runtime_loader_manifest["runtime_deferred_record_count"] != 0:
    raise SystemExit(f"unexpected runtime loader runtime counts: {runtime_loader_manifest!r}")
if runtime_loader_manifest["runtime_ready_native_sampled_record_count"] != 0 or runtime_loader_manifest["runtime_ready_compat_record_count"] != 1:
    raise SystemExit(f"unexpected runtime loader runtime-ready class counts: {runtime_loader_manifest!r}")
if runtime_loader_manifest["runtime_ready_record_class"] != "compat-only":
    raise SystemExit(f"unexpected runtime loader runtime-ready class: {runtime_loader_manifest['runtime_ready_record_class']!r}")
if package_manifest["runtime_ready_record_count"] != 1 or package_manifest["runtime_deferred_record_count"] != 0:
    raise SystemExit(f"unexpected package-manifest runtime counts: {package_manifest!r}")
if package_manifest["runtime_ready_native_sampled_record_count"] != 1 or package_manifest["runtime_ready_compat_record_count"] != 0:
    raise SystemExit(f"unexpected package-manifest runtime-ready class counts: {package_manifest!r}")
if package_manifest["runtime_ready_record_class"] != "native-sampled-only":
    raise SystemExit(f"unexpected package-manifest runtime-ready class: {package_manifest['runtime_ready_record_class']!r}")
if report["package_asset_storage"] != "legacy-blobs":
    raise SystemExit(f"unexpected package asset storage: {report['package_asset_storage']!r}")
if report["conversion_outcome"] != "promotable-runtime-package":
    raise SystemExit(f"unexpected conversion outcome: {report['conversion_outcome']!r}")
if report.get("minimum_outcome") is not None or report.get("require_promotable"):
    raise SystemExit(f"expected no explicit outcome gate metadata, got {report!r}")
if report["output_dir_was_default"]:
    raise SystemExit(f"did not expect default output dir for explicit output path: {report!r}")
if not report.get("gate_success", False) or report.get("gate_failures"):
    raise SystemExit(f"expected no gate failures without explicit gates, got {report!r}")
if report["warnings"]:
    raise SystemExit(f"expected no warnings, got {report['warnings']}")
if report["binding_policy_keys"] != ["sampled-fmt2-siz1-off0-stride2-wh2x2-fs258-low3211111111"]:
    raise SystemExit(f"unexpected binding policy keys: {report['binding_policy_keys']!r}")
if report["binding_sampled_low32s"] != ["11111111"]:
    raise SystemExit(f"unexpected binding sampled_low32s: {report['binding_sampled_low32s']!r}")
if report["unresolved_policy_keys"] or report["unresolved_sampled_low32s"]:
    raise SystemExit(
        f"expected no unresolved summaries, got keys={report['unresolved_policy_keys']!r} low32s={report['unresolved_sampled_low32s']!r}"
    )
if report["input_cache_bytes"] <= 0:
    raise SystemExit(f"expected positive input_cache_bytes, got {report['input_cache_bytes']}")
if report["binary_package_bytes"] <= 0:
    raise SystemExit(f"expected positive binary_package_bytes, got {report['binary_package_bytes']}")
if report["progress_path"] != str(out_dir / "hts2phrb-progress.json"):
    raise SystemExit(f"unexpected progress path: {report['progress_path']!r}")
if report.get("family_inventory_json_path") != str(family_inventory_json):
    raise SystemExit(f"unexpected family inventory json path: {report.get('family_inventory_json_path')!r}")
if report.get("family_inventory_markdown_path") != str(family_inventory_md):
    raise SystemExit(f"unexpected family inventory markdown path: {report.get('family_inventory_markdown_path')!r}")
if not family_inventory_json.exists() or not family_inventory_md.exists():
    raise SystemExit("missing family inventory artifacts")
if progress.get("status") != "complete":
    raise SystemExit(f"expected complete progress report, got {progress!r}")
if progress.get("binary_package", {}).get("record_count") != 1:
    raise SystemExit(f"unexpected progress binary summary: {progress!r}")
migration_summary = report.get("migration_plan_summary") or {}
if migration_summary.get("family_count") != 1:
    raise SystemExit(f"unexpected migration family count: {migration_summary!r}")
if migration_summary.get("tier_counts") != {"exact-authoritative": 1}:
    raise SystemExit(f"unexpected migration tier counts: {migration_summary!r}")
index_summary = report.get("imported_index_summary") or {}
if index_summary.get("exact_authority_count") != 1 or index_summary.get("canonical_record_count") != 1:
    raise SystemExit(f"unexpected imported index summary: {index_summary!r}")
family_states = report.get("requested_family_states") or {}
if family_states.get("runtime_state_counts") != {"runtime-bound": 1}:
    raise SystemExit(f"unexpected runtime state counts: {family_states!r}")
if family_states.get("import_state_counts") != {"exact-authority": 1}:
    raise SystemExit(f"unexpected import state counts: {family_states!r}")
if report.get("runtime_state_counts") != {"runtime-bound": 1}:
    raise SystemExit(f"unexpected top-level runtime state counts: {report.get('runtime_state_counts')!r}")
if report.get("import_state_counts") != {"exact-authority": 1}:
    raise SystemExit(f"unexpected top-level import state counts: {report.get('import_state_counts')!r}")
if float(report.get("total_runtime_ms") or 0.0) <= 0.0:
    raise SystemExit(f"expected positive total_runtime_ms, got {report.get('total_runtime_ms')!r}")
families = family_states.get("families") or []
if len(families) != 1:
    raise SystemExit(f"expected one family state, got {families!r}")
family = families[0]
if family["family_key"] != "11111111:fs258" or family["runtime_state"] != "runtime-bound" or family["import_state"] != "exact-authority":
    raise SystemExit(f"unexpected family state: {family!r}")
if report.get("promotion_blockers"):
    raise SystemExit(f"expected no promotion blockers, got {report['promotion_blockers']!r}")
if "Outcome: `promotable-runtime-package`" not in summary_text:
    raise SystemExit(f"expected summary markdown to include outcome, got {summary_text!r}")
if "Family inventory:" not in summary_text:
    raise SystemExit(f"expected summary markdown to link family inventory, got {summary_text!r}")
stage_timings = report.get("stage_timings_ms") or {}
required_stages = {
    "parse_cache",
    "resolve_requested_pairs",
    "build_migration_plan",
    "build_canonical_loader_manifest",
    "build_bindings",
    "build_runtime_loader_manifest",
    "materialize_package",
    "emit_binary_package",
    "total",
}
missing_stages = sorted(required_stages.difference(stage_timings))
if missing_stages:
    raise SystemExit(f"missing stage timings: {missing_stages}")
for stage_name in required_stages:
    if float(stage_timings[stage_name]) < 0:
        raise SystemExit(f"expected non-negative stage timing for {stage_name}, got {stage_timings[stage_name]!r}")

binding = bindings["bindings"][0]
if binding.get("selection_reason") != "deterministic-singleton-source-policy":
    raise SystemExit(f"unexpected selection reason: {binding.get('selection_reason')}")

records = plan["imported_index"]["canonical_records"]
if len(records) != 1:
    raise SystemExit(f"expected one canonical record, got {len(records)}")

package_path = Path(report["binary_package"]["output_path"])
if not package_path.exists():
    raise SystemExit(f"missing emitted package: {package_path}")
PY

echo "emu_hts2phrb_smoke: PASS"
