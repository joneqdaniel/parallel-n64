#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

from hires_pack_common import GL_RGBA, GL_RGBA8, GL_UNSIGNED_BYTE
from hires_pack_emit_binary_package import emit_binary_package
from hires_pack_emit_loader_manifest import build_loader_manifest
from hires_pack_materialize_package import materialize_package


def load_json(path: Path):
    return json.loads(path.read_text())


def review_group_index(review: dict):
    groups = {}
    for group in review.get("groups", []):
        signature = group.get("signature", {})
        sampled_low32 = signature.get("sampled_low32")
        if sampled_low32:
            groups[sampled_low32] = group
    return groups


def candidate_index(group: dict):
    return {
        candidate["replacement_id"]: candidate
        for candidate in group.get("transport_candidates", [])
    }


def build_transport_candidate(candidate: dict, cache_path: str, selector_checksum64: str, sampled_low32: str):
    width = int(candidate["width"])
    height = int(candidate["height"])
    return {
        "replacement_id": candidate["replacement_id"],
        "source": {
            "legacy_checksum64": candidate["checksum64"],
            "legacy_texture_crc": candidate["texture_crc"],
            "legacy_palette_crc": candidate["palette_crc"],
            "legacy_formatsize": candidate["formatsize"],
            "legacy_storage": "hts",
            "legacy_source_path": cache_path,
        },
        "match": {
            "exact_legacy_checksum64": candidate["checksum64"],
            "texture_crc": candidate["texture_crc"],
            "palette_crc": candidate["palette_crc"],
            "formatsize": candidate["formatsize"],
        },
        "replacement_asset": {
            "width": width,
            "height": height,
            "format": GL_RGBA8,
            "texture_format": GL_RGBA,
            "pixel_type": GL_UNSIGNED_BYTE,
            "data_size": candidate["data_size"],
            "is_hires": True,
        },
        "selector_checksum64": selector_checksum64,
        "variant_group_id": f"surface-{sampled_low32}-{selector_checksum64}",
    }


def build_surface_binding(surface_entry: dict, group: dict, cache_path: str):
    surface = surface_entry["surface"]
    slots = surface.get("slots", [])
    candidates = candidate_index(group)
    selectors = {}

    for slot in slots:
        replacement_id = slot.get("replacement_id")
        if not replacement_id:
            continue
        candidate = candidates.get(replacement_id)
        if candidate is None:
            raise SystemExit(
                f"replacement_id {replacement_id} is missing from sampled review group {surface['sampled_low32']}"
            )
        selector_checksum64 = slot["upload_key"].lower()
        selectors.setdefault(
            (replacement_id, selector_checksum64),
            build_transport_candidate(candidate, cache_path, selector_checksum64, surface["sampled_low32"]),
        )

    canonical_identity = dict(group.get("canonical_identity", {}))
    if not canonical_identity:
        raise SystemExit(f"sampled review group {surface['sampled_low32']} is missing canonical_identity")

    binding = {
        "policy_key": surface["surface_id"],
        "family_type": "ordered-surface",
        "status": "surface-compiled",
        "selection_reason": "ordered-surface-slot-map",
        "sampled_object_id": group.get("sampled_object_id") or f"sampled-low32-{surface['sampled_low32']}",
        "canonical_identity": canonical_identity,
        "surface_tile_dims": surface.get("surface_tile_dims"),
        "slot_count": surface.get("slot_count", 0),
        "upload_low32s": [],
        "upload_pcrcs": [],
        "transport_candidates": sorted(
            selectors.values(),
            key=lambda item: (item["selector_checksum64"], item["replacement_id"]),
        ),
    }

    low32_counts = {}
    pcrc_counts = {}
    for slot in slots:
        upload_key = slot["upload_key"].lower()
        low32 = upload_key[-8:]
        pcrc = upload_key[:8]
        low32_counts[low32] = low32_counts.get(low32, 0) + 1
        pcrc_counts[pcrc] = pcrc_counts.get(pcrc, 0) + 1
    binding["upload_low32s"] = [
        {"value": value, "count": count}
        for value, count in sorted(low32_counts.items())
    ]
    binding["upload_pcrcs"] = [
        {"value": value, "count": count}
        for value, count in sorted(pcrc_counts.items())
    ]

    unresolved = None
    if surface.get("unresolved_sequences"):
        unresolved = {
            "policy_key": f"{surface['surface_id']}-unresolved",
            "family_type": "ordered-surface",
            "status": "manual-review-required",
            "reason": "ordered-surface-unresolved-slots",
            "sampled_object_id": binding["sampled_object_id"],
            "canonical_identity": canonical_identity,
            "surface_tile_dims": surface.get("surface_tile_dims"),
            "slot_count": surface.get("slot_count", 0),
            "unresolved_sequences": surface.get("unresolved_sequences", []),
        }

    return binding, unresolved


def compile_surface_package(surface_package_path: Path):
    surface_package = load_json(surface_package_path)
    if surface_package.get("format") != "phrs-surface-package-v1":
        raise SystemExit(f"unsupported surface package format: {surface_package.get('format')}")

    review_path = Path(surface_package["review"])
    review = load_json(review_path)
    cache_path = review["cache"]
    groups = review_group_index(review)

    bindings = []
    unresolved = []
    for surface_entry in surface_package.get("surfaces", []):
        sampled_low32 = surface_entry["surface"]["sampled_low32"]
        group = groups.get(sampled_low32)
        if group is None:
            raise SystemExit(f"sampled_low32 {sampled_low32} is missing from {review_path}")
        binding, unresolved_case = build_surface_binding(surface_entry, group, cache_path)
        bindings.append(binding)
        if unresolved_case is not None:
            unresolved.append(unresolved_case)

    return {
        "schema_version": 1,
        "source_input_path": str(surface_package_path),
        "surface_review_path": str(review_path),
        "bundle_path": review.get("bundle"),
        "binding_count": len(bindings),
        "unresolved_count": len(unresolved),
        "bindings": bindings,
        "unresolved_transport_cases": unresolved,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Compile an ordered-surface package into standard bindings / loader manifest / PHRB artifacts."
    )
    parser.add_argument("--surface-package", required=True, help="Path to phrs-surface-package-v1 JSON.")
    parser.add_argument("--output-dir", required=True, help="Output directory for compiled artifacts.")
    parser.add_argument("--package-name", default="package.phrb", help="Binary package filename relative to output dir.")
    parser.add_argument("--allow-unresolved", action="store_true", help="Keep unresolved ordered-surface slots in metadata.")
    args = parser.parse_args()

    surface_package_path = Path(args.surface_package)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    bindings = compile_surface_package(surface_package_path)
    unresolved = bindings.get("unresolved_transport_cases", [])
    if unresolved and not args.allow_unresolved:
        unresolved_keys = [item.get("policy_key") for item in unresolved]
        raise SystemExit(
            "Compiled surface package still has unresolved slots. "
            "Pass --allow-unresolved to keep them in metadata only. "
            f"Unresolved: {unresolved_keys}"
        )

    bindings_path = output_dir / "bindings.json"
    bindings_path.write_text(json.dumps(bindings, indent=2) + "\n")

    loader_manifest = build_loader_manifest(bindings, bindings_path)
    loader_manifest_path = output_dir / "loader-manifest.json"
    loader_manifest_path.write_text(json.dumps(loader_manifest, indent=2) + "\n")

    package_dir = output_dir / "package"
    package_manifest = materialize_package(loader_manifest_path, package_dir)
    binary_path = output_dir / args.package_name
    binary_result = emit_binary_package(package_dir, binary_path)

    result = {
        "surface_package_path": str(surface_package_path),
        "bindings_path": str(bindings_path),
        "loader_manifest_path": str(loader_manifest_path),
        "package_dir": str(package_dir),
        "binding_count": bindings.get("binding_count", 0),
        "unresolved_count": len(unresolved),
        "package_manifest_record_count": package_manifest.get("record_count", 0),
        "binary_package": binary_result,
    }
    sys.stdout.write(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
