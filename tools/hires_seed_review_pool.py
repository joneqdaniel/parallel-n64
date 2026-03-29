#!/usr/bin/env python3
import argparse
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

from hires_pack_common import decode_entry_rgba8, parse_cache_entries


def load_json(path: Path):
    return json.loads(path.read_text())


def make_replacement_id(entry):
    return (
        f"legacy-{entry['texture_crc']:08x}-{entry['palette_crc']:08x}-"
        f"fs{entry['formatsize']}-{entry['width']}x{entry['height']}"
    )


def build_candidate(entry, cache_path: Path):
    rgba = decode_entry_rgba8(cache_path, entry)
    return {
        "replacement_id": make_replacement_id(entry),
        "checksum64": f"{entry['checksum64']:016x}",
        "texture_crc": f"{entry['texture_crc']:08x}",
        "palette_crc": f"{entry['palette_crc']:08x}",
        "formatsize": entry["formatsize"],
        "width": entry["width"],
        "height": entry["height"],
        "data_size": entry["data_size"],
        "pixel_sha256": hashlib.sha256(rgba).hexdigest(),
    }


def parse_seed_formatsizes(raw_values):
    if not raw_values:
        return None
    return {int(value) for value in raw_values}


def select_seed_candidates(cache_entries, cache_path: Path, width: int, height: int, formatsizes):
    selected = []
    for entry in cache_entries:
        if int(entry["width"]) != width or int(entry["height"]) != height:
            continue
        if formatsizes is not None and int(entry["formatsize"]) not in formatsizes:
            continue
        selected.append(build_candidate(entry, cache_path))
    selected.sort(key=lambda item: item["replacement_id"])
    return selected


def seed_review_groups(review, candidates, sampled_low32s, width, height, formatsizes, cache_path: Path):
    target_low32s = set(sampled_low32s)
    dim_counter = Counter(f"{candidate['width']}x{candidate['height']}" for candidate in candidates)
    pixel_counter = Counter(candidate["pixel_sha256"] for candidate in candidates)

    for group in review.get("groups", []):
        signature = group.get("signature", {})
        if signature.get("sampled_low32") not in target_low32s:
            continue
        group["transport_candidates"] = [dict(candidate) for candidate in candidates]
        group["unique_transport_candidate_count"] = len(candidates)
        group["unique_transport_pixel_count"] = len(pixel_counter)
        group["transport_candidate_dims"] = [
            {"dims": dims, "count": count} for dims, count in dim_counter.most_common()
        ]
        group["seeded_transport_pool"] = {
            "source": "cache-dimension-seed",
            "cache_path": str(cache_path),
            "width": width,
            "height": height,
            "formatsizes": sorted(formatsizes) if formatsizes is not None else None,
            "candidate_count": len(candidates),
            "note": (
                "Seeded review-only candidate pool from source-backed cache dimensions. "
                "This does not assert an exact runtime/upload match."
            ),
        }
    return review


def render_markdown(review):
    lines = []
    lines.append("# Seeded Hi-Res Review Pool")
    lines.append("")
    lines.append(f"- Source review: `{review.get('source_review_path', '')}`")
    lines.append(f"- Cache: `{review.get('cache', '')}`")
    lines.append(f"- Group count: `{review.get('group_count', 0)}`")
    lines.append("")

    for group in review.get("groups", []):
        signature = group.get("signature", {})
        seeded = group.get("seeded_transport_pool")
        lines.append(
            f"## `{signature.get('sampled_low32')}` `{signature.get('draw_class')}/{signature.get('cycle')}` `fs={signature.get('formatsize')}`"
        )
        lines.append("")
        lines.append(f"- Exact hits: `{group.get('exact_hit_count', 0)}`")
        lines.append(f"- Probe events: `{group.get('probe_event_count', 0)}`")
        lines.append(f"- Unique upload families: `{group.get('unique_upload_family_count', 0)}`")
        lines.append(f"- Unique transport candidates: `{group.get('unique_transport_candidate_count', 0)}`")
        if seeded:
            lines.append(
                f"- Seed source: `{seeded['source']}` `{seeded['width']}x{seeded['height']}` `formatsizes={seeded['formatsizes']}`"
            )
            lines.append(f"- Note: {seeded['note']}")
        if group.get("transport_candidate_dims"):
            lines.append(
                "- Transport dims: "
                + ", ".join(f"`{item['dims']} x{item['count']}`" for item in group["transport_candidate_dims"])
            )
        lines.append("")
        lines.append("| candidate | dims | palette | pixel sha256 |")
        lines.append("|---|---|---|---|")
        for candidate in group.get("transport_candidates", []):
            lines.append(
                f"| `{candidate['replacement_id']}` | `{candidate['width']}x{candidate['height']}` | `{candidate['palette_crc']}` | `{candidate['pixel_sha256'][:16]}` |"
            )
        lines.append("")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(
        description="Seed sampled-object review groups with a source-backed cache candidate pool."
    )
    parser.add_argument("--review", required=True, help="Existing sampled transport review.json")
    parser.add_argument("--cache", required=True, help="Path to .hts or .htc cache")
    parser.add_argument("--sampled-low32", action="append", required=True, help="Target sampled_low32")
    parser.add_argument("--width", type=int, required=True, help="Candidate replacement width")
    parser.add_argument("--height", type=int, required=True, help="Candidate replacement height")
    parser.add_argument(
        "--seed-formatsize",
        action="append",
        help="Allowed candidate formatsize. Pass multiple times; default is any.",
    )
    parser.add_argument("--output-json", help="Optional output JSON path")
    parser.add_argument("--output-markdown", help="Optional output markdown path")
    args = parser.parse_args()

    review_path = Path(args.review)
    cache_path = Path(args.cache)
    review = load_json(review_path)
    cache_entries = parse_cache_entries(cache_path)
    formatsizes = parse_seed_formatsizes(args.seed_formatsize)
    candidates = select_seed_candidates(cache_entries, cache_path, args.width, args.height, formatsizes)
    if not candidates:
        raise SystemExit(
            f"no cache candidates matched {args.width}x{args.height} formatsizes={sorted(formatsizes) if formatsizes is not None else 'any'}"
        )

    seeded_review = seed_review_groups(
        review,
        candidates,
        args.sampled_low32,
        args.width,
        args.height,
        formatsizes,
        cache_path,
    )
    seeded_review["source_review_path"] = str(review_path)
    seeded_review["cache"] = str(cache_path)

    serialized_json = json.dumps(seeded_review, indent=2) + "\n"
    if args.output_json:
        output_json = Path(args.output_json)
        output_json.parent.mkdir(parents=True, exist_ok=True)
        output_json.write_text(serialized_json)
    else:
        sys.stdout.write(serialized_json)

    if args.output_markdown:
        output_markdown = Path(args.output_markdown)
        output_markdown.parent.mkdir(parents=True, exist_ok=True)
        output_markdown.write_text(render_markdown(seeded_review))


if __name__ == "__main__":
    main()
