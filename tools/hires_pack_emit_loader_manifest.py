#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

RUNTIME_READY_FLAG = 1 << 0


def load_bindings(path: Path):
    return json.loads(path.read_text())


def make_asset_candidate_from_candidate(candidate, selector_checksum64=None):
    source = candidate.get("source", {})
    asset = candidate.get("replacement_asset", {})
    return {
        "replacement_id": candidate.get("replacement_id"),
        "legacy_checksum64": source.get("legacy_checksum64"),
        "legacy_texture_crc": source.get("legacy_texture_crc"),
        "legacy_palette_crc": source.get("legacy_palette_crc"),
        "selector_checksum64": selector_checksum64 if selector_checksum64 is not None else candidate.get("selector_checksum64"),
        "legacy_formatsize": source.get("legacy_formatsize"),
        "legacy_storage": source.get("legacy_storage"),
        "legacy_source_path": source.get("legacy_source_path"),
        "variant_group_id": candidate.get("variant_group_id"),
        "width": asset.get("width"),
        "height": asset.get("height"),
        "format": asset.get("format"),
        "texture_format": asset.get("texture_format"),
        "pixel_type": asset.get("pixel_type"),
        "data_size": asset.get("data_size"),
        "is_hires": asset.get("is_hires"),
    }


def make_asset_candidate_from_import_record(record, selector_checksum64="0000000000000000"):
    source = record.get("source", {})
    asset = record.get("replacement_asset", {})
    diagnostics = record.get("diagnostics", {})
    return {
        "replacement_id": record.get("replacement_id"),
        "legacy_checksum64": source.get("legacy_checksum64"),
        "legacy_texture_crc": source.get("legacy_texture_crc"),
        "legacy_palette_crc": source.get("legacy_palette_crc"),
        "selector_checksum64": selector_checksum64,
        "legacy_formatsize": source.get("legacy_formatsize"),
        "legacy_storage": source.get("legacy_storage"),
        "legacy_source_path": source.get("legacy_source_path"),
        "variant_group_id": diagnostics.get("variant_group_id"),
        "width": asset.get("width"),
        "height": asset.get("height"),
        "format": asset.get("format"),
        "texture_format": asset.get("texture_format"),
        "pixel_type": asset.get("pixel_type"),
        "data_size": asset.get("data_size"),
        "is_hires": asset.get("is_hires"),
    }


def normalize_upload_values(items):
    normalized = []
    for item in items or []:
        if isinstance(item, dict):
            value = item.get("value")
            if value is None:
                continue
            normalized.append({"value": value})
        else:
            normalized.append({"value": item})
    return normalized


def classify_runtime_record_class(native_count, compat_count):
    native_count = int(native_count or 0)
    compat_count = int(compat_count or 0)
    if native_count > 0 and compat_count == 0:
        return "native-sampled-only"
    if native_count == 0 and compat_count > 0:
        return "compat-only"
    if native_count > 0 and compat_count > 0:
        return "mixed-native-and-compat"
    return "none"


def summarize_runtime_records(records):
    runtime_ready_record_count = 0
    runtime_deferred_record_count = 0
    runtime_ready_record_kind_counts = {}
    runtime_deferred_record_kind_counts = {}
    for record in records:
        record_kind = str(record.get("record_kind") or "unknown")
        if bool(record.get("runtime_ready")):
            runtime_ready_record_count += 1
            runtime_ready_record_kind_counts[record_kind] = runtime_ready_record_kind_counts.get(record_kind, 0) + 1
        else:
            runtime_deferred_record_count += 1
            runtime_deferred_record_kind_counts[record_kind] = runtime_deferred_record_kind_counts.get(record_kind, 0) + 1

    runtime_ready_native_sampled_record_count = int(runtime_ready_record_kind_counts.get("canonical-sampled", 0))
    runtime_deferred_native_sampled_record_count = int(runtime_deferred_record_kind_counts.get("canonical-sampled", 0))
    runtime_ready_compat_record_count = int(runtime_ready_record_count - runtime_ready_native_sampled_record_count)
    runtime_deferred_compat_record_count = int(runtime_deferred_record_count - runtime_deferred_native_sampled_record_count)

    return {
        "record_count": len(records),
        "runtime_ready_record_count": runtime_ready_record_count,
        "runtime_deferred_record_count": runtime_deferred_record_count,
        "runtime_ready_record_kind_counts": dict(sorted(runtime_ready_record_kind_counts.items())),
        "runtime_deferred_record_kind_counts": dict(sorted(runtime_deferred_record_kind_counts.items())),
        "runtime_ready_native_sampled_record_count": runtime_ready_native_sampled_record_count,
        "runtime_ready_compat_record_count": runtime_ready_compat_record_count,
        "runtime_deferred_native_sampled_record_count": runtime_deferred_native_sampled_record_count,
        "runtime_deferred_compat_record_count": runtime_deferred_compat_record_count,
        "runtime_ready_record_class": classify_runtime_record_class(
            runtime_ready_native_sampled_record_count,
            runtime_ready_compat_record_count,
        ),
        "runtime_deferred_record_class": classify_runtime_record_class(
            runtime_deferred_native_sampled_record_count,
            runtime_deferred_compat_record_count,
        ),
    }


def build_loader_manifest(bindings_data, bindings_path: Path):
    records = []
    for binding in bindings_data.get("bindings", []):
        asset_candidates = []
        for candidate in binding.get("transport_candidates", []):
            asset_candidates.append(make_asset_candidate_from_candidate(candidate))
        records.append(
            {
                "policy_key": binding.get("policy_key"),
                "sampled_object_id": binding.get("sampled_object_id"),
                "record_kind": binding.get("family_type") or "runtime-proxy-binding",
                "record_flags": RUNTIME_READY_FLAG,
                "runtime_ready": True,
                "canonical_identity": binding.get("canonical_identity", {}),
                "candidate_origin": binding.get("canonical_identity", {}).get("candidate_origin"),
                "transport_hint": binding.get("canonical_identity", {}).get("transport_hint"),
                "upload_low32s": binding.get("upload_low32s", []),
                "upload_pcrcs": binding.get("upload_pcrcs", []),
                "asset_candidate_count": len(asset_candidates),
                "asset_candidates": asset_candidates,
            }
        )

    summary = summarize_runtime_records(records)
    return {
        "schema_version": 1,
        "source_bindings_path": str(bindings_path),
        "bundle_path": bindings_data.get("bundle_path"),
        "record_count": summary["record_count"],
        "runtime_ready_record_count": summary["runtime_ready_record_count"],
        "runtime_deferred_record_count": summary["runtime_deferred_record_count"],
        "runtime_ready_record_kind_counts": summary["runtime_ready_record_kind_counts"],
        "runtime_deferred_record_kind_counts": summary["runtime_deferred_record_kind_counts"],
        "runtime_ready_native_sampled_record_count": summary["runtime_ready_native_sampled_record_count"],
        "runtime_ready_compat_record_count": summary["runtime_ready_compat_record_count"],
        "runtime_deferred_native_sampled_record_count": summary["runtime_deferred_native_sampled_record_count"],
        "runtime_deferred_compat_record_count": summary["runtime_deferred_compat_record_count"],
        "runtime_ready_record_class": summary["runtime_ready_record_class"],
        "runtime_deferred_record_class": summary["runtime_deferred_record_class"],
        "records": records,
        "unresolved_transport_cases": bindings_data.get("unresolved_transport_cases", []),
    }


def build_canonical_loader_manifest(imported_index_data, imported_index_path: Path):
    imported_records = {
        record.get("replacement_id"): record
        for record in imported_index_data.get("records", [])
        if record.get("replacement_id")
    }

    def make_family_runtime_stub(family_type, family):
        match = family.get("match", {})
        low32 = family.get("family_low32") or match.get("texture_crc")
        formatsize = family.get("formatsize")
        if formatsize is None:
            formatsize = match.get("formatsize") or 0
        policy_key = family.get("policy_key") or family.get("alias_id") or f"legacy-family-{low32}-fs{formatsize}"
        transport_hint = family.get("active_pool") or match.get("active_pool")
        candidate_replacement_ids = family.get("candidate_replacement_ids", [])
        runtime_ready = family_type != "unresolved-family" and bool(candidate_replacement_ids)
        return {
            "policy_key": policy_key,
            "sampled_object_id": policy_key,
            "record_kind": family_type,
            "record_flags": RUNTIME_READY_FLAG if runtime_ready else 0,
            "runtime_ready": runtime_ready,
            "canonical_identity": {
                "candidate_origin": f"legacy-family-{family_type}",
                "transport_hint": transport_hint,
                "evidence_authority": (family.get("observed_runtime_context") or {}).get("mode"),
                "draw_class": "legacy-family",
                "cycle": "unknown",
                "fmt": 0,
                "siz": 0,
                "off": 0,
                "stride": 0,
                "wh": "0x0",
                "formatsize": int(formatsize or 0),
                "sampled_low32": low32,
                "sampled_entry_pcrc": 0,
                "sampled_sparse_pcrc": 0,
                "runtime_ready": runtime_ready,
            },
            "candidate_origin": f"legacy-family-{family_type}",
            "transport_hint": transport_hint,
            "upload_low32s": [{"value": low32}] if low32 else [],
            "upload_pcrcs": [],
            "asset_candidates": [
                make_asset_candidate_from_import_record(imported_records[replacement_id])
                for replacement_id in candidate_replacement_ids
                if replacement_id in imported_records
            ],
        }

    records = []
    for record in imported_index_data.get("canonical_records", []):
        policy_keys = sorted(policy_key for policy_key in record.get("linked_policy_keys", []) if policy_key)
        policy_key = policy_keys[0] if policy_keys else (record.get("sampled_object_id") or "canonical-record")
        asset_candidates = []
        for candidate in record.get("transport_candidates", []):
            asset_candidates.append(make_asset_candidate_from_candidate(candidate, selector_checksum64="0000000000000000"))
        if not asset_candidates:
            for replacement_id in record.get("linked_replacement_ids", []):
                source_record = imported_records.get(replacement_id)
                if source_record:
                    asset_candidates.append(make_asset_candidate_from_import_record(source_record))

        records.append(
            {
                "policy_key": policy_key,
                "sampled_object_id": record.get("sampled_object_id"),
                "record_kind": "canonical-sampled",
                "record_flags": RUNTIME_READY_FLAG if record.get("runtime_ready") else 0,
                "runtime_ready": bool(record.get("runtime_ready")),
                "canonical_identity": {
                    "candidate_origin": record.get("candidate_origin"),
                    "transport_hint": record.get("transport_hint"),
                    "evidence_authority": record.get("evidence_authority"),
                    "draw_class": record.get("draw_class"),
                    "cycle": record.get("cycle"),
                    "fmt": int(record.get("fmt") or 0),
                    "siz": int(record.get("siz") or 0),
                    "off": int(record.get("off") or 0),
                    "stride": int(record.get("stride") or 0),
                    "wh": record.get("wh") or "0x0",
                    "formatsize": int(record.get("formatsize") or 0),
                    "sampled_low32": record.get("sampled_low32"),
                    "sampled_entry_pcrc": record.get("sampled_entry_pcrc"),
                    "sampled_sparse_pcrc": record.get("sampled_sparse_pcrc"),
                    "runtime_ready": bool(record.get("runtime_ready")),
                },
                "candidate_origin": record.get("candidate_origin"),
                "transport_hint": record.get("transport_hint"),
                "upload_low32s": normalize_upload_values(record.get("upload_low32s", [])),
                "upload_pcrcs": normalize_upload_values(record.get("upload_pcrcs", [])),
                "linked_policy_keys": policy_keys,
                "linked_replacement_ids": list(record.get("linked_replacement_ids", [])),
                "asset_candidates": asset_candidates,
            }
        )

    for family_type, families in (
        ("exact-authority-family", imported_index_data.get("exact_authorities", [])),
        ("compatibility-alias-family", imported_index_data.get("compatibility_aliases", [])),
        ("unresolved-family", imported_index_data.get("unresolved_families", [])),
    ):
        for family in families:
            if family.get("canonical_sampled_objects"):
                continue
            records.append(make_family_runtime_stub(family_type, family))

    for record in records:
        record["asset_candidate_count"] = len(record.get("asset_candidates", []))

    summary = summarize_runtime_records(records)
    return {
        "schema_version": 1,
        "source_imported_index_path": str(imported_index_path),
        "record_count": summary["record_count"],
        "runtime_ready_record_count": summary["runtime_ready_record_count"],
        "runtime_deferred_record_count": summary["runtime_deferred_record_count"],
        "runtime_ready_record_kind_counts": summary["runtime_ready_record_kind_counts"],
        "runtime_deferred_record_kind_counts": summary["runtime_deferred_record_kind_counts"],
        "runtime_ready_native_sampled_record_count": summary["runtime_ready_native_sampled_record_count"],
        "runtime_ready_compat_record_count": summary["runtime_ready_compat_record_count"],
        "runtime_deferred_native_sampled_record_count": summary["runtime_deferred_native_sampled_record_count"],
        "runtime_deferred_compat_record_count": summary["runtime_deferred_compat_record_count"],
        "runtime_ready_record_class": summary["runtime_ready_record_class"],
        "runtime_deferred_record_class": summary["runtime_deferred_record_class"],
        "records": records,
        "unresolved_transport_cases": [],
    }


def main():
    parser = argparse.ArgumentParser(description="Emit a loader-oriented canonical hi-res manifest from deterministic bindings.")
    parser.add_argument("--bindings", required=True, help="Path to canonical bindings JSON.")
    parser.add_argument("--output", help="Optional output JSON path.")
    args = parser.parse_args()

    bindings_path = Path(args.bindings)
    bindings_data = load_bindings(bindings_path)
    result = build_loader_manifest(bindings_data, bindings_path)
    serialized = json.dumps(result, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(serialized)
    else:
        sys.stdout.write(serialized)


if __name__ == "__main__":
    main()
