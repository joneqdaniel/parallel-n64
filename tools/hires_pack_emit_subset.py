#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

from hires_pack_common import parse_cache_entries, parse_bundle_ci_context, parse_bundle_families, parse_bundle_sampled_object_context
from hires_pack_migrate import build_imported_index, load_import_policy


def parse_variant_selections(selection_args):
    selections = {}
    for raw in selection_args:
        if "=" not in raw:
            raise SystemExit(f"Invalid --variant-selection value: {raw}")
        policy_key, variant_group_id = raw.split("=", 1)
        selections[policy_key] = variant_group_id
    return selections


def apply_variant_selection(entry, variant_group_id):
    variant_groups = entry.get("variant_groups") or entry.get("diagnostics", {}).get("variant_groups", [])
    selected_groups = [group for group in variant_groups if group.get("variant_group_id") == variant_group_id]
    if not selected_groups:
        return entry, set()

    selected_group = selected_groups[0]
    selected_ids = set(selected_group.get("candidate_replacement_ids", []))
    cloned = json.loads(json.dumps(entry))
    cloned["variant_groups"] = [selected_group]
    cloned["candidate_replacement_ids"] = [
        replacement_id for replacement_id in cloned.get("candidate_replacement_ids", [])
        if replacement_id in selected_ids
    ]
    selector_policy = cloned.get("selector_policy") or {}
    selector_policy["proposed_selected_variant_group_id"] = variant_group_id
    selector_policy["proposed_selection_reason"] = "review-subset-override"
    cloned["selector_policy"] = selector_policy
    return cloned, selected_ids


def filter_imported_index(imported_index, policy_keys, variant_selections=None):
    if not policy_keys:
        return imported_index

    variant_selections = variant_selections or {}
    wanted = set(policy_keys)
    compatibility = [
        entry for entry in imported_index.get("compatibility_aliases", [])
        if entry.get("policy_key") in wanted or entry.get("alias_id") in wanted
    ]
    unresolved = []
    selected_candidate_ids = set()
    for entry in imported_index.get("unresolved_families", []):
        policy_key = entry.get("policy_key")
        if policy_key not in wanted:
            continue
        if policy_key in variant_selections:
            filtered_entry, selected_ids = apply_variant_selection(entry, variant_selections[policy_key])
            unresolved.append(filtered_entry)
            selected_candidate_ids.update(selected_ids)
        else:
            unresolved.append(entry)

    candidate_ids = set()
    for entry in compatibility:
        candidate_ids.update(entry.get("candidate_replacement_ids", []))
    for entry in unresolved:
        candidate_ids.update(entry.get("candidate_replacement_ids", []))
    candidate_ids.update(selected_candidate_ids)

    records = [
        record for record in imported_index.get("records", [])
        if record.get("replacement_id") in candidate_ids
    ]

    return {
        "schema_version": imported_index.get("schema_version"),
        "source": imported_index.get("source"),
        "policy_source": imported_index.get("policy_source"),
        "variant_selections": variant_selections,
        "records": records,
        "compatibility_aliases": compatibility,
        "unresolved_families": unresolved,
    }


def collect_requested_pairs(bundle_path, low32_args, formatsize_args):
    requested_pairs = list(parse_bundle_families(bundle_path))
    if low32_args:
        formatsizes = formatsize_args or []
        if formatsizes and len(formatsizes) != len(low32_args):
            raise SystemExit("--formatsize must either be omitted or match the number of --low32 arguments.")
        for index, low32 in enumerate(low32_args):
            formatsize = formatsizes[index] if formatsizes else 0
            requested_pairs.append((int(low32, 16), formatsize))

    deduped_pairs = []
    seen = set()
    for pair in requested_pairs:
        if pair in seen:
            continue
        seen.add(pair)
        deduped_pairs.append(pair)
    return deduped_pairs


def main():
    parser = argparse.ArgumentParser(description="Emit a tiny imported hi-res subset for selected strict families.")
    parser.add_argument("--cache", required=True, help="Path to .hts or .htc pack.")
    parser.add_argument("--bundle", required=True, help="Strict bundle path.")
    parser.add_argument("--policy", help="Optional import policy JSON.")
    parser.add_argument("--low32", action="append", default=[], help="Optional low32 texture CRC in hex for explicit review/subset seeds.")
    parser.add_argument("--formatsize", action="append", type=int, default=[], help="Formatsize values paired with --low32 in order.")
    parser.add_argument("--policy-key", action="append", default=[], help="Optional policy key(s) to keep in the emitted subset.")
    parser.add_argument("--variant-selection", action="append", default=[], help="Optional policy_key=variant_group_id override for review-only subset emission.")
    parser.add_argument("--output", help="Optional output JSON path.")
    args = parser.parse_args()

    cache_path = Path(args.cache)
    bundle_path = Path(args.bundle)
    entries = parse_cache_entries(cache_path)
    requested_pairs = collect_requested_pairs(bundle_path, args.low32, args.formatsize)
    bundle_context = parse_bundle_ci_context(bundle_path)
    bundle_sampled_context = parse_bundle_sampled_object_context(bundle_path)

    import_policy = {"families": {}}
    if args.policy:
        import_policy = load_import_policy(args.policy)

    imported_index = build_imported_index(
        entries,
        requested_pairs,
        cache_path,
        bundle_context=bundle_context,
        bundle_sampled_context=bundle_sampled_context,
        import_policy=import_policy,
    )
    subset = filter_imported_index(
        imported_index,
        args.policy_key,
        parse_variant_selections(args.variant_selection),
    )

    result = {
        "bundle_path": str(bundle_path),
        "requested_policy_keys": args.policy_key,
        "requested_variant_selections": args.variant_selection,
        "imported_subset": subset,
    }

    serialized = json.dumps(result, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(serialized)
    else:
        sys.stdout.write(serialized)


if __name__ == "__main__":
    main()
