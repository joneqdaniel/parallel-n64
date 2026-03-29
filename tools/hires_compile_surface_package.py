#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

from hires_pack_common import GL_RGBA, GL_RGBA8, GL_UNSIGNED_BYTE
from hires_pack_emit_binary_package import emit_binary_package
from hires_pack_emit_loader_manifest import build_loader_manifest
from hires_pack_materialize_package import materialize_package
from hires_surface_edge_review import classify_unresolved_slots


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


def build_surface_binding(surface_entry: dict, group: dict | None, cache_path: str | None):
    surface = surface_entry["surface"]
    slots = surface.get("slots", [])
    embedded_candidates = {
        candidate['replacement_id']: candidate
        for candidate in surface_entry.get('candidate_snapshots', [])
    }
    candidates = embedded_candidates or (candidate_index(group) if group is not None else {})
    selectors = {}

    for slot in slots:
        replacement_id = slot.get("replacement_id")
        if not replacement_id:
            continue
        candidate = candidates.get(replacement_id)
        if candidate is None:
            raise SystemExit(
                f"replacement_id {replacement_id} is missing from sampled transport data for {surface['sampled_low32']}"
            )
        selector_checksum64 = slot["upload_key"].lower()
        selectors.setdefault(
            (replacement_id, selector_checksum64),
            build_transport_candidate(candidate, surface_entry.get('source_cache_path') or cache_path, selector_checksum64, surface["sampled_low32"]),
        )

    canonical_identity = dict(surface_entry.get('canonical_identity') or (group.get("canonical_identity", {}) if group is not None else {}))
    if not canonical_identity:
        raise SystemExit(f"sampled transport data for {surface['sampled_low32']} is missing canonical_identity")

    sampled_object_id = None
    if group is not None:
        sampled_object_id = group.get("sampled_object_id")
    if not sampled_object_id:
        sampled_object_id = (
            f"sampled-fmt{canonical_identity.get('fmt')}"
            f"-siz{canonical_identity.get('siz')}"
            f"-off{canonical_identity.get('off')}"
            f"-stride{canonical_identity.get('stride')}"
            f"-wh{canonical_identity.get('wh')}"
            f"-fs{canonical_identity.get('formatsize')}"
            f"-low32{canonical_identity.get('sampled_low32')}"
        )

    binding = {
        "policy_key": surface["surface_id"],
        "family_type": "ordered-surface",
        "status": "surface-compiled",
        "selection_reason": "ordered-surface-slot-map",
        "sampled_object_id": sampled_object_id,
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
        edge_review = classify_unresolved_slots(surface)
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
            "edge_review": {
                "first_resolved_index": edge_review.get("first_resolved_index"),
                "last_resolved_index": edge_review.get("last_resolved_index"),
                "unresolved_count": edge_review.get("unresolved_count", 0),
                "edge_only": edge_review.get("edge_only", False),
                "unresolved_slots": edge_review.get("unresolved_slots", []),
            },
        }

    return binding, unresolved


def compile_surface_package(surface_package_path: Path):
    surface_package = load_json(surface_package_path)
    surface_format = surface_package.get("format")
    if surface_format not in {"phrs-surface-package-v1", "phrs-surface-package-v2"}:
        raise SystemExit(f"unsupported surface package format: {surface_format}")

    review = None
    groups = {}
    cache_path = None
    provenance = surface_package.get("provenance") or {}
    review_value = provenance.get("review_path") or surface_package.get("review")
    surfaces = surface_package.get("surfaces", [])
    embedded_ready = all(
        surface_entry.get('canonical_identity') and surface_entry.get('candidate_snapshots') and surface_entry.get('source_cache_path')
        for surface_entry in surfaces
    )
    if review_value and not embedded_ready:
        review_path = Path(review_value)
        review = load_json(review_path)
        cache_path = review["cache"]
        groups = review_group_index(review)
    else:
        review_path = Path(review_value) if review_value else None

    bindings = []
    unresolved = []
    for surface_entry in surfaces:
        sampled_low32 = surface_entry["surface"]["sampled_low32"]
        group = groups.get(sampled_low32) if groups else None
        if group is None and not surface_entry.get('canonical_identity'):
            raise SystemExit(f"sampled_low32 {sampled_low32} is missing embedded transport data and review source")
        binding, unresolved_case = build_surface_binding(surface_entry, group, cache_path)
        bindings.append(binding)
        if unresolved_case is not None:
            unresolved.append(unresolved_case)

    return {
        "schema_version": 1,
        "source_input_path": str(surface_package_path),
        "surface_review_path": str(review_path) if review_path is not None else None,
        "bundle_path": review.get("bundle") if review is not None else surface_package.get("bundle_path"),
        "binding_count": len(bindings),
        "unresolved_count": len(unresolved),
        "bindings": bindings,
        "unresolved_transport_cases": unresolved,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Compile an ordered-surface package into standard bindings / loader manifest / PHRB artifacts."
    )
    parser.add_argument("--surface-package", required=True, help="Path to phrs-surface-package-v1 or phrs-surface-package-v2 JSON.")
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
