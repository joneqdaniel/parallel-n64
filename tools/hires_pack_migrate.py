#!/usr/bin/env python3
import argparse
import json
import sys
from collections import Counter
from pathlib import Path

from hires_pack_common import (
    build_family_summary,
    collect_family_entries,
    parse_bundle_ci_context,
    parse_bundle_families,
    parse_bundle_sampled_object_context,
    parse_cache_entries,
)


def build_migration_plan(entries, requested_pairs):
    families = [build_family_summary(entries, texture_crc, formatsize) for texture_crc, formatsize in requested_pairs]
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


def build_selector_policy(texture_crc, formatsize, observation, variant_group_list, tier):
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

    policy = {
        "status": "deterministic" if tier in ("compat-unique", "compat-repl-dims-unique") else "manual-disambiguation-required",
        "selector_basis": base_selector,
        "candidate_variant_group_ids": [group["variant_group_id"] for group in variant_group_list],
        "disambiguation_inputs": disambiguation_inputs,
    }

    if tier in ("compat-unique", "compat-repl-dims-unique") and len(variant_group_list) == 1:
        policy["selected_variant_group_id"] = variant_group_list[0]["variant_group_id"]
        policy["selection_reason"] = tier
    else:
        policy["selection_reason"] = "legacy-family-ambiguous"

    return policy


def build_imported_index(entries, requested_pairs, source_cache_path, bundle_context=None, bundle_sampled_context=None, import_policy=None):
    records = []
    compatibility_aliases = []
    unresolved_families = []
    bundle_context = bundle_context or {}
    bundle_sampled_context = bundle_sampled_context or {}
    import_policy = import_policy or {"families": {}}

    for texture_crc, formatsize in requested_pairs:
        family_summary = build_family_summary(entries, texture_crc, formatsize)
        family_entries = collect_family_entries(entries, texture_crc)
        observation = bundle_context.get((texture_crc, formatsize))
        sampled_candidates = bundle_sampled_context.get((texture_crc, formatsize), [])
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
        selector_policy = build_selector_policy(
            texture_crc,
            formatsize,
            observation,
            variant_group_list,
            family_summary["recommended_tier"],
        )
        if family_policy:
            selector_policy["applied_policy"] = family_policy

        if family_summary["recommended_tier"] in ("compat-unique", "compat-repl-dims-unique"):
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
        elif family_summary["recommended_tier"] in ("ambiguous-import-or-policy", "missing-active-pool"):
            unresolved_families.append(
                {
                    "policy_key": family_policy_key,
                    "family_low32": f"{texture_crc:08x}",
                    "formatsize": formatsize,
                    "reason": (
                        "legacy-family-ambiguous"
                        if family_summary["recommended_tier"] == "ambiguous-import-or-policy"
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
        "compatibility_aliases": compatibility_aliases,
        "unresolved_families": unresolved_families,
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
