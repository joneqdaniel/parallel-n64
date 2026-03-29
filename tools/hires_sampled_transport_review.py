#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

from hires_pack_common import decode_entry_rgba8, parse_cache_entries

UPLOAD_RE = re.compile(r"Hi-res keying (?:hit|miss): (.+)")
SAMPLED_EXACT_RE = re.compile(r"Hi-res sampled-object exact hit: (.+)")
FIELD_RE = re.compile(r"(\w+)=([^\s]+)")


def parse_fields(detail):
    fields = {}
    for key, value in FIELD_RE.findall(detail):
        fields[key] = value.rstrip(".")
    return fields


def parse_log_events(log_path: Path):
    sampled_groups = defaultdict(lambda: {"events": [], "uploads": Counter()})
    last_upload = None

    for line in log_path.read_text(errors="replace").splitlines():
        upload_match = UPLOAD_RE.search(line)
        if upload_match:
            detail = upload_match.group(1)
            fields = parse_fields(detail)
            fields["detail"] = detail
            last_upload = fields
            continue

        sampled_match = SAMPLED_EXACT_RE.search(line)
        if not sampled_match:
            continue

        detail = sampled_match.group(1)
        fields = parse_fields(detail)
        fields["detail"] = detail
        signature = (
            fields.get("draw_class"),
            fields.get("cycle"),
            fields.get("sampled_low32"),
            fields.get("sampled_entry_pcrc"),
            fields.get("sampled_sparse_pcrc"),
            fields.get("fs"),
            fields.get("repl"),
        )
        group = sampled_groups[signature]
        group["events"].append({"sampled": fields, "upload": last_upload})
        if last_upload and last_upload.get("key"):
            group["uploads"][last_upload["key"]] += 1
        last_upload = None

    return sampled_groups


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


def build_review(bundle_path: Path, cache_path: Path):
    cache_entries = parse_cache_entries(cache_path)
    by_checksum = defaultdict(list)
    for entry in cache_entries:
        by_checksum[entry["checksum64"]].append(entry)

    sampled_groups = parse_log_events(bundle_path / "logs" / "retroarch.log")
    groups = []
    for signature, group in sorted(sampled_groups.items(), key=lambda item: (-len(item[1]["events"]), item[0])):
        first_sampled = group["events"][0]["sampled"]
        upload_rows = []
        candidate_by_id = {}

        for upload_key, count in group["uploads"].most_common():
            checksum64 = int(upload_key, 16)
            entries = by_checksum.get(checksum64, [])
            candidates = [build_candidate(entry, cache_path) for entry in entries]
            for candidate in candidates:
                candidate_by_id.setdefault(candidate["replacement_id"], candidate)
            upload_rows.append(
                {
                    "upload_checksum64": upload_key,
                    "event_count": count,
                    "candidate_count": len(candidates),
                    "candidates": candidates,
                }
            )

        candidate_dims = Counter(
            f"{candidate['width']}x{candidate['height']}" for candidate in candidate_by_id.values()
        )
        candidate_pixels = Counter(candidate["pixel_sha256"] for candidate in candidate_by_id.values())
        groups.append(
            {
                "sampled_object_id": (
                    f"sampled-low32{first_sampled.get('sampled_low32')}-"
                    f"fs{first_sampled.get('fs')}"
                ),
                "signature": {
                    "draw_class": first_sampled.get("draw_class"),
                    "cycle": first_sampled.get("cycle"),
                    "sampled_low32": first_sampled.get("sampled_low32"),
                    "sampled_entry_pcrc": first_sampled.get("sampled_entry_pcrc"),
                    "sampled_sparse_pcrc": first_sampled.get("sampled_sparse_pcrc"),
                    "formatsize": int(first_sampled.get("fs", "0")),
                    "replacement_dims": first_sampled.get("repl"),
                },
                "exact_hit_count": len(group["events"]),
                "unique_upload_family_count": len(group["uploads"]),
                "unique_transport_candidate_count": len(candidate_by_id),
                "unique_transport_pixel_count": len(candidate_pixels),
                "transport_candidate_dims": [
                    {"dims": dims, "count": count} for dims, count in candidate_dims.most_common()
                ],
                "top_upload_families": upload_rows[:12],
                "transport_candidates": sorted(candidate_by_id.values(), key=lambda item: item["replacement_id"]),
            }
        )

    return {
        "bundle": str(bundle_path),
        "cache": str(cache_path),
        "group_count": len(groups),
        "groups": groups,
    }


def render_markdown(review):
    lines = []
    lines.append("# Hi-Res Sampled Transport Review")
    lines.append("")
    lines.append(f"- Bundle: `{review['bundle']}`")
    lines.append(f"- Cache: `{review['cache']}`")
    lines.append(f"- Groups: `{review['group_count']}`")
    lines.append("")

    for group in review["groups"]:
        sig = group["signature"]
        lines.append(
            f"## `{sig['sampled_low32']}` `{sig['draw_class']}/{sig['cycle']}` `fs={sig['formatsize']}` `repl={sig['replacement_dims']}`"
        )
        lines.append("")
        lines.append(f"- Exact hits: `{group['exact_hit_count']}`")
        lines.append(f"- Unique upload families: `{group['unique_upload_family_count']}`")
        lines.append(f"- Unique transport candidates: `{group['unique_transport_candidate_count']}`")
        lines.append(f"- Unique transport pixel payloads: `{group['unique_transport_pixel_count']}`")
        if group["transport_candidate_dims"]:
            lines.append(
                "- Transport dims: "
                + ", ".join(f"`{item['dims']} x{item['count']}`" for item in group["transport_candidate_dims"])
            )
        lines.append("")
        lines.append("| upload key | events | candidates |")
        lines.append("|---|---:|---:|")
        for item in group["top_upload_families"]:
            lines.append(
                f"| `{item['upload_checksum64']}` | {item['event_count']} | {item['candidate_count']} |"
            )
        lines.append("")
        lines.append("| candidate | dims | palette | pixel sha256 |")
        lines.append("|---|---|---|---|")
        for candidate in group["transport_candidates"][:20]:
            lines.append(
                f"| `{candidate['replacement_id']}` | `{candidate['width']}x{candidate['height']}` | "
                f"`{candidate['palette_crc']}` | `{candidate['pixel_sha256'][:16]}` |"
            )
        lines.append("")

    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Review transport candidate pools behind sampled-object exact hits.")
    parser.add_argument("--bundle", required=True, help="Runtime bundle with retroarch.log and hires-evidence.json.")
    parser.add_argument("--cache", required=True, help="Path to .hts or .htc cache.")
    parser.add_argument("--format", choices=("json", "markdown"), default="markdown")
    args = parser.parse_args()

    review = build_review(Path(args.bundle), Path(args.cache))
    if args.format == "json":
        print(json.dumps(review, indent=2))
    else:
        print(render_markdown(review))


if __name__ == "__main__":
    main()
