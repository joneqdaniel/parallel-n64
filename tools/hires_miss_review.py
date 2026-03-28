#!/usr/bin/env python3
import argparse
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

from hires_pack_common import build_family_summary, parse_cache_entries

MISS_RE = re.compile(r"Hi-res keying miss: (.+)")
FIELD_RE = re.compile(r"(\w+)=([^\s]+)")


def parse_fields(detail: str):
    fields = {}
    for key, value in FIELD_RE.findall(detail):
        fields[key] = value.rstrip(".")
    return fields


def bucket_signature(fields):
    return " ".join(
        f"{key}={fields.get(key)}"
        for key in ("mode", "fmt", "siz", "wh", "fs", "tile")
    )


def load_miss_events(log_path: Path):
    events = []
    for line in log_path.read_text(errors="replace").splitlines():
        match = MISS_RE.search(line)
        if not match:
            continue
        detail = match.group(1)
        fields = parse_fields(detail)
        fields["detail"] = detail
        events.append(fields)
    return events


def classify_low32_presence(summary):
    if summary["family_entry_count"] == 0:
        return "absent-from-pack"
    if summary["exact_formatsize_entries"] > 0:
        return "present-exact-formatsize"
    if summary["generic_formatsize_entries"] > 0:
        return "present-generic-only"
    return "present-other-formatsize-only"


def collect_sampler_contexts(hires_data, requested_fs, requested_wh):
    sampler_usage = hires_data.get("sampler_usage", {})
    contexts = []
    for bucket in sampler_usage.get("top_buckets", []) or []:
        fields = bucket.get("fields", {})
        if fields.get("texel0_fs") != str(requested_fs):
            continue
        texel0_wh = f"{fields.get('texel0_w')}x{fields.get('texel0_h')}"
        if texel0_wh != requested_wh:
            continue
        sample_detail = bucket.get("sample_detail", "")
        uses_texel0 = None
        if "uses_texel0=" in sample_detail:
            uses_texel0 = sample_detail.split("uses_texel0=", 1)[1].split()[0]
        contexts.append(
            {
                "signature": bucket.get("signature", ""),
                "count": bucket.get("count", 0),
                "draw_class": fields.get("draw_class"),
                "cycle": fields.get("cycle"),
                "texel0_hit": fields.get("texel0_hit"),
                "texel1_hit": fields.get("texel1_hit"),
                "uses_texel0": uses_texel0,
            }
        )
    return contexts


def review_bucket(signature, events, cache_entries, hires_data):
    low32_counter = Counter(int(event["key"], 16) & 0xFFFFFFFF for event in events if event.get("key"))
    pcrc_counter = Counter(event.get("pcrc", "00000000") for event in events)
    family_summaries = []
    presence_counter = Counter()
    tier_counter = Counter()

    requested_fs = int(events[0].get("fs", "0"))
    for low32, count in low32_counter.most_common():
        summary = build_family_summary(cache_entries, low32, requested_fs)
        presence = classify_low32_presence(summary)
        presence_counter[presence] += count
        tier_counter[summary["recommended_tier"]] += count
        family_summaries.append(
            {
                "low32": f"{low32:08x}",
                "event_count": count,
                "presence": presence,
                "recommended_tier": summary["recommended_tier"],
                "family_entry_count": summary["family_entry_count"],
                "exact_formatsize_entries": summary["exact_formatsize_entries"],
                "generic_formatsize_entries": summary["generic_formatsize_entries"],
                "active_unique_palette_count": summary["active_unique_palette_count"],
                "active_unique_repl_dim_count": summary["active_unique_repl_dim_count"],
                "active_replacement_dims": summary["active_replacement_dims"][:5],
            }
        )

    requested_wh = events[0].get("wh", "0x0")
    return {
        "signature": signature,
        "event_count": len(events),
        "unique_low32_count": len(low32_counter),
        "unique_pcrc_count": len(pcrc_counter),
        "top_pcrcs": [{"pcrc": pcrc, "count": count} for pcrc, count in pcrc_counter.most_common(5)],
        "presence_breakdown": [{"kind": kind, "count": count} for kind, count in presence_counter.most_common()],
        "recommended_tier_breakdown": [{"tier": tier, "count": count} for tier, count in tier_counter.most_common()],
        "top_low32_families": family_summaries[:8],
        "sample_details": [event["detail"] for event in events[:3]],
        "sampler_contexts": collect_sampler_contexts(hires_data, requested_fs, requested_wh),
    }


def render_markdown(bundle_path: Path, cache_path: Path, reviews):
    lines = []
    lines.append(f"# Hi-Res Miss Review")
    lines.append("")
    lines.append(f"- Bundle: `{bundle_path}`")
    lines.append(f"- Cache: `{cache_path}`")
    lines.append("")
    for review in reviews:
        lines.append(f"## `{review['signature']}`")
        lines.append("")
        lines.append(f"- Events: `{review['event_count']}`")
        lines.append(f"- Unique low32 keys: `{review['unique_low32_count']}`")
        lines.append(f"- Unique palette CRCs: `{review['unique_pcrc_count']}`")
        if review["presence_breakdown"]:
            lines.append(
                "- Pack presence: "
                + ", ".join(f"`{item['kind']}={item['count']}`" for item in review["presence_breakdown"])
            )
        if review["recommended_tier_breakdown"]:
            lines.append(
                "- Family tiers: "
                + ", ".join(f"`{item['tier']}={item['count']}`" for item in review["recommended_tier_breakdown"])
            )
        if review["top_pcrcs"]:
            lines.append(
                "- Top palette CRCs: "
                + ", ".join(f"`{item['pcrc']} x{item['count']}`" for item in review["top_pcrcs"])
            )
        if review.get("sampler_contexts"):
            lines.append(
                "- Sampler contexts: "
                + ", ".join(
                    f"`{ctx['draw_class']}/{ctx['cycle']} count={ctx['count']} uses_texel0={ctx['uses_texel0']} texel1_hit={ctx['texel1_hit']}`"
                    for ctx in review["sampler_contexts"]
                )
            )
        lines.append("")
        lines.append("| low32 | events | presence | tier | exact | generic | palettes | repl dims |")
        lines.append("|---|---:|---|---|---:|---:|---:|---:|")
        for family in review["top_low32_families"]:
            lines.append(
                f"| `{family['low32']}` | {family['event_count']} | `{family['presence']}` | "
                f"`{family['recommended_tier']}` | {family['exact_formatsize_entries']} | "
                f"{family['generic_formatsize_entries']} | {family['active_unique_palette_count']} | "
                f"{family['active_unique_repl_dim_count']} |"
            )
        lines.append("")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Review top hi-res miss buckets against a pack cache.")
    parser.add_argument("--bundle", required=True, help="Strict bundle path with hires-evidence.json and retroarch.log.")
    parser.add_argument("--cache", required=True, help="Path to .hts or .htc cache.")
    parser.add_argument("--top", type=int, default=5, help="Number of top miss buckets to review.")
    parser.add_argument("--format", choices=["json", "markdown"], default="markdown")
    args = parser.parse_args()

    bundle_path = Path(args.bundle)
    cache_path = Path(args.cache)

    hires_path = bundle_path / "traces" / "hires-evidence.json"
    log_path = bundle_path / "logs" / "retroarch.log"
    hires_data = json.loads(hires_path.read_text())
    cache_entries = parse_cache_entries(cache_path)
    miss_events = load_miss_events(log_path)

    events_by_signature = defaultdict(list)
    for event in miss_events:
        events_by_signature[bucket_signature(event)].append(event)

    top_signatures = [
        bucket["signature"]
        for bucket in hires_data.get("bucket_summaries", {}).get("miss", {}).get("top_buckets", [])[: args.top]
    ]
    reviews = [review_bucket(signature, events_by_signature[signature], cache_entries, hires_data) for signature in top_signatures]

    if args.format == "json":
        print(json.dumps({"bundle": str(bundle_path), "cache": str(cache_path), "reviews": reviews}, indent=2))
    else:
        print(render_markdown(bundle_path, cache_path, reviews))


if __name__ == "__main__":
    main()
