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

    canonical_ids = set()
    transport_aliases = []
    for entry in compatibility + unresolved:
        transport_key = entry.get("policy_key") or entry.get("alias_id")
        for alias in imported_index.get("legacy_transport_aliases", []):
            if alias.get("policy_key") == transport_key:
                transport_aliases.append(alias)
                canonical_ids.update(alias.get("canonical_sampled_object_ids", []))
                break

    canonical_records = [
        record for record in imported_index.get("canonical_records", [])
        if record.get("sampled_object_id") in canonical_ids
    ]

    return {
        "schema_version": imported_index.get("schema_version"),
        "source": imported_index.get("source"),
        "policy_source": imported_index.get("policy_source"),
        "variant_selections": variant_selections,
        "records": records,
        "compatibility_aliases": compatibility,
        "unresolved_families": unresolved,
        "canonical_records": canonical_records,
        "legacy_transport_aliases": transport_aliases,
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


def build_canonical_projection(imported_subset):
    canonical_records = imported_subset.get("canonical_records")
    legacy_links = imported_subset.get("legacy_transport_aliases")
    if canonical_records is not None and legacy_links is not None:
        canonical_list = sorted(canonical_records, key=lambda item: item["sampled_object_id"])
        link_list = sorted(legacy_links, key=lambda item: item["policy_key"] or "")
        return {
            "canonical_record_count": len(canonical_list),
            "legacy_link_count": len(link_list),
            "canonical_records": canonical_list,
            "legacy_links": link_list,
        }

    canonical_records = {}
    legacy_links = []

    def ingest_family(family, family_type):
        policy_key = family.get("policy_key") or family.get("alias_id")
        canonical_objects = family.get("canonical_sampled_objects") or []
        link = {
            "family_type": family_type,
            "policy_key": policy_key,
            "reason": family.get("reason"),
            "kind": family.get("kind"),
            "status": (family.get("selector_policy") or {}).get("status"),
            "selection_reason": (family.get("selector_policy") or {}).get("selection_reason"),
            "candidate_replacement_ids": family.get("candidate_replacement_ids", []),
            "canonical_sampled_object_ids": [obj.get("sampled_object_id") for obj in canonical_objects],
        }
        legacy_links.append(link)
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
                    "pack_exact_entry_hit": obj.get("pack_exact_entry_hit"),
                    "pack_exact_sparse_hit": obj.get("pack_exact_sparse_hit"),
                    "pack_family_available": obj.get("pack_family_available"),
                    "linked_policy_keys": [],
                    "linked_replacement_ids": [],
                    "upload_low32s": [],
                    "upload_pcrcs": [],
                },
            )
            if policy_key and policy_key not in record["linked_policy_keys"]:
                record["linked_policy_keys"].append(policy_key)
            for replacement_id in family.get("candidate_replacement_ids", []):
                if replacement_id not in record["linked_replacement_ids"]:
                    record["linked_replacement_ids"].append(replacement_id)
            for upload in obj.get("upload_low32s", []):
                if upload not in record["upload_low32s"]:
                    record["upload_low32s"].append(upload)
            for upload in obj.get("upload_pcrcs", []):
                if upload not in record["upload_pcrcs"]:
                    record["upload_pcrcs"].append(upload)

    for family in imported_subset.get("compatibility_aliases", []):
        ingest_family(family, "compatibility")
    for family in imported_subset.get("unresolved_families", []):
        ingest_family(family, "unresolved")

    canonical_list = sorted(canonical_records.values(), key=lambda item: item["sampled_object_id"])
    legacy_links.sort(key=lambda item: item["policy_key"] or "")
    return {
        "canonical_record_count": len(canonical_list),
        "legacy_link_count": len(legacy_links),
        "canonical_records": canonical_list,
        "legacy_links": legacy_links,
    }


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
        "canonical_projection": build_canonical_projection(subset),
    }

    serialized = json.dumps(result, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(serialized)
    else:
        sys.stdout.write(serialized)


if __name__ == "__main__":
    main()
