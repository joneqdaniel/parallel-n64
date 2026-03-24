#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

from hires_pack_common import parse_cache_entries, parse_bundle_ci_context, parse_bundle_families
from hires_pack_migrate import build_imported_index, load_import_policy


def filter_imported_index(imported_index, policy_keys):
    if not policy_keys:
        return imported_index

    wanted = set(policy_keys)
    compatibility = [
        entry for entry in imported_index.get("compatibility_aliases", [])
        if entry.get("policy_key") in wanted or entry.get("alias_id") in wanted
    ]
    unresolved = [
        entry for entry in imported_index.get("unresolved_families", [])
        if entry.get("policy_key") in wanted
    ]

    candidate_ids = set()
    for entry in compatibility:
        candidate_ids.update(entry.get("candidate_replacement_ids", []))
    for entry in unresolved:
        candidate_ids.update(entry.get("candidate_replacement_ids", []))

    records = [
        record for record in imported_index.get("records", [])
        if record.get("replacement_id") in candidate_ids
    ]

    return {
        "schema_version": imported_index.get("schema_version"),
        "source": imported_index.get("source"),
        "policy_source": imported_index.get("policy_source"),
        "records": records,
        "compatibility_aliases": compatibility,
        "unresolved_families": unresolved,
    }


def main():
    parser = argparse.ArgumentParser(description="Emit a tiny imported hi-res subset for selected strict families.")
    parser.add_argument("--cache", required=True, help="Path to .hts or .htc pack.")
    parser.add_argument("--bundle", required=True, help="Strict bundle path.")
    parser.add_argument("--policy", help="Optional import policy JSON.")
    parser.add_argument("--policy-key", action="append", default=[], help="Optional policy key(s) to keep in the emitted subset.")
    parser.add_argument("--output", help="Optional output JSON path.")
    args = parser.parse_args()

    cache_path = Path(args.cache)
    bundle_path = Path(args.bundle)
    entries = parse_cache_entries(cache_path)
    requested_pairs = parse_bundle_families(bundle_path)
    bundle_context = parse_bundle_ci_context(bundle_path)

    import_policy = {"families": {}}
    if args.policy:
        import_policy = load_import_policy(args.policy)

    imported_index = build_imported_index(
        entries,
        requested_pairs,
        cache_path,
        bundle_context=bundle_context,
        import_policy=import_policy,
    )
    subset = filter_imported_index(imported_index, args.policy_key)

    result = {
        "bundle_path": str(bundle_path),
        "requested_policy_keys": args.policy_key,
        "imported_subset": subset,
    }

    serialized = json.dumps(result, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(serialized)
    else:
        sys.stdout.write(serialized)


if __name__ == "__main__":
    main()
