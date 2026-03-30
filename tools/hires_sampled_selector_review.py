#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def load_probe(bundle: Path):
    data = json.loads((bundle / "traces" / "hires-evidence.json").read_text())
    return data.get("sampled_object_probe", {})


def bucket_fields(item):
    return item.get("fields", {})


def group_unresolved(buckets):
    grouped = {}
    for item in buckets:
        fields = bucket_fields(item)
        key = (
            fields.get("draw_class"),
            fields.get("cycle"),
            fields.get("sampled_low32"),
            fields.get("fs"),
        )
        group = grouped.setdefault(key, {
            "count": 0,
            "selectors": [],
            "palette_crcs": set(),
            "sample_detail": item.get("sample_detail"),
        })
        group["count"] += item.get("count", 0)
        selector = fields.get("selector")
        if selector is not None:
            group["selectors"].append({"selector": selector, "count": item.get("count", 0)})
        palette_crc = fields.get("palette_crc")
        if palette_crc is not None:
            group["palette_crcs"].add(palette_crc)
    rows = []
    for key, group in grouped.items():
        selectors = {}
        for sel in group["selectors"]:
            selectors[sel["selector"]] = selectors.get(sel["selector"], 0) + sel["count"]
        rows.append({
            "draw_class": key[0],
            "cycle": key[1],
            "sampled_low32": key[2],
            "fs": key[3],
            "count": group["count"],
            "palette_crcs": sorted(group["palette_crcs"]),
            "selectors": [
                {"selector": selector, "count": count}
                for selector, count in sorted(selectors.items(), key=lambda item: (-item[1], item[0]))
            ],
            "sample_detail": group["sample_detail"],
        })
    rows.sort(key=lambda row: (-row["count"], row["sampled_low32"] or "", row["cycle"] or ""))
    return rows


def render_markdown(bundle: Path, probe: dict) -> str:
    lines = []
    lines.append(f"# Sampled Selector Review\n")
    lines.append(f"- Bundle: `{bundle}`")
    lines.append(f"- Exact hits: `{probe.get('exact_hit_count', 0)}`")
    lines.append(f"- Exact misses: `{probe.get('exact_miss_count', 0)}`")
    lines.append(f"- Conflict misses: `{probe.get('exact_conflict_miss_count', 0)}`")
    lines.append(f"- Unresolved misses: `{probe.get('exact_unresolved_miss_count', 0)}`\n")

    unresolved = group_unresolved(probe.get('top_exact_unresolved_miss_buckets', []))
    conflicts = group_unresolved(probe.get('top_exact_conflict_miss_buckets', []))

    lines.append('## Unresolved')
    if not unresolved:
        lines.append('- None')
    else:
        for row in unresolved:
            lines.append(f"- `{row['sampled_low32']}` `{row['draw_class']}` `{row['cycle']}` `fs={row['fs']}` count `{row['count']}` palettes `{', '.join(row['palette_crcs']) or 'none'}`")
            for selector in row['selectors'][:8]:
                lines.append(f"  selector `{selector['selector']}` count `{selector['count']}`")

    lines.append('\n## Conflicts')
    if not conflicts:
        lines.append('- None')
    else:
        for row in conflicts:
            lines.append(f"- `{row['sampled_low32']}` `{row['draw_class']}` `{row['cycle']}` `fs={row['fs']}` count `{row['count']}` palettes `{', '.join(row['palette_crcs']) or 'none'}`")
            for selector in row['selectors'][:8]:
                lines.append(f"  selector `{selector['selector']}` count `{selector['count']}`")

    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle-dir', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()

    bundle = Path(args.bundle_dir)
    probe = load_probe(bundle)
    Path(args.output).write_text(render_markdown(bundle, probe))


if __name__ == '__main__':
    main()
