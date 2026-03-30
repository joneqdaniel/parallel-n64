#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text())


def review_group(review: dict, sampled_low32: str):
    for group in review.get("groups", []):
        signature = group.get("signature", {})
        if signature.get("sampled_low32") == sampled_low32:
            return group
    raise SystemExit(f"no review group for sampled_low32={sampled_low32}")


def candidate_key(candidate: dict):
    checksum64 = candidate.get("checksum64")
    if checksum64:
        return checksum64.lower()
    texture_crc = candidate.get("texture_crc", "").lower()
    palette_crc = candidate.get("palette_crc", "").lower()
    if palette_crc and palette_crc != "00000000":
        return (palette_crc + texture_crc).lower()
    return texture_crc.lower()


def build_map(sequence: dict, group: dict, sampled_low32: str):
    by_key = {candidate_key(candidate): candidate for candidate in group.get("transport_candidates", [])}
    mapped = []
    unresolved = []
    for row in sequence.get("sequences", []):
        key = row["key"].lower()
        candidate = by_key.get(key)
        item = {
            "sequence_index": row["sequence_index"],
            "addr_hex": row.get("addr_hex"),
            "line_no": row.get("line_no"),
            "upload_key": row.get("upload_key", key),
            "candidate_found": candidate is not None,
        }
        if candidate is not None:
            item["replacement_id"] = candidate["replacement_id"]
            item["dims"] = f"{candidate['width']}x{candidate['height']}"
            item["pixel_sha256"] = candidate["pixel_sha256"]
            item["checksum64"] = candidate["checksum64"].lower()
        else:
            unresolved.append(item)
        mapped.append(item)
    return {
        "sampled_low32": sampled_low32,
        "sequence_path": sequence.get("log_path"),
        "shape_hint": sequence.get("shape_hint"),
        "sequence_count": len(sequence.get("sequences", [])),
        "mapped_candidate_count": sum(1 for item in mapped if item["candidate_found"]),
        "unresolved_count": len(unresolved),
        "unresolved_sequences": unresolved,
        "surface_map": mapped,
    }


def render_markdown(result: dict):
    lines = [
        "# Sampled Surface Map",
        "",
        f"- sampled_low32: `{result['sampled_low32']}`",
        f"- shape_hint: `{result.get('shape_hint')}`",
        f"- sequence count: `{result['sequence_count']}`",
        f"- mapped candidates: `{result['mapped_candidate_count']}`",
        f"- unresolved sequences: `{result['unresolved_count']}`",
        "",
        "## Unresolved",
        "",
    ]
    if result["unresolved_sequences"]:
        for row in result["unresolved_sequences"]:
            lines.append(
                f"- seq `{row['sequence_index']}` line `{row.get('line_no')}` key `{row['upload_key']}`"
            )
    else:
        lines.append("- none")
    lines.extend(["", "## Ordered Map", "", "| seq | line | key | replacement | dims |", "|---:|---:|---|---|---|"])
    for row in result["surface_map"]:
        lines.append(
            f"| `{row['sequence_index']}` | `{row.get('line_no', '-')}` | `{row['upload_key']}` | `{row.get('replacement_id', '-')}` | `{row.get('dims', '-')}` |"
        )
    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Map sampled-side ordered sequences onto transported candidates.")
    parser.add_argument("--sequence", required=True)
    parser.add_argument("--review", required=True)
    parser.add_argument("--sampled-low32", required=True)
    parser.add_argument("--output-json")
    parser.add_argument("--output-markdown")
    args = parser.parse_args()

    sequence = load_json(Path(args.sequence))
    review = load_json(Path(args.review))
    group = review_group(review, args.sampled_low32)
    result = build_map(sequence, group, args.sampled_low32)
    serialized = json.dumps(result, indent=2) + "\n"
    if args.output_json:
        output_json = Path(args.output_json)
        output_json.parent.mkdir(parents=True, exist_ok=True)
        output_json.write_text(serialized)
    else:
        print(serialized, end="")
    if args.output_markdown:
        output_markdown = Path(args.output_markdown)
        output_markdown.parent.mkdir(parents=True, exist_ok=True)
        output_markdown.write_text(render_markdown(result))


if __name__ == "__main__":
    main()
