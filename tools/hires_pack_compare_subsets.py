#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path


def load_subset(path):
    data = json.loads(Path(path).read_text())
    subset = data["imported_subset"]
    unresolved = subset.get("unresolved_families", [])
    family = unresolved[0] if unresolved else None
    records = subset.get("records", [])
    total_data_size = sum(record.get("replacement_asset", {}).get("data_size", 0) for record in records)
    variant_groups = family.get("variant_groups", []) if family else []
    selector_policy = family.get("selector_policy", {}) if family else {}
    return {
        "path": str(path),
        "policy_key": family.get("policy_key") if family else None,
        "proposed_variant_group_id": selector_policy.get("proposed_selected_variant_group_id"),
        "record_count": len(records),
        "total_data_size": total_data_size,
        "variant_group_count": len(variant_groups),
        "variant_group_dims": [group.get("dims") for group in variant_groups],
        "candidate_replacement_id_count": len(family.get("candidate_replacement_ids", [])) if family else 0,
        "runtime_context": family.get("observed_runtime_context") if family else None,
    }


def format_markdown(entries):
    lines = []
    lines.append("# Hi-Res Imported Subset Comparison")
    lines.append("")
    lines.append("| File | Policy Key | Proposed Variant Group | Records | Total Data Size | Variant Group Count | Dims |")
    lines.append("| --- | --- | --- | ---: | ---: | ---: | --- |")
    for entry in entries:
        lines.append(
            f"| `{Path(entry['path']).name}` | `{entry['policy_key']}` | `{entry['proposed_variant_group_id']}` | `{entry['record_count']}` | `{entry['total_data_size']}` | `{entry['variant_group_count']}` | `{', '.join(entry['variant_group_dims'])}` |"
        )

    if entries:
        lines.append("")
        lines.append("## Shared Runtime Context")
        lines.append("")
        runtime = entries[0].get("runtime_context") or {}
        lines.append(f"- mode: `{runtime.get('mode')}`")
        lines.append(f"- runtime_wh: `{runtime.get('runtime_wh')}`")
        lines.append(f"- observed_runtime_pcrc: `{runtime.get('observed_runtime_pcrc')}`")
        lines.append(f"- sample_replacement_dims: `{runtime.get('sample_replacement_dims')}`")

    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Compare review-only imported subset artifacts.")
    parser.add_argument("paths", nargs="+", help="Subset JSON paths.")
    parser.add_argument("--format", choices=("json", "markdown"), default="markdown")
    parser.add_argument("--output", help="Optional output path.")
    args = parser.parse_args()

    entries = [load_subset(path) for path in args.paths]
    if args.format == "json":
        serialized = json.dumps(entries, indent=2) + "\n"
    else:
        serialized = format_markdown(entries)

    if args.output:
        Path(args.output).write_text(serialized)
    else:
        sys.stdout.write(serialized)


if __name__ == "__main__":
    main()
