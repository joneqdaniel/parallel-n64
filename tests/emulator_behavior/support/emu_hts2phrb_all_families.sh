#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-all-families-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"
OUTPUT_DIR="$TMP_DIR/out"

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
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --all-families \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR"

python3 - "$ROOT_DIR" "$OUTPUT_DIR" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
out_dir = Path(sys.argv[2])
sys.path.insert(0, str(root / "tools"))
from hires_pack_inspect_binary_package import inspect_binary_package

report = json.loads((out_dir / "hts2phrb-report.json").read_text())
plan = json.loads((out_dir / "migration-plan.json").read_text())
summary_text = (out_dir / "hts2phrb-summary.md").read_text()
family_inventory = json.loads((out_dir / "hts2phrb-family-inventory.json").read_text())
binary = inspect_binary_package(Path(report["binary_package"]["output_path"]))

if report["request_mode"] != "all-families":
    raise SystemExit(f"unexpected request mode: {report['request_mode']!r}")
if report["requested_family_count"] != 2:
    raise SystemExit(f"expected two requested families, got {report['requested_family_count']}")
if report["binding_count"] != 0:
    raise SystemExit(f"expected zero bindings without runtime context, got {report['binding_count']}")
if report["runtime_overlay_mode"] != "auto" or report["runtime_overlay_built"]:
    raise SystemExit(f"expected runtime overlay to skip in all-families auto mode, got mode={report['runtime_overlay_mode']!r} built={report['runtime_overlay_built']!r}")
if report["runtime_overlay_reason"] != "no-runtime-context":
    raise SystemExit(f"unexpected runtime overlay reason: {report['runtime_overlay_reason']!r}")
if report.get("runtime_overlay_artifacts_emitted"):
    raise SystemExit(f"did not expect runtime overlay artifacts when overlay is skipped, got {report!r}")
if report.get("bindings_path") is not None or report.get("runtime_loader_manifest_path") is not None:
    raise SystemExit(f"did not expect runtime overlay artifact paths when overlay is skipped, got {report!r}")
if (out_dir / "bindings.json").exists() or (out_dir / "runtime-loader-manifest.json").exists():
    raise SystemExit("runtime overlay artifacts should not be emitted when runtime overlay is skipped")
if report["unresolved_count"] != 0:
    raise SystemExit(f"expected zero unresolved families, got {report['unresolved_count']}")
if report["bundle_path"] is not None:
    raise SystemExit(f"expected null bundle path, got {report['bundle_path']!r}")
if report["conversion_outcome"] != "promotable-runtime-package":
    raise SystemExit(f"unexpected conversion outcome: {report['conversion_outcome']!r}")
if report.get("minimum_outcome") is not None or report.get("require_promotable"):
    raise SystemExit(f"expected no explicit outcome gate metadata, got {report!r}")
if report["output_dir_was_default"]:
    raise SystemExit(f"did not expect default output dir for explicit output path: {report!r}")
if not report.get("gate_success", False) or report.get("gate_failures"):
    raise SystemExit(f"expected no gate failures without explicit gates, got {report!r}")
if report["package_manifest_record_count"] != 2 or report["binary_package"]["record_count"] != 2:
    raise SystemExit(f"expected two canonical package records, got report={report!r}")
if report["package_manifest_runtime_ready_record_count"] != 2 or report["package_manifest_runtime_deferred_record_count"] != 0:
    raise SystemExit(f"unexpected package runtime-ready counts: {report!r}")
if report["package_asset_storage"] != "legacy-blobs":
    raise SystemExit(f"unexpected package asset storage: {report['package_asset_storage']!r}")
if binary["version"] != 7 or binary["asset_count"] != 2:
    raise SystemExit(f"unexpected binary summary: {binary!r}")
if not all(record["runtime_ready"] for record in binary["records"]):
    raise SystemExit(f"expected all-families package records to be runtime-ready: {binary['records']!r}")
migration_summary = report.get("migration_plan_summary") or {}
if migration_summary.get("family_count") != 2:
    raise SystemExit(f"unexpected migration family count: {migration_summary!r}")
if migration_summary.get("tier_counts") != {"exact-authoritative": 2}:
    raise SystemExit(f"unexpected migration tier counts: {migration_summary!r}")
index_summary = report.get("imported_index_summary") or {}
if index_summary.get("exact_authority_count") != 2:
    raise SystemExit(f"unexpected imported index exact authority count: {index_summary!r}")
if index_summary.get("canonical_record_count") != 0:
    raise SystemExit(f"expected zero sampled canonical records without runtime context, got {index_summary!r}")
family_states = report.get("requested_family_states") or {}
if family_states.get("runtime_state_counts") != {"runtime-ready-package": 2}:
    raise SystemExit(f"unexpected runtime state counts: {family_states!r}")
if family_states.get("import_state_counts") != {"exact-authority": 2}:
    raise SystemExit(f"unexpected import state counts: {family_states!r}")
if report.get("runtime_state_counts") != {"runtime-ready-package": 2}:
    raise SystemExit(f"unexpected top-level runtime state counts: {report.get('runtime_state_counts')!r}")
if report.get("import_state_counts") != {"exact-authority": 2}:
    raise SystemExit(f"unexpected top-level import state counts: {report.get('import_state_counts')!r}")
if float(report.get("total_runtime_ms") or 0.0) <= 0.0:
    raise SystemExit(f"expected positive total_runtime_ms, got {report.get('total_runtime_ms')!r}")
families = sorted((item["family_key"], item["runtime_state"], item["import_state"], item["canonical_record_count"]) for item in (family_states.get("families") or []))
if families != [
    ("11111111:fs258", "runtime-ready-package", "exact-authority", 1),
    ("22222222:fs514", "runtime-ready-package", "exact-authority", 1),
]:
    raise SystemExit(f"unexpected family states: {families!r}")
if report.get("promotion_blockers"):
    raise SystemExit(f"expected no promotion blockers, got {report.get('promotion_blockers')!r}")
if "- Runtime overlay artifacts emitted: `no`" not in summary_text:
    raise SystemExit(f"expected summary markdown to include skipped overlay artifact state, got {summary_text!r}")
warnings = report.get("warnings") or []
if len(warnings) != 1 or "still contains runtime-ready canonical records" not in warnings[0]:
    raise SystemExit(f"unexpected warnings: {warnings!r}")

requested = sorted((item["low32"], item["formatsize"]) for item in plan["plan"]["families"])
if requested != [("11111111", 258), ("22222222", 514)]:
    raise SystemExit(f"unexpected requested families: {requested!r}")

if report["binding_policy_keys"] or report["binding_sampled_low32s"]:
    raise SystemExit(
        f"expected no runtime binding summaries in canonical-only mode, got keys={report['binding_policy_keys']!r} low32s={report['binding_sampled_low32s']!r}"
    )
if report.get("family_inventory_json_path") != str(out_dir / "hts2phrb-family-inventory.json"):
    raise SystemExit(f"unexpected family inventory json path: {report.get('family_inventory_json_path')!r}")
if report.get("family_inventory_markdown_path") != str(out_dir / "hts2phrb-family-inventory.md"):
    raise SystemExit(f"unexpected family inventory markdown path: {report.get('family_inventory_markdown_path')!r}")
if family_inventory.get("runtime_state_counts") != {"runtime-ready-package": 2}:
    raise SystemExit(f"unexpected family inventory runtime state counts: {family_inventory!r}")
if "Family inventory:" not in summary_text:
    raise SystemExit(f"expected summary markdown to link family inventory, got {summary_text!r}")
PY

echo "emu_hts2phrb_all_families: PASS"
