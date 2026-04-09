#!/usr/bin/env python3
import argparse
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

from hires_pack_common import (
    build_family_summary,
    collect_family_entries,
    decode_entry_rgba8,
    index_entries_by_texture_crc,
    parse_bundle_ci_context,
    parse_bundle_families,
    parse_bundle_sampled_object_context,
    parse_cache_entries,
)


def build_migration_plan(entries, requested_pairs):
    indexed_entries = index_entries_by_texture_crc(entries)
    families = [build_family_summary(indexed_entries, texture_crc, formatsize) for texture_crc, formatsize in requested_pairs]
    tier_counts = Counter(family["recommended_tier"] for family in families)

    plan = {
        "family_count": len(families),
        "tier_counts": dict(tier_counts),
        "families": families,
        "migration_guidance": {
            "exact-authoritative": "Preserve as exact identity in the imported index.",
            "compat-unique": "Safe candidate for an explicit compatibility alias in the imported index.",
            "compat-repl-dims-unique": "Candidate for constrained compatibility import if dimensions and fixture evidence stay stable.",
            "ambiguous-import-or-policy": "Do not auto-promote into runtime fallback. Require imported disambiguation or explicit policy fields.",
            "missing-active-pool": "No active exact/generic family available for requested formatsize.",
        },
    }
    return plan


def make_replacement_id(texture_crc, palette_crc, formatsize, width, height):
    return f"legacy-{texture_crc:08x}-{palette_crc:08x}-fs{formatsize}-{width}x{height}"


def make_variant_group_id(texture_crc, requested_formatsize, width, height):
    return f"legacy-low32-{texture_crc:08x}-fs{requested_formatsize}-{width}x{height}"


def make_family_policy_key(texture_crc, formatsize):
    return f"legacy-low32-{texture_crc:08x}-fs{formatsize}"


def load_import_policy(policy_path):
    data = json.loads(Path(policy_path).read_text())
    return {
        "schema_version": data.get("schema_version", 0),
        "families": data.get("families", {}),
        "source_path": str(policy_path),
    }


def build_selector_policy(texture_crc, formatsize, observation, variant_group_list, tier, selection_override=None):
    base_selector = {
        "texture_crc": f"{texture_crc:08x}",
        "requested_formatsize": formatsize,
    }
    if observation:
        base_selector.update(
            {
                "mode": observation.get("mode"),
                "runtime_wh": observation.get("runtime_wh"),
            }
        )

    disambiguation_inputs = []
    if observation:
        disambiguation_inputs.extend(
            [
                "observed_runtime_pcrc",
                "usage.mask_crc",
                "usage.sparse_pcrc",
                "emulated_tmem.entry_pcrc",
                "emulated_tmem.sparse_pcrc",
            ]
        )

    if tier == "missing-active-pool":
        return {
            "status": "manual-disambiguation-required",
            "selector_basis": base_selector,
            "candidate_variant_group_ids": [],
            "disambiguation_inputs": disambiguation_inputs,
            "selection_reason": "missing-active-pool",
        }

    exact_deterministic = tier == "exact-authoritative" and len(variant_group_list) == 1
    policy = {
        "status": (
            "deterministic"
            if tier in ("compat-unique", "compat-repl-dims-unique") or exact_deterministic
            else "manual-disambiguation-required"
        ),
        "selector_basis": base_selector,
        "candidate_variant_group_ids": [group["variant_group_id"] for group in variant_group_list],
        "disambiguation_inputs": disambiguation_inputs,
    }

    if selection_override:
        policy["status"] = "deterministic"
        policy["selected_variant_group_id"] = selection_override["selected_variant_group_id"]
        policy["selection_reason"] = selection_override["selection_reason"]
        policy["selection_override"] = {
            key: value
            for key, value in selection_override.items()
            if key not in ("selected_variant_group_id", "selection_reason", "selected_replacement_ids")
        }
    elif (tier in ("compat-unique", "compat-repl-dims-unique") or exact_deterministic) and len(variant_group_list) == 1:
        policy["selected_variant_group_id"] = variant_group_list[0]["variant_group_id"]
        policy["selection_reason"] = "exact-authoritative" if exact_deterministic else tier
    else:
        policy["selection_reason"] = "legacy-family-ambiguous"

    return policy


def _parse_variant_group_dims(group):
    dims_text = str(group.get("dims") or "")
    if "x" not in dims_text:
        return None
    width_text, height_text = dims_text.split("x", 1)
    try:
        width = int(width_text)
        height = int(height_text)
    except ValueError:
        return None
    if width <= 0 or height <= 0:
        return None
    return width, height


def _resolve_scale_equivalent_group_order(variant_group_list):
    if len(variant_group_list) != 2:
        return None
    first_dims = _parse_variant_group_dims(variant_group_list[0])
    second_dims = _parse_variant_group_dims(variant_group_list[1])
    if first_dims is None or second_dims is None:
        return None
    (first_width, first_height) = first_dims
    (second_width, second_height) = second_dims
    if first_width == second_width and first_height == second_height:
        return None

    if second_width >= first_width and second_height >= first_height:
        smaller_index = 0
        larger_index = 1
    elif first_width >= second_width and first_height >= second_height:
        smaller_index = 1
        larger_index = 0
    else:
        return None

    smaller_width, smaller_height = _parse_variant_group_dims(variant_group_list[smaller_index])
    larger_width, larger_height = _parse_variant_group_dims(variant_group_list[larger_index])
    if (
        larger_width % smaller_width != 0
        or larger_height % smaller_height != 0
    ):
        return None

    scale_x = larger_width // smaller_width
    scale_y = larger_height // smaller_height
    if scale_x <= 0 or scale_y <= 0:
        return None
    if scale_x == 1 and scale_y == 1:
        return None

    return {
        "smaller_index": smaller_index,
        "larger_index": larger_index,
        "scale_x": scale_x,
        "scale_y": scale_y,
    }


def _exact_nearest_neighbor_scale_match(smaller_rgba, smaller_width, smaller_height, larger_rgba, larger_width, larger_height, scale_x, scale_y):
    if len(smaller_rgba) != smaller_width * smaller_height * 4:
        return False
    if len(larger_rgba) != larger_width * larger_height * 4:
        return False
    for larger_y in range(larger_height):
        source_y = larger_y // scale_y
        larger_row_offset = larger_y * larger_width * 4
        smaller_row_offset = source_y * smaller_width * 4
        for larger_x in range(larger_width):
            source_x = larger_x // scale_x
            larger_offset = larger_row_offset + larger_x * 4
            smaller_offset = smaller_row_offset + source_x * 4
            if larger_rgba[larger_offset:larger_offset + 4] != smaller_rgba[smaller_offset:smaller_offset + 4]:
                return False
    return True


def _decode_variant_group_representative(source_cache_path, cache_bytes, variant_group, variant_group_entries, decoded_rgba_cache):
    group_entries = variant_group_entries.get(variant_group.get("variant_group_id"), [])
    if not group_entries:
        return None

    representative_rgba = None
    representative_hash = None
    representative_width = None
    representative_height = None

    for replacement_id, entry in group_entries:
        rgba = decoded_rgba_cache.get(replacement_id)
        if rgba is None:
            try:
                rgba = decode_entry_rgba8(source_cache_path, entry, cache_bytes=cache_bytes)
            except Exception:
                return None
            decoded_rgba_cache[replacement_id] = rgba
        rgba_hash = hashlib.sha256(rgba).hexdigest()
        if representative_hash is None:
            representative_rgba = rgba
            representative_hash = rgba_hash
            representative_width = int(entry.get("width", 0))
            representative_height = int(entry.get("height", 0))
        elif rgba_hash != representative_hash:
            return None

    return {
        "rgba": representative_rgba,
        "pixel_sha256": representative_hash,
        "width": representative_width,
        "height": representative_height,
    }


def build_exact_scale_equivalent_selection(texture_crc, formatsize, variant_group_list, variant_group_entries, source_cache_path, cache_bytes, decoded_rgba_cache):
    ordered_groups = _resolve_scale_equivalent_group_order(variant_group_list)
    if ordered_groups is None:
        return None

    smaller_group = variant_group_list[ordered_groups["smaller_index"]]
    larger_group = variant_group_list[ordered_groups["larger_index"]]
    smaller_representative = _decode_variant_group_representative(
        source_cache_path,
        cache_bytes,
        smaller_group,
        variant_group_entries,
        decoded_rgba_cache,
    )
    if smaller_representative is None:
        return None
    larger_representative = _decode_variant_group_representative(
        source_cache_path,
        cache_bytes,
        larger_group,
        variant_group_entries,
        decoded_rgba_cache,
    )
    if larger_representative is None:
        return None

    if not _exact_nearest_neighbor_scale_match(
        smaller_representative["rgba"],
        smaller_representative["width"],
        smaller_representative["height"],
        larger_representative["rgba"],
        larger_representative["width"],
        larger_representative["height"],
        ordered_groups["scale_x"],
        ordered_groups["scale_y"],
    ):
        return None

    return {
        "selection_reason": "exact-scale-equivalent",
        "selected_variant_group_id": larger_group["variant_group_id"],
        "selected_variant_group_ids": [larger_group["variant_group_id"]],
        "selected_replacement_ids": list(larger_group.get("candidate_replacement_ids", [])),
        "collapsed_variant_group_ids": [group["variant_group_id"] for group in variant_group_list],
        "collapsed_variant_group_dims": [group["dims"] for group in variant_group_list],
        "selected_dims": larger_group.get("dims"),
        "smaller_dims": smaller_group.get("dims"),
        "scale_x": ordered_groups["scale_x"],
        "scale_y": ordered_groups["scale_y"],
        "selected_pixel_sha256": larger_representative["pixel_sha256"],
        "smaller_pixel_sha256": smaller_representative["pixel_sha256"],
        "applies_to_family": make_family_policy_key(texture_crc, formatsize),
    }


def build_canonical_transport(exact_authorities, compatibility_aliases, unresolved_families, record_index):
    canonical_records = {}
    legacy_transport_aliases = []

    def make_transport_candidate(replacement_id):
        source_record = record_index.get(replacement_id)
        if not source_record:
            return {
                "replacement_id": replacement_id,
            }
        return {
            "replacement_id": replacement_id,
            "source": dict(source_record.get("source", {})),
            "match": dict(source_record.get("match", {})),
            "replacement_asset": dict(source_record.get("replacement_asset", {})),
            "variant_group_id": source_record.get("diagnostics", {}).get("variant_group_id"),
        }

    def ingest_family(family, family_type):
        policy_key = family.get("policy_key") or family.get("alias_id")
        canonical_objects = family.get("canonical_sampled_objects") or []
        alias = {
            "family_type": family_type,
            "policy_key": policy_key,
            "reason": family.get("reason"),
            "kind": family.get("kind"),
            "status": (family.get("selector_policy") or {}).get("status"),
            "selection_reason": (family.get("selector_policy") or {}).get("selection_reason"),
            "candidate_replacement_ids": family.get("candidate_replacement_ids", []),
            "canonical_sampled_object_ids": [obj.get("sampled_object_id") for obj in canonical_objects],
        }
        legacy_transport_aliases.append(alias)

        for obj in canonical_objects:
            sampled_object_id = obj.get("sampled_object_id")
            if not sampled_object_id:
                continue
            record = canonical_records.setdefault(
                sampled_object_id,
                {
                    "sampled_object_id": sampled_object_id,
                    "candidate_origin": obj.get("candidate_origin"),
                    "transport_hint": obj.get("transport_hint"),
                    "evidence_authority": obj.get("evidence_authority"),
                    "draw_class": obj.get("draw_class"),
                    "cycle": obj.get("cycle"),
                    "fmt": obj.get("fmt"),
                    "siz": obj.get("siz"),
                    "off": obj.get("off"),
                    "stride": obj.get("stride"),
                    "wh": obj.get("wh"),
                    "formatsize": obj.get("formatsize"),
                    "sampled_low32": obj.get("sampled_low32"),
                    "sampled_entry_pcrc": obj.get("sampled_entry_pcrc"),
                    "sampled_sparse_pcrc": obj.get("sampled_sparse_pcrc"),
                    "sampled_entry_count": obj.get("sampled_entry_count"),
                    "sampled_used_count": obj.get("sampled_used_count"),
                    "runtime_ready": obj.get("runtime_ready", False),
                    "runtime_proxy_candidates": obj.get("runtime_proxy_candidates", []),
                    "runtime_proxy_count": obj.get("runtime_proxy_count", 0),
                    "runtime_proxy_unique": obj.get("runtime_proxy_unique", False),
                    "runtime_proxy_identity_mismatch": obj.get("runtime_proxy_identity_mismatch", False),
                    "pack_exact_entry_hit": obj.get("pack_exact_entry_hit"),
                    "pack_exact_sparse_hit": obj.get("pack_exact_sparse_hit"),
                    "pack_family_available": obj.get("pack_family_available"),
                    "unique_replacement_dims": obj.get("unique_replacement_dims"),
                    "sample_replacement_dims": obj.get("sample_replacement_dims"),
                    "linked_policy_keys": [],
                    "linked_replacement_ids": [],
                    "transport_candidates": [],
                    "upload_low32s": [],
                    "upload_pcrcs": [],
                },
            )
            if policy_key and policy_key not in record["linked_policy_keys"]:
                record["linked_policy_keys"].append(policy_key)
            for replacement_id in family.get("candidate_replacement_ids", []):
                if replacement_id not in record["linked_replacement_ids"]:
                    record["linked_replacement_ids"].append(replacement_id)
                if not any(candidate.get("replacement_id") == replacement_id for candidate in record["transport_candidates"]):
                    record["transport_candidates"].append(make_transport_candidate(replacement_id))
            for upload in obj.get("upload_low32s", []):
                if upload not in record["upload_low32s"]:
                    record["upload_low32s"].append(upload)
            for upload in obj.get("upload_pcrcs", []):
                if upload not in record["upload_pcrcs"]:
                    record["upload_pcrcs"].append(upload)

    for family in exact_authorities:
        ingest_family(family, "exact-authority")
    for family in compatibility_aliases:
        ingest_family(family, "compatibility")
    for family in unresolved_families:
        ingest_family(family, "unresolved")

    legacy_transport_aliases.sort(key=lambda item: item["policy_key"] or "")
    for record in canonical_records.values():
        record["transport_candidates"].sort(key=lambda item: item.get("replacement_id") or "")
    return {
        "canonical_records": sorted(canonical_records.values(), key=lambda item: item["sampled_object_id"]),
        "legacy_transport_aliases": legacy_transport_aliases,
    }


def build_imported_index(entries, requested_pairs, source_cache_path, bundle_context=None, bundle_sampled_context=None, import_policy=None):
    records = []
    exact_authorities = []
    compatibility_aliases = []
    unresolved_families = []
    bundle_context = bundle_context or {}
    bundle_sampled_context = bundle_sampled_context or {}
    import_policy = import_policy or {"families": {}}
    indexed_entries = index_entries_by_texture_crc(entries)
    cache_bytes = source_cache_path.read_bytes() if source_cache_path.suffix.lower() == ".hts" else None
    decoded_rgba_cache = {}

    def fallback_sampled_candidates(texture_crc, requested_formatsize):
        sampled_candidates = list(bundle_sampled_context.get((texture_crc, requested_formatsize), []))
        if sampled_candidates or requested_formatsize != 0:
            return sampled_candidates

        seen = {
            candidate.get("sampled_object_id")
            for candidate in sampled_candidates
            if candidate.get("sampled_object_id")
        }
        for (candidate_low32, _candidate_formatsize), candidate_list in bundle_sampled_context.items():
            if int(candidate_low32) != int(texture_crc):
                continue
            for candidate in candidate_list:
                sampled_object_id = candidate.get("sampled_object_id")
                if sampled_object_id and sampled_object_id in seen:
                    continue
                sampled_candidates.append(candidate)
                if sampled_object_id:
                    seen.add(sampled_object_id)
        return sampled_candidates

    for texture_crc, formatsize in requested_pairs:
        family_summary = build_family_summary(indexed_entries, texture_crc, formatsize)
        family_entries = collect_family_entries(indexed_entries, texture_crc)
        observation = bundle_context.get((texture_crc, formatsize))
        sampled_candidates = fallback_sampled_candidates(texture_crc, formatsize)
        family_policy_key = make_family_policy_key(texture_crc, formatsize)
        family_policy = import_policy["families"].get(family_policy_key)
        active_entries = [
            entry for entry in family_entries
            if entry["formatsize"] == formatsize
        ]
        if not active_entries:
            active_entries = [
                entry for entry in family_entries
                if entry["formatsize"] == 0
            ]

        replacement_ids = []
        variant_groups = {}
        variant_group_entries = {}
        for entry in active_entries:
            replacement_id = make_replacement_id(
                entry["texture_crc"],
                entry["palette_crc"],
                entry["formatsize"],
                entry["width"],
                entry["height"],
            )
            variant_group_id = make_variant_group_id(
                entry["texture_crc"],
                formatsize,
                entry["width"],
                entry["height"],
            )
            replacement_ids.append(replacement_id)
            variant_group_entries.setdefault(variant_group_id, []).append((replacement_id, entry))
            group = variant_groups.setdefault(
                variant_group_id,
                {
                    "variant_group_id": variant_group_id,
                    "dims": f"{entry['width']}x{entry['height']}",
                    "requested_formatsize": formatsize,
                    "active_pool": family_summary["active_pool"],
                    "candidate_replacement_ids": [],
                    "legacy_palette_crcs": [],
                },
            )
            group["candidate_replacement_ids"].append(replacement_id)
            group["legacy_palette_crcs"].append(f"{entry['palette_crc']:08x}")
            records.append(
                {
                    "replacement_id": replacement_id,
                    "source": {
                        "legacy_checksum64": f"{entry['checksum64']:016x}",
                        "legacy_texture_crc": f"{entry['texture_crc']:08x}",
                        "legacy_palette_crc": f"{entry['palette_crc']:08x}",
                        "legacy_formatsize": entry["formatsize"],
                        "legacy_storage": entry["storage"],
                        "legacy_source_path": entry["source_path"],
                    },
                    "match": {
                        "exact_legacy_checksum64": f"{entry['checksum64']:016x}",
                        "texture_crc": f"{entry['texture_crc']:08x}",
                        "palette_crc": f"{entry['palette_crc']:08x}",
                        "formatsize": entry["formatsize"],
                    },
                    "replacement_asset": {
                        "width": entry["width"],
                        "height": entry["height"],
                        "format": entry["format"],
                        "texture_format": entry["texture_format"],
                        "pixel_type": entry["pixel_type"],
                        "data_size": entry["data_size"],
                        "is_hires": entry["is_hires"],
                    },
                    "diagnostics": {
                        "family_low32": f"{texture_crc:08x}",
                        "requested_formatsize": formatsize,
                        "family_tier": family_summary["recommended_tier"],
                        "active_pool": family_summary["active_pool"],
                        "variant_group_id": variant_group_id,
                        "canonical_sampled_objects": sampled_candidates,
                    },
                }
            )

        variant_group_list = [
            {
                **group,
                "legacy_palette_crcs": sorted(group["legacy_palette_crcs"]),
            }
            for group in sorted(variant_groups.values(), key=lambda item: item["variant_group_id"])
        ]
        scale_equivalent_selection = None
        if family_summary["recommended_tier"] == "exact-authoritative" and len(variant_group_list) == 2:
            scale_equivalent_selection = build_exact_scale_equivalent_selection(
                texture_crc,
                formatsize,
                variant_group_list,
                variant_group_entries,
                source_cache_path,
                cache_bytes,
                decoded_rgba_cache,
            )
        selector_policy = build_selector_policy(
            texture_crc,
            formatsize,
            observation,
            variant_group_list,
            family_summary["recommended_tier"],
            selection_override=scale_equivalent_selection,
        )
        if family_policy:
            selector_policy["applied_policy"] = family_policy
        selected_replacement_ids = replacement_ids
        if scale_equivalent_selection:
            selected_replacement_ids = list(scale_equivalent_selection["selected_replacement_ids"])

        if family_summary["recommended_tier"] == "exact-authoritative" and selector_policy.get("status") == "deterministic":
            exact_authorities.append(
                {
                    "alias_id": family_policy_key,
                    "kind": "exact-authoritative",
                    "match": {
                        "texture_crc": f"{texture_crc:08x}",
                        "formatsize": formatsize,
                        "active_pool": family_summary["active_pool"],
                    },
                    "resolution_policy": {
                        "rule": "exact-authoritative",
                        "uniform_replacement_dims": family_summary["active_unique_repl_dim_count"] == 1,
                    },
                    "policy_key": family_policy_key,
                    "observed_runtime_context": observation,
                    "canonical_sampled_objects": sampled_candidates,
                    "selector_policy": selector_policy,
                    "candidate_replacement_ids": selected_replacement_ids,
                    "candidate_variant_group_ids": list(selector_policy.get("candidate_variant_group_ids") or []),
                    "diagnostics": {
                        "active_unique_palette_count": family_summary["active_unique_palette_count"],
                        "active_unique_repl_dim_count": family_summary["active_unique_repl_dim_count"],
                        "active_replacement_dims": family_summary["active_replacement_dims"],
                        "variant_groups": variant_group_list,
                        "scale_equivalent_selection": scale_equivalent_selection,
                    },
                }
            )
        elif family_summary["recommended_tier"] in ("compat-unique", "compat-repl-dims-unique"):
            compatibility_aliases.append(
                {
                    "alias_id": family_policy_key,
                    "kind": family_summary["recommended_tier"],
                    "match": {
                        "texture_crc": f"{texture_crc:08x}",
                        "formatsize": formatsize,
                        "active_pool": family_summary["active_pool"],
                    },
                    "resolution_policy": {
                        "rule": family_summary["recommended_tier"],
                        "uniform_replacement_dims": family_summary["active_unique_repl_dim_count"] == 1,
                    },
                    "policy_key": family_policy_key,
                    "observed_runtime_context": observation,
                    "canonical_sampled_objects": sampled_candidates,
                    "selector_policy": selector_policy,
                    "candidate_replacement_ids": replacement_ids,
                    "candidate_variant_group_ids": [group["variant_group_id"] for group in variant_group_list],
                    "diagnostics": {
                        "active_unique_palette_count": family_summary["active_unique_palette_count"],
                        "active_unique_repl_dim_count": family_summary["active_unique_repl_dim_count"],
                        "active_replacement_dims": family_summary["active_replacement_dims"],
                        "variant_groups": variant_group_list,
                    },
                }
            )
        elif family_summary["recommended_tier"] in ("ambiguous-import-or-policy", "missing-active-pool", "exact-authoritative"):
            unresolved_families.append(
                {
                    "policy_key": family_policy_key,
                    "family_low32": f"{texture_crc:08x}",
                    "formatsize": formatsize,
                    "reason": (
                        "legacy-family-ambiguous"
                        if family_summary["recommended_tier"] == "ambiguous-import-or-policy"
                        else "exact-family-ambiguous"
                        if family_summary["recommended_tier"] == "exact-authoritative"
                        else "missing-active-pool"
                    ),
                    "active_pool": family_summary["active_pool"],
                    "active_unique_palette_count": family_summary["active_unique_palette_count"],
                    "active_unique_repl_dim_count": family_summary["active_unique_repl_dim_count"],
                    "active_replacement_dims": family_summary["active_replacement_dims"],
                    "observed_runtime_context": observation,
                    "canonical_sampled_objects": sampled_candidates,
                    "selector_policy": selector_policy,
                    "candidate_replacement_ids": replacement_ids,
                    "variant_groups": variant_group_list,
                }
            )

    record_index = {record["replacement_id"]: record for record in records}
    transport = build_canonical_transport(exact_authorities, compatibility_aliases, unresolved_families, record_index)

    return {
        "schema_version": 1,
        "source": {
            "legacy_cache_path": str(source_cache_path),
            "legacy_entry_count": len(entries),
        },
        "policy_source": {
            "path": import_policy.get("source_path"),
            "schema_version": import_policy.get("schema_version"),
        } if import_policy.get("source_path") else None,
        "records": records,
        "exact_authorities": exact_authorities,
        "compatibility_aliases": compatibility_aliases,
        "unresolved_families": unresolved_families,
        "canonical_records": transport["canonical_records"],
        "legacy_transport_aliases": transport["legacy_transport_aliases"],
    }


def main():
    parser = argparse.ArgumentParser(description="Build a migration-oriented plan from a legacy hi-res pack.")
    parser.add_argument("--cache", required=True, help="Path to .hts or .htc pack.")
    parser.add_argument("--bundle", help="Optional strict bundle path; imports low32/fs pairs from ci_palette_probe.families.")
    parser.add_argument("--low32", action="append", default=[], help="Low32 texture CRC in hex.")
    parser.add_argument("--formatsize", action="append", type=int, default=[], help="Formatsize values paired with --low32 in order.")
    parser.add_argument("--emit-import-index", action="store_true", help="Emit the first imported-index format instead of only the migration plan.")
    parser.add_argument("--policy", help="Optional import policy JSON to attach to selector output.")
    parser.add_argument("--output", help="Optional output JSON path.")
    args = parser.parse_args()

    cache_path = Path(args.cache)
    entries = parse_cache_entries(cache_path)
    bundle_context = {}
    bundle_sampled_context = {}
    import_policy = {"families": {}}
    if args.policy:
        import_policy = load_import_policy(args.policy)

    requested_pairs = []
    if args.bundle:
        bundle_path = Path(args.bundle)
        requested_pairs.extend(parse_bundle_families(bundle_path))
        bundle_context = parse_bundle_ci_context(bundle_path)
        bundle_sampled_context = parse_bundle_sampled_object_context(bundle_path)

    if args.low32:
        formatsizes = args.formatsize or []
        if formatsizes and len(formatsizes) != len(args.low32):
            raise SystemExit("--formatsize must either be omitted or match the number of --low32 arguments.")
        for index, low32 in enumerate(args.low32):
            formatsize = formatsizes[index] if formatsizes else 0
            requested_pairs.append((int(low32, 16), formatsize))

    if not requested_pairs:
        raise SystemExit("No families requested. Use --bundle and/or --low32.")

    deduped_pairs = []
    seen = set()
    for pair in requested_pairs:
        if pair in seen:
            continue
        seen.add(pair)
        deduped_pairs.append(pair)

    result = {
        "cache_path": str(cache_path),
        "entry_count": len(entries),
        "requested_family_count": len(deduped_pairs),
        "plan": build_migration_plan(entries, deduped_pairs),
    }
    if args.emit_import_index:
        result["imported_index"] = build_imported_index(entries, deduped_pairs, cache_path, bundle_context, bundle_sampled_context, import_policy)

    serialized = json.dumps(result, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(serialized)
    else:
        sys.stdout.write(serialized)


if __name__ == "__main__":
    main()
