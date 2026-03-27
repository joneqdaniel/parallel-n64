#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path


def load_subset(path: Path):
    data = json.loads(path.read_text())
    imported_subset = data.get("imported_subset") or {}
    projection = data.get("canonical_projection") or {}
    canonical_records = projection.get("canonical_records") or imported_subset.get("canonical_records") or []
    legacy_links = projection.get("legacy_links") or imported_subset.get("legacy_transport_aliases") or []
    return data, canonical_records, legacy_links


def build_bindings(subset_path: Path, data, canonical_records, legacy_links):
    canonical_index = {record.get("sampled_object_id"): record for record in canonical_records}
    bindings = []
    unresolved = []

    for link in legacy_links:
        sampled_ids = link.get("canonical_sampled_object_ids") or []
        candidate_ids = set(link.get("candidate_replacement_ids") or [])
        status = link.get("status")
        if status == "deterministic" and len(sampled_ids) == 1:
            sampled_object_id = sampled_ids[0]
            record = canonical_index.get(sampled_object_id)
            if not record:
                unresolved.append(
                    {
                        "policy_key": link.get("policy_key"),
                        "family_type": link.get("family_type"),
                        "reason": "missing-canonical-record",
                        "status": status,
                        "canonical_sampled_object_ids": sampled_ids,
                        "candidate_replacement_ids": list(candidate_ids),
                    }
                )
                continue
            candidates = [
                candidate
                for candidate in record.get("transport_candidates", [])
                if not candidate_ids or candidate.get("replacement_id") in candidate_ids
            ]
            bindings.append(
                {
                    "policy_key": link.get("policy_key"),
                    "family_type": link.get("family_type"),
                    "status": status,
                    "selection_reason": link.get("selection_reason"),
                    "sampled_object_id": sampled_object_id,
                    "canonical_identity": {
                        "draw_class": record.get("draw_class"),
                        "cycle": record.get("cycle"),
                        "fmt": record.get("fmt"),
                        "siz": record.get("siz"),
                        "off": record.get("off"),
                        "stride": record.get("stride"),
                        "wh": record.get("wh"),
                        "formatsize": record.get("formatsize"),
                        "sampled_low32": record.get("sampled_low32"),
                        "sampled_entry_pcrc": record.get("sampled_entry_pcrc"),
                        "sampled_sparse_pcrc": record.get("sampled_sparse_pcrc"),
                    },
                    "transport_candidates": candidates,
                    "upload_low32s": record.get("upload_low32s", []),
                    "upload_pcrcs": record.get("upload_pcrcs", []),
                }
            )
        else:
            unresolved.append(
                {
                    "policy_key": link.get("policy_key"),
                    "family_type": link.get("family_type"),
                    "reason": link.get("reason") or "manual-disambiguation-required",
                    "status": status,
                    "selection_reason": link.get("selection_reason"),
                    "canonical_sampled_object_ids": sampled_ids,
                    "candidate_replacement_ids": list(candidate_ids),
                }
            )

    bindings.sort(key=lambda item: item.get("policy_key") or "")
    unresolved.sort(key=lambda item: item.get("policy_key") or "")
    return {
        "schema_version": 1,
        "source_subset_path": str(subset_path),
        "bundle_path": data.get("bundle_path"),
        "binding_count": len(bindings),
        "unresolved_count": len(unresolved),
        "bindings": bindings,
        "unresolved_transport_cases": unresolved,
    }


def main():
    parser = argparse.ArgumentParser(description="Emit deterministic canonical hi-res bindings from an imported subset.")
    parser.add_argument("--subset", required=True, help="Path to emitted subset JSON.")
    parser.add_argument("--output", help="Optional output JSON path.")
    args = parser.parse_args()

    subset_path = Path(args.subset)
    data, canonical_records, legacy_links = load_subset(subset_path)
    result = build_bindings(subset_path, data, canonical_records, legacy_links)
    serialized = json.dumps(result, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(serialized)
    else:
        sys.stdout.write(serialized)


if __name__ == "__main__":
    main()
