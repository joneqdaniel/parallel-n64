#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

from hires_pack_common import build_family_summary, parse_cache_entries

PROVENANCE_RE = re.compile(
    r"Hi-res keying provenance: "
    r"outcome=(?P<outcome>\w+) "
    r"source_class=(?P<source_class>[\w-]+) "
    r"provenance_class=(?P<provenance_class>[\w-]+) "
    r"mode=(?P<mode>\w+) "
    r"addr=0x(?P<addr>[0-9a-f]+) "
    r"tile=(?P<tile>\d+) "
    r"fmt=(?P<fmt>\d+) "
    r"siz=(?P<siz>\d+) "
    r"pal=(?P<pal>\d+) "
    r"wh=(?P<width>\d+)x(?P<height>\d+) "
    r"key=(?P<key>[0-9a-f]+) "
    r"pcrc=(?P<pcrc>[0-9a-f]+) "
    r"fs=(?P<formatsize>\d+) "
    r"upload=(?P<upload>\w+) "
    r"cycle=(?P<cycle>[\w-]+) "
    r"copy=(?P<copy>\d+) "
    r"tlut=(?P<tlut>\d+) "
    r"tlut_type=(?P<tlut_type>\d+) "
    r"framebuffer=(?P<framebuffer>\d+) "
    r"color_fb=(?P<color_fb>\d+) "
    r"depth_fb=(?P<depth_fb>\d+) "
    r"tmem=0x(?P<tmem>[0-9a-f]+) "
    r"line=(?P<line>\d+) "
    r"key_xy=(?P<key_x>\d+)x(?P<key_y>\d+)",
    re.IGNORECASE,
)

DRAW_USAGE_RE = re.compile(
    r"Hi-res draw usage: "
    r"draw_class=(?P<draw_class>[\w-]+) "
    r"cycle=(?P<cycle>[\w-]+) "
    r"copy=(?P<copy>\d+) "
    r"base_tile=(?P<base_tile>\d+) "
    r"uses_texel0=(?P<uses_texel0>\d+) "
    r"uses_texel1=(?P<uses_texel1>\d+) "
    r"texel0_hit=(?P<texel0_hit>\d+) "
    r"texel0_key=(?P<texel0_key>[0-9a-f]+) "
    r"texel0_fs=(?P<texel0_fs>\d+) "
    r"texel0_w=(?P<texel0_w>\d+) "
    r"texel0_h=(?P<texel0_h>\d+) "
    r"texel1_tile=(?P<texel1_tile>\d+) "
    r"texel1_hit=(?P<texel1_hit>\d+) "
    r"texel1_key=(?P<texel1_key>[0-9a-f]+) "
    r"texel1_fs=(?P<texel1_fs>\d+) "
    r"texel1_w=(?P<texel1_w>\d+) "
    r"texel1_h=(?P<texel1_h>\d+) "
    r"fmt=(?P<fmt>\d+) "
    r"siz=(?P<siz>\d+) "
    r"pal=(?P<pal>\d+) "
    r"offset=(?P<offset>\d+) "
    r"stride=(?P<stride>\d+) "
    r"sl=(?P<sl>\d+) "
    r"tl=(?P<tl>\d+) "
    r"sh=(?P<sh>\d+) "
    r"th=(?P<th>\d+) "
    r"mask_s=(?P<mask_s>\d+) "
    r"shift_s=(?P<shift_s>\d+) "
    r"mask_t=(?P<mask_t>\d+) "
    r"shift_t=(?P<shift_t>\d+) "
    r"clamp_s=(?P<clamp_s>\d+) "
    r"mirror_s=(?P<mirror_s>\d+) "
    r"clamp_t=(?P<clamp_t>\d+) "
    r"mirror_t=(?P<mirror_t>\d+)\.",
    re.IGNORECASE,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Plan and analyze targeted hi-res family probes.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    plan = subparsers.add_parser("plan", help="Extract a probe plan from a bundle log.")
    plan.add_argument("--source-bundle", required=True)
    plan.add_argument("--mode", default="block")
    plan.add_argument("--outcome", default="miss")
    plan.add_argument("--formatsize", type=int, required=True)
    plan.add_argument("--width", type=int, required=True)
    plan.add_argument("--height", type=int, required=True)
    plan.add_argument("--tile", type=int, default=None)
    plan.add_argument("--output", required=True)

    analyze = subparsers.add_parser("analyze", help="Analyze a probe bundle using a saved probe plan.")
    analyze.add_argument("--plan", required=True)
    analyze.add_argument("--snapshot-trace", required=True)
    analyze.add_argument("--cache")
    analyze.add_argument("--output-json", required=True)
    analyze.add_argument("--output-markdown", required=True)

    return parser.parse_args()


def row_bytes(width: int, siz: int) -> int:
    return (width << siz) >> 1


def parse_provenance_rows(log_path: Path) -> list[dict]:
    rows: list[dict] = []
    for line in log_path.read_text(errors="replace").splitlines():
        match = PROVENANCE_RE.search(line)
        if not match:
            continue
        row = match.groupdict()
        for key in (
            "addr",
            "tile",
            "fmt",
            "siz",
            "pal",
            "width",
            "height",
            "formatsize",
            "copy",
            "tlut",
            "tlut_type",
            "framebuffer",
            "color_fb",
            "depth_fb",
            "tmem",
            "line",
            "key_x",
            "key_y",
        ):
            base = 16 if key in ("addr", "tmem") else 10
            row[key] = int(row[key], base)
        rows.append(row)
    return rows


def parse_draw_usage_rows(log_path: Path) -> list[dict]:
    rows: list[dict] = []
    for line in log_path.read_text(errors="replace").splitlines():
        match = DRAW_USAGE_RE.search(line)
        if not match:
            continue
        row = match.groupdict()
        for key in (
            "copy",
            "base_tile",
            "uses_texel0",
            "uses_texel1",
            "texel0_hit",
            "texel0_fs",
            "texel0_w",
            "texel0_h",
            "texel1_tile",
            "texel1_hit",
            "texel1_fs",
            "texel1_w",
            "texel1_h",
            "fmt",
            "siz",
            "pal",
            "offset",
            "stride",
            "sl",
            "tl",
            "sh",
            "th",
            "mask_s",
            "shift_s",
            "mask_t",
            "shift_t",
            "clamp_s",
            "mirror_s",
            "clamp_t",
            "mirror_t",
        ):
            row[key] = int(row[key], 10)
        rows.append(row)
    return rows


def build_plan(args: argparse.Namespace) -> dict:
    source_bundle = Path(args.source_bundle)
    log_path = source_bundle / "logs" / "retroarch.log"
    rows = parse_provenance_rows(log_path)
    filtered = [
        row
        for row in rows
        if row["mode"] == args.mode
        and row["outcome"] == args.outcome
        and row["formatsize"] == args.formatsize
        and row["width"] == args.width
        and row["height"] == args.height
        and (args.tile is None or row["tile"] == args.tile)
    ]
    if not filtered:
        raise SystemExit("No matching provenance rows found for requested family.")

    addr_counter = Counter(row["addr"] for row in filtered)
    key_counter = Counter(row["key"] for row in filtered)
    addr_to_key = {}
    for row in filtered:
        addr_to_key.setdefault(row["addr"], row["key"])

    unique_addrs = sorted(addr_counter)
    min_addr = unique_addrs[0]
    max_addr = unique_addrs[-1]
    observed_siz = Counter(row["siz"] for row in filtered).most_common(1)[0][0]
    observed_fmt = Counter(row["fmt"] for row in filtered).most_common(1)[0][0]
    row_size_bytes = row_bytes(args.width, observed_siz)
    span_bytes = (max_addr - min_addr) + 0x80
    delta_counts = Counter(b - a for a, b in zip(unique_addrs, unique_addrs[1:]))

    clusters = []
    current_cluster = [unique_addrs[0]]
    for addr in unique_addrs[1:]:
        if addr - current_cluster[-1] <= 0x100:
            current_cluster.append(addr)
        else:
            clusters.append(current_cluster)
            current_cluster = [addr]
    clusters.append(current_cluster)

    exact_row_runs = []
    current_run = [unique_addrs[0]]
    for addr in unique_addrs[1:]:
        if addr - current_run[-1] == row_size_bytes:
            current_run.append(addr)
        else:
            exact_row_runs.append(current_run)
            current_run = [addr]
    exact_row_runs.append(current_run)

    plan = {
        "source_bundle": str(source_bundle),
        "log_path": str(log_path),
        "family": {
            "mode": args.mode,
            "outcome": args.outcome,
            "tile": args.tile,
            "formatsize": args.formatsize,
            "width": args.width,
            "height": args.height,
            "observed_fmt": observed_fmt,
            "observed_siz": observed_siz,
            "row_bytes": row_size_bytes,
        },
        "event_count": len(filtered),
        "unique_low32_keys": len(key_counter),
        "unique_addresses": len(unique_addrs),
        "address_counter": [
            {
                "addr": f"0x{addr:06x}",
                "count": count,
                "key": addr_to_key[addr],
            }
            for addr, count in addr_counter.most_common()
        ],
        "top_keys": [
            {"key": key, "count": count}
            for key, count in key_counter.most_common()
        ],
        "snapshot": {
            "min_addr": f"0x{min_addr:06x}",
            "max_addr": f"0x{max_addr:06x}",
            "span_bytes": span_bytes,
        },
        "address_delta_counts": [
            {"delta": f"0x{delta:x}", "count": count}
            for delta, count in delta_counts.most_common()
        ],
        "clusters": [
            {
                "start_addr": f"0x{cluster[0]:06x}",
                "end_addr": f"0x{cluster[-1]:06x}",
                "count": len(cluster),
                "addresses": [f"0x{addr:06x}" for addr in cluster],
            }
            for cluster in clusters
        ],
        "exact_row_runs": [
            {
                "start_addr": f"0x{run[0]:06x}",
                "end_addr": f"0x{run[-1]:06x}",
                "row_count": len(run),
                "candidate_surface": f"{args.width}x{len(run)}",
                "addresses": [f"0x{addr:06x}" for addr in run],
            }
            for run in exact_row_runs
        ],
    }
    return plan


def parse_snapshot_trace(path: Path) -> tuple[int, bytes]:
    fields = path.read_text().split()
    if not fields or fields[0] != "READ_CORE_MEMORY":
        raise SystemExit(f"Unexpected snapshot format: {path}")
    base_addr = int(fields[1], 16)
    data = bytes(int(field, 16) for field in fields[2:])
    return base_addr, data


def nibble_counter(data: bytes) -> Counter:
    counts: Counter = Counter()
    for byte in data:
        counts[(byte >> 4) & 0xF] += 1
        counts[byte & 0xF] += 1
    return counts


def signed_hex(value: int) -> str:
    if value == 0:
        return "0x0"
    sign = "-" if value < 0 else "+"
    return f"{sign}0x{abs(value):x}"


def rice_crc32_wrapped(data: bytes, base_off: int, width: int, height: int, size: int, row_stride: int) -> int:
    bytes_per_line = (width << size) >> 1
    if width == 0 or height == 0 or bytes_per_line < 4:
        return 0

    crc = 0
    line = 0
    for y in range(height - 1, -1, -1):
        esi = 0
        row_off = base_off + line * row_stride
        for x in range(bytes_per_line - 4, -1, -4):
            esi = int.from_bytes(data[row_off + x : row_off + x + 4], "little")
            esi ^= x
            crc = ((crc << 4) & 0xFFFFFFFF) + ((crc >> 28) & 15)
            crc = (crc + esi) & 0xFFFFFFFF
        esi ^= y
        crc = (crc + esi) & 0xFFFFFFFF
        line += 1
    return crc


def candidate_widths_for_area(total_pixels: int) -> list[int]:
    widths = []
    for width in range(4, total_pixels + 1):
        if total_pixels % width == 0:
            widths.append(width)
    return widths


def analyze_plan(plan: dict, snapshot_trace: Path, cache_path: Path | None = None) -> tuple[dict, str]:
    base_addr, data = parse_snapshot_trace(snapshot_trace)
    min_addr = int(plan["snapshot"]["min_addr"], 16)
    row_size_bytes = int(plan["family"]["row_bytes"])
    expected_span = int(plan["snapshot"]["span_bytes"])
    if base_addr != min_addr:
        raise SystemExit(
            f"Snapshot base mismatch: expected {plan['snapshot']['min_addr']}, got 0x{base_addr:06x}"
        )
    if len(data) < expected_span:
        raise SystemExit(
            f"Snapshot shorter than expected span: {len(data)} < {expected_span}"
        )

    row_groups: dict[str, list[str]] = {}
    rows = []
    row_size_bytes = int(plan["family"]["row_bytes"])
    for item in plan["address_counter"]:
        addr = int(item["addr"], 16)
        offset = addr - base_addr
        row = data[offset : offset + row_size_bytes]
        row_hash = hashlib.sha256(row).hexdigest()
        row_hex = row.hex()
        nibs = nibble_counter(row)
        nonzero_offsets = [index for index, value in enumerate(row) if value != 0]
        first_nonzero = nonzero_offsets[0] if nonzero_offsets else None
        last_nonzero = nonzero_offsets[-1] if nonzero_offsets else None
        neighborhood_before = min(0x40, offset)
        neighborhood_after = min(0x80, len(data) - offset)
        neighborhood = data[offset - neighborhood_before : offset + neighborhood_after]
        neighborhood_nonzero = [index for index, value in enumerate(neighborhood) if value != 0]
        nearby_nonzero = None
        if neighborhood_nonzero:
            nearby_nonzero = {
                "window_before": neighborhood_before,
                "window_after": neighborhood_after,
                "first_nonzero_rel": neighborhood_nonzero[0] - neighborhood_before,
                "last_nonzero_rel": neighborhood_nonzero[-1] - neighborhood_before,
                "count": len(neighborhood_nonzero),
            }
        row_groups.setdefault(row_hash, []).append(item["addr"])
        rows.append(
            {
                "addr": item["addr"],
                "count": item["count"],
                "key": item["key"],
                "offset": f"0x{offset:x}",
                "row_sha256": row_hash,
                "row_hex": row_hex,
                "first_16_bytes_hex": row[:16].hex(),
                "last_16_bytes_hex": row[-16:].hex(),
                "leading_zero_bytes": first_nonzero if first_nonzero is not None else len(row),
                "trailing_zero_bytes": (len(row) - 1 - last_nonzero) if last_nonzero is not None else len(row),
                "first_nonzero_byte": None if first_nonzero is None else f"0x{first_nonzero:x}",
                "last_nonzero_byte": None if last_nonzero is None else f"0x{last_nonzero:x}",
                "nearby_nonzero": nearby_nonzero,
                "top_nibbles": [
                    {"index": f"{index:x}", "count": count}
                    for index, count in nibs.most_common(6)
                ],
            }
        )

    duplicate_groups = [
        {"row_sha256": row_hash, "addresses": addresses}
        for row_hash, addresses in row_groups.items()
        if len(addresses) > 1
    ]
    duplicate_groups.sort(key=lambda group: (-len(group["addresses"]), group["addresses"][0]))

    family_keys = {item["key"].lower() for item in plan["address_counter"]}
    draw_usage_rows = parse_draw_usage_rows(Path(plan["log_path"]))
    matching_draw_usage = []
    for row in draw_usage_rows:
        if row["texel0_key"].lower() not in family_keys:
            continue
        if row["texel0_fs"] != int(plan["family"]["formatsize"]):
            continue
        if row["texel0_w"] != int(plan["family"]["width"]) or row["texel0_h"] != int(plan["family"]["height"]):
            continue
        matching_draw_usage.append(row)

    draw_signature_counts = Counter()
    draw_samples = {}
    for row in matching_draw_usage:
        signature = (
            f"draw={row['draw_class']} cycle={row['cycle']} copy={row['copy']} "
            f"fmt={row['fmt']} siz={row['siz']} stride={row['stride']} "
            f"sl={row['sl']} tl={row['tl']} sh={row['sh']} th={row['th']} "
            f"mask_s={row['mask_s']} shift_s={row['shift_s']} "
            f"mask_t={row['mask_t']} shift_t={row['shift_t']} "
            f"clamp_s={row['clamp_s']} mirror_s={row['mirror_s']} "
            f"clamp_t={row['clamp_t']} mirror_t={row['mirror_t']}"
        )
        draw_signature_counts[signature] += 1
        draw_samples.setdefault(signature, row)

    draw_usage_summary = [
        {
            "signature": signature,
            "count": count,
            "sample": draw_samples[signature],
        }
        for signature, count in draw_signature_counts.most_common()
    ]

    exact_row_run_pack_checks = []
    if cache_path is not None:
        cache_entries = parse_cache_entries(cache_path)
        observed_width = int(plan["family"]["width"])
        observed_size = int(plan["family"]["observed_siz"])
        formatsize = int(plan["family"]["formatsize"])
        for run in plan.get("exact_row_runs", []):
            row_count = int(run["row_count"])
            if row_count < 2:
                continue
            start_addr = int(run["start_addr"], 16)
            run_bytes = row_size_bytes * row_count
            total_pixels = (run_bytes * 2) >> observed_size
            exact_low32 = rice_crc32_wrapped(
                data,
                start_addr - base_addr,
                observed_width,
                row_count,
                observed_size,
                row_size_bytes,
            )
            exact_summary = build_family_summary(cache_entries, exact_low32, formatsize)
            reinterpretation_hits = []
            for width in candidate_widths_for_area(total_pixels):
                height = total_pixels // width
                if width == observed_width and height == row_count:
                    continue
                candidate_row_bytes = (width << observed_size) >> 1
                if candidate_row_bytes * height != run_bytes or candidate_row_bytes < 4:
                    continue
                low32 = rice_crc32_wrapped(
                    data,
                    start_addr - base_addr,
                    width,
                    height,
                    observed_size,
                    candidate_row_bytes,
                )
                summary = build_family_summary(cache_entries, low32, formatsize)
                if summary["family_entry_count"] == 0:
                    continue
                reinterpretation_hits.append(
                    {
                        "width": width,
                        "height": height,
                        "low32": f"{low32:08x}",
                        "family_entry_count": summary["family_entry_count"],
                        "exact_formatsize_entries": summary["exact_formatsize_entries"],
                        "generic_formatsize_entries": summary["generic_formatsize_entries"],
                        "recommended_tier": summary["recommended_tier"],
                        "active_replacement_dims": summary["active_replacement_dims"][:5],
                    }
                )
            exact_row_run_pack_checks.append(
                {
                    "start_addr": run["start_addr"],
                    "end_addr": run["end_addr"],
                    "candidate_surface": run["candidate_surface"],
                    "exact_surface_low32": f"{exact_low32:08x}",
                    "exact_surface_family_entry_count": exact_summary["family_entry_count"],
                    "exact_surface_exact_formatsize_entries": exact_summary["exact_formatsize_entries"],
                    "exact_surface_generic_formatsize_entries": exact_summary["generic_formatsize_entries"],
                    "exact_surface_recommended_tier": exact_summary["recommended_tier"],
                    "reinterpretation_hits": reinterpretation_hits,
                }
            )

    report = {
        "plan_source_bundle": plan["source_bundle"],
        "snapshot_trace": str(snapshot_trace),
        "cache_path": None if cache_path is None else str(cache_path),
        "family": plan["family"],
        "snapshot": {
            "base_addr": f"0x{base_addr:06x}",
            "captured_bytes": len(data),
        },
        "rows": rows,
        "duplicate_row_groups": duplicate_groups,
        "draw_usage_summary": draw_usage_summary,
        "exact_row_run_pack_checks": exact_row_run_pack_checks,
        "delta_vs_row_bytes": {
            "row_bytes": row_size_bytes,
            "matching_delta_event_count": sum(
                entry["count"] for entry in plan["address_delta_counts"] if int(entry["delta"], 16) == row_size_bytes
            ),
        },
    }

    md = []
    md.append("# Hi-Res Family Probe\n")
    md.append(f"- Source bundle: `{plan['source_bundle']}`")
    md.append(f"- Snapshot trace: `{snapshot_trace}`")
    md.append(
        f"- Family: `mode={plan['family']['mode']} fs={plan['family']['formatsize']} "
        f"wh={plan['family']['width']}x{plan['family']['height']} fmt={plan['family']['observed_fmt']} "
        f"siz={plan['family']['observed_siz']}`"
    )
    md.append(f"- Events: `{plan['event_count']}`")
    md.append(f"- Unique addresses: `{plan['unique_addresses']}`")
    md.append(f"- Unique low32 keys: `{plan['unique_low32_keys']}`\n")
    md.append(
        f"- Observed row bytes: `{row_size_bytes}` (`0x{row_size_bytes:x}`)"
    )
    delta_matches = [
        entry for entry in plan["address_delta_counts"] if int(entry["delta"], 16) == row_size_bytes
    ]
    if delta_matches:
        md.append(
            f"- `0x{row_size_bytes:x}` address delta occurs `{delta_matches[0]['count']}` times across unique addresses\n"
        )
    else:
        md.append("- No address delta matches the observed row size\n")
    md.append("## Address Clusters\n")
    for cluster in plan["clusters"]:
        md.append(
            f"- `{cluster['start_addr']} .. {cluster['end_addr']}` "
            f"count=`{cluster['count']}`"
        )
    md.append("\n## Exact Row Runs\n")
    for run in plan.get("exact_row_runs", []):
        md.append(
            f"- `{run['start_addr']} .. {run['end_addr']}` "
            f"rows=`{run['row_count']}` candidate_surface=`{run['candidate_surface']}`"
        )
    md.append("\n## Duplicate Row Groups\n")
    if duplicate_groups:
        for group in duplicate_groups[:10]:
            md.append(
                f"- `{group['row_sha256'][:12]}` -> {', '.join(group['addresses'])}"
            )
    else:
        md.append("- None")
    if draw_usage_summary:
        md.append("\n## Matched Draw-Side Regimes\n")
        for item in draw_usage_summary[:8]:
            sample = item["sample"]
            md.append(f"- count=`{item['count']}` `{item['signature']}`")
            md.append(
                f"  - sample key=`{sample['texel0_key']}` "
                f"draw_fmt_siz=`{sample['fmt']}/{sample['siz']}` "
                f"upload_family=`{plan['family']['mode']} fs={plan['family']['formatsize']} "
                f"wh={plan['family']['width']}x{plan['family']['height']}`"
            )
    if exact_row_run_pack_checks:
        md.append("\n## Exact Row Run Pack Checks\n")
        for item in exact_row_run_pack_checks:
            md.append(
                f"- `{item['start_addr']} .. {item['end_addr']}` "
                f"`{item['candidate_surface']}` "
                f"low32=`{item['exact_surface_low32']}` "
                f"family_entries=`{item['exact_surface_family_entry_count']}` "
                f"tier=`{item['exact_surface_recommended_tier']}`"
            )
            if item["reinterpretation_hits"]:
                for hit in item["reinterpretation_hits"][:8]:
                    md.append(
                        f"  - reinterpretation `{hit['width']}x{hit['height']}` "
                        f"low32=`{hit['low32']}` family_entries=`{hit['family_entry_count']}` "
                        f"tier=`{hit['recommended_tier']}`"
                    )
            else:
                md.append("  - no area-preserving reinterpretation hits in the active pack")
    md.append("\n## Row Preview\n")
    md.append("| addr | count | key | first16 | last16 | active span | nearby nz | top nibbles |")
    md.append("|---|---:|---|---|---|---|---|---|")
    for row in rows[:21]:
        top_nibbles = ", ".join(f"{entry['index']}:{entry['count']}" for entry in row["top_nibbles"])
        active_span = (
            "all-zero"
            if row["first_nonzero_byte"] is None
            else f"{row['first_nonzero_byte']}..{row['last_nonzero_byte']}"
        )
        nearby = row.get("nearby_nonzero")
        if nearby is None:
            nearby_span = "-"
        else:
            nearby_span = (
                f"{signed_hex(nearby['first_nonzero_rel'])}..{signed_hex(nearby['last_nonzero_rel'])} "
                f"({nearby['count']})"
            )
        md.append(
            f"| `{row['addr']}` | `{row['count']}` | `{row['key'][-8:]}` | "
            f"`{row['first_16_bytes_hex']}` | `{row['last_16_bytes_hex']}` | "
            f"`{active_span}` | `{nearby_span}` | `{top_nibbles}` |"
        )
    md.append("")

    return report, "\n".join(md)


def main() -> None:
    args = parse_args()
    if args.command == "plan":
        plan = build_plan(args)
        Path(args.output).write_text(json.dumps(plan, indent=2) + "\n")
        return

    plan = json.loads(Path(args.plan).read_text())
    report, markdown = analyze_plan(
        plan,
        Path(args.snapshot_trace),
        None if not args.cache else Path(args.cache),
    )
    Path(args.output_json).write_text(json.dumps(report, indent=2) + "\n")
    Path(args.output_markdown).write_text(markdown)


if __name__ == "__main__":
    main()
