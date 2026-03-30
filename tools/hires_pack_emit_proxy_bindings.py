#!/usr/bin/env python3
import argparse
import copy
import json
import sys
from pathlib import Path

from hires_pack_proxy_review import build_proxy_view, load_index


def load_policy(path: Path | None):
    if path is None:
        return {}
    return json.loads(path.read_text())


def clone_transport_candidates(selected_candidates, selector_checksum64s, include_zero_selector):
    emitted = []
    if include_zero_selector:
        emitted.extend(copy.deepcopy(selected_candidates))
    for selector_checksum64 in selector_checksum64s:
        for candidate in selected_candidates:
            cloned = copy.deepcopy(candidate)
            cloned['selector_checksum64'] = selector_checksum64
            variant_group_id = cloned.get('variant_group_id') or 'selector-alias'
            cloned['variant_group_id'] = f'{variant_group_id}-sel-{selector_checksum64}'
            emitted.append(cloned)
    return emitted


def build_alias_bindings(base, selected_candidates, policy_record):
    aliases = []
    for alias_record in policy_record.get('sampled_alias_records', []):
        alias_entry_pcrc = alias_record.get('sampled_entry_pcrc')
        if not alias_entry_pcrc:
            continue
        alias_sparse_pcrc = alias_record.get('sampled_sparse_pcrc', alias_entry_pcrc)
        alias_suffix = alias_record.get('alias_suffix') or alias_entry_pcrc
        selector_checksum64s = alias_record.get('selector_checksum64s', [])
        include_zero_selector = alias_record.get('include_zero_selector', True)
        alias_policy_key = f"{base['policy_key']}#alias-{alias_suffix}"
        alias_binding = copy.deepcopy(base)
        alias_binding['policy_key'] = alias_policy_key
        alias_binding['family_type'] = 'proxy-selector-alias'
        alias_binding['sampled_object_id'] = alias_policy_key
        alias_binding['status'] = alias_record.get('status') or 'selected-alias'
        alias_binding['selection_reason'] = alias_record.get('justification') or 'proxy-selector-alias'
        alias_binding['canonical_identity']['candidate_origin'] = 'runtime-sampled-probe-alias'
        alias_binding['canonical_identity']['sampled_entry_pcrc'] = alias_entry_pcrc
        alias_binding['canonical_identity']['sampled_sparse_pcrc'] = alias_sparse_pcrc
        alias_binding['transport_candidates'] = clone_transport_candidates(
            selected_candidates,
            selector_checksum64s,
            include_zero_selector,
        )
        alias_binding['transport_policy'] = {
            'base_proxy_id': base['policy_key'],
            'selected_replacement_id': policy_record.get('selected_replacement_id'),
            **alias_record,
        }
        aliases.append(alias_binding)
    return aliases


def build_proxy_bindings(input_path: Path, policy_data: dict):
    review = build_proxy_view(load_index(input_path))
    proxy_policy = policy_data.get("transport_proxies", {}) if policy_data else {}

    bindings = []
    unresolved = []

    for group in review.get("proxy_groups", []):
        proxy = group.get("proxy_identity", {})
        proxy_id = group.get("proxy_sampled_object_id")
        policy_record = proxy_policy.get(proxy_id, {})
        selected_replacement_id = policy_record.get("selected_replacement_id")
        candidates = list(group.get("transport_candidates", []))
        base = {
            "policy_key": proxy_id,
            "family_type": "proxy-transport",
            "sampled_object_id": proxy_id,
            "canonical_identity": {
                "candidate_origin": proxy.get("candidate_origin"),
                "evidence_authority": proxy.get("evidence_authority"),
                "draw_class": proxy.get("draw_class"),
                "cycle": proxy.get("cycle"),
                "fmt": proxy.get("fmt"),
                "siz": proxy.get("siz"),
                "off": proxy.get("off"),
                "stride": proxy.get("stride"),
                "wh": proxy.get("wh"),
                "formatsize": proxy.get("formatsize"),
                "sampled_low32": proxy.get("sampled_low32"),
                "sampled_entry_pcrc": proxy.get("sampled_entry_pcrc"),
                "sampled_sparse_pcrc": proxy.get("sampled_sparse_pcrc"),
                "runtime_ready": proxy.get("runtime_ready", False),
            },
            "source_hint_ids": group.get("source_hint_ids", []),
            "source_hint_low32s": group.get("source_hint_low32s", []),
            "source_policy_keys": group.get("source_policy_keys", []),
            "source_policy_status_counts": group.get("source_policy_status_counts", {}),
            "transport_candidate_dims": group.get("transport_candidate_dims", []),
            "transport_candidate_count": group.get("transport_candidate_count", 0),
            "transport_candidate_palette_count": group.get("transport_candidate_palette_count", 0),
            "upload_low32s": [{"value": value} for value in group.get("source_hint_low32s", [])],
            "upload_pcrcs": [],
        }

        if selected_replacement_id:
            selected = [candidate for candidate in candidates if candidate.get("replacement_id") == selected_replacement_id]
            if len(selected) != 1:
                unresolved.append({
                    **base,
                    "status": "invalid-selection",
                    "reason": "selected-replacement-id-not-found",
                    "selected_replacement_id": selected_replacement_id,
                    "transport_candidates": candidates,
                    "transport_policy": policy_record,
                })
                continue
            bindings.append({
                **base,
                "status": policy_record.get("status") or "selected",
                "selection_reason": policy_record.get("justification") or "proxy-transport-selected",
                "transport_candidates": selected,
                "transport_policy": policy_record,
            })
            bindings.extend(build_alias_bindings(base, selected, policy_record))
        else:
            unresolved.append({
                **base,
                "status": policy_record.get("status") or "manual-review-required",
                "reason": policy_record.get("reason") or "proxy-transport-selection-required",
                "selection_reason": policy_record.get("justification"),
                "suggested_replacement_id": policy_record.get("suggested_replacement_id"),
                "transport_candidates": candidates,
                "transport_policy": policy_record,
            })

    bindings.sort(key=lambda item: item.get("policy_key") or "")
    unresolved.sort(key=lambda item: item.get("policy_key") or "")
    return {
        "schema_version": 1,
        "source_input_path": str(input_path),
        "binding_count": len(bindings),
        "unresolved_count": len(unresolved),
        "bindings": bindings,
        "unresolved_transport_cases": unresolved,
    }


def main():
    parser = argparse.ArgumentParser(description="Emit sampled-proxy-centered hi-res bindings from an imported index or subset.")
    parser.add_argument("--input", required=True, help="Path to imported_index or imported_subset JSON.")
    parser.add_argument("--policy", help="Optional transport policy JSON with transport_proxies entries.")
    parser.add_argument("--output", help="Optional output JSON path.")
    args = parser.parse_args()

    input_path = Path(args.input)
    policy_path = Path(args.policy) if args.policy else None
    result = build_proxy_bindings(input_path, load_policy(policy_path))
    serialized = json.dumps(result, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(serialized)
    else:
        sys.stdout.write(serialized)


if __name__ == "__main__":
    main()
