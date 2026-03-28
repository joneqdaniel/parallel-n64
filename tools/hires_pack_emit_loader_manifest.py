#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path


def load_bindings(path: Path):
    return json.loads(path.read_text())


def build_loader_manifest(bindings_data, bindings_path: Path):
    records = []
    for binding in bindings_data.get("bindings", []):
        asset_candidates = []
        for candidate in binding.get("transport_candidates", []):
            source = candidate.get("source", {})
            asset = candidate.get("replacement_asset", {})
            asset_candidates.append(
                {
                    "replacement_id": candidate.get("replacement_id"),
                    "legacy_checksum64": source.get("legacy_checksum64"),
                    "legacy_texture_crc": source.get("legacy_texture_crc"),
                    "legacy_palette_crc": source.get("legacy_palette_crc"),
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
            )
        records.append(
            {
                "policy_key": binding.get("policy_key"),
                "sampled_object_id": binding.get("sampled_object_id"),
                "canonical_identity": binding.get("canonical_identity", {}),
                "candidate_origin": binding.get("canonical_identity", {}).get("candidate_origin"),
                "transport_hint": binding.get("canonical_identity", {}).get("transport_hint"),
                "upload_low32s": binding.get("upload_low32s", []),
                "upload_pcrcs": binding.get("upload_pcrcs", []),
                "asset_candidate_count": len(asset_candidates),
                "asset_candidates": asset_candidates,
            }
        )

    return {
        "schema_version": 1,
        "source_bindings_path": str(bindings_path),
        "bundle_path": bindings_data.get("bundle_path"),
        "record_count": len(records),
        "records": records,
        "unresolved_transport_cases": bindings_data.get("unresolved_transport_cases", []),
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
