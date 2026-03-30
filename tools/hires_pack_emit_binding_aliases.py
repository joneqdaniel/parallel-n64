#!/usr/bin/env python3
import argparse
import copy
import json
import sys
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text())


def clone_transport_candidates(selected_candidates, selector_checksum64s, include_zero_selector):
    emitted = []
    if include_zero_selector:
        emitted.extend(copy.deepcopy(selected_candidates))
    for selector_checksum64 in selector_checksum64s:
        for candidate in selected_candidates:
            cloned = copy.deepcopy(candidate)
            cloned["selector_checksum64"] = selector_checksum64
            variant_group_id = cloned.get("variant_group_id") or "selector-alias"
            cloned["variant_group_id"] = f"{variant_group_id}-sel-{selector_checksum64}"
            emitted.append(cloned)
    return emitted


def build_aliases(bindings_data, policy_data):
    proxy_policy = policy_data.get("transport_proxies", {}) if policy_data else {}
    alias_bindings = []
    for binding in bindings_data.get("bindings", []):
        policy_record = proxy_policy.get(binding.get("policy_key"))
        if not policy_record:
            continue
        selected_replacement_id = policy_record.get("selected_replacement_id")
        if not selected_replacement_id:
            continue
        selected = [candidate for candidate in binding.get("transport_candidates", []) if candidate.get("replacement_id") == selected_replacement_id]
        if len(selected) != 1:
            continue
        for alias_record in policy_record.get("sampled_alias_records", []):
            alias_entry_pcrc = alias_record.get("sampled_entry_pcrc")
            if not alias_entry_pcrc:
                continue
            alias_sparse_pcrc = alias_record.get("sampled_sparse_pcrc", alias_entry_pcrc)
            alias_suffix = alias_record.get("alias_suffix") or alias_entry_pcrc
            alias_policy_key = f"{binding['policy_key']}#alias-{alias_suffix}"
            alias_binding = copy.deepcopy(binding)
            alias_binding["policy_key"] = alias_policy_key
            alias_binding["family_type"] = "binding-selector-alias"
            alias_binding["sampled_object_id"] = alias_policy_key
            alias_binding["status"] = alias_record.get("status") or "selected-alias"
            alias_binding["selection_reason"] = alias_record.get("justification") or "binding-selector-alias"
            alias_binding["canonical_identity"]["candidate_origin"] = "runtime-binding-alias"
            alias_binding["canonical_identity"]["sampled_entry_pcrc"] = alias_entry_pcrc
            alias_binding["canonical_identity"]["sampled_sparse_pcrc"] = alias_sparse_pcrc
            alias_binding["transport_candidates"] = clone_transport_candidates(
                selected,
                alias_record.get("selector_checksum64s", []),
                alias_record.get("include_zero_selector", True),
            )
            alias_binding["transport_policy"] = {
                "base_proxy_id": binding["policy_key"],
                "selected_replacement_id": selected_replacement_id,
                **alias_record,
            }
            alias_bindings.append(alias_binding)
    return {
        "schema_version": 1,
        "source_input_path": str(bindings_data.get("source_input_paths") or bindings_data.get("source_input_path") or "bindings"),
        "binding_count": len(alias_bindings),
        "unresolved_count": 0,
        "bindings": sorted(alias_bindings, key=lambda item: item.get("policy_key") or ""),
        "unresolved_transport_cases": [],
    }


def main():
    parser = argparse.ArgumentParser(description="Emit selector/palette alias bindings from an existing selected binding set and transport policy.")
    parser.add_argument("--bindings", required=True, help="Path to an existing bindings.json payload.")
    parser.add_argument("--policy", required=True, help="Transport policy JSON path.")
    parser.add_argument("--output", help="Optional output JSON path.")
    args = parser.parse_args()

    result = build_aliases(load_json(Path(args.bindings)), load_json(Path(args.policy)))
    serialized = json.dumps(result, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(serialized)
    else:
        sys.stdout.write(serialized)


if __name__ == "__main__":
    main()
