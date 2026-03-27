#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path

PROBE_RE = re.compile(
    r"Hi-res sampled-object probe: "
    r"draw_class=(?P<draw_class>[\w-]+) "
    r"cycle=(?P<cycle>[\w-]+) "
    r"tile=(?P<tile>\d+) "
    r"fmt=(?P<fmt>\d+) "
    r"siz=(?P<siz>\d+) "
    r"pal=(?P<pal>\d+) "
    r"off=(?P<off>\d+) "
    r"stride=(?P<stride>\d+) "
    r"wh=(?P<width>\d+)x(?P<height>\d+) "
    r"upload_low32=(?P<upload_low32>[0-9a-f]+) "
    r"upload_pcrc=(?P<upload_pcrc>[0-9a-f]+) "
    r"sampled_low32=(?P<sampled_low32>[0-9a-f]+) "
    r"sampled_entry_pcrc=(?P<sampled_entry_pcrc>[0-9a-f]+) "
    r"sampled_sparse_pcrc=(?P<sampled_sparse_pcrc>[0-9a-f]+) "
    r"sampled_entry_count=(?P<sampled_entry_count>\d+) "
    r"sampled_used_count=(?P<sampled_used_count>\d+) "
    r"fs=(?P<formatsize>\d+) "
    r"entry_hit=(?P<entry_hit>\d+) "
    r"sparse_hit=(?P<sparse_hit>\d+) "
    r"family=(?P<family>\d+) "
    r"unique_repl_dims=(?P<unique_repl_dims>\d+) "
    r"sample_repl=(?P<sample_repl_w>\d+)x(?P<sample_repl_h>\d+)\.",
    re.IGNORECASE,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Review sampled-object probe output from a bundle log.")
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--output-markdown")
    parser.add_argument("--output-json")
    return parser.parse_args()


def normalize_row(row: dict) -> dict:
    row = dict(row)
    if "wh" in row and ("width" not in row or "height" not in row):
        width, height = row["wh"].split("x", 1)
        row["width"] = width
        row["height"] = height
    if "fs" in row and "formatsize" not in row:
        row["formatsize"] = row["fs"]
    if "sample_repl" in row and ("sample_repl_w" not in row or "sample_repl_h" not in row):
        repl_w, repl_h = row["sample_repl"].split("x", 1)
        row["sample_repl_w"] = repl_w
        row["sample_repl_h"] = repl_h
    for key in (
        "tile", "fmt", "siz", "pal", "off", "stride", "width", "height",
        "sampled_entry_count", "sampled_used_count", "formatsize",
        "entry_hit", "sparse_hit", "family", "unique_repl_dims",
        "sample_repl_w", "sample_repl_h",
    ):
        row[key] = int(row[key], 10)
    for key in (
        "upload_low32", "upload_pcrc", "sampled_low32",
        "sampled_entry_pcrc", "sampled_sparse_pcrc",
    ):
        row[key] = int(row[key], 16)
    return row


def parse_probe_rows(bundle: Path) -> list[dict]:
    hires_path = bundle / "traces" / "hires-evidence.json"
    if hires_path.is_file():
        data = json.loads(hires_path.read_text())
        groups = data.get("sampled_object_probe", {}).get("groups", [])
        if groups:
            return [normalize_row(row) for row in groups]

    log_path = bundle / "logs" / "retroarch.log"
    rows: list[dict] = []
    for line in log_path.read_text(errors="replace").splitlines():
        match = PROBE_RE.search(line)
        if not match:
            continue
        rows.append(normalize_row(match.groupdict()))
    return rows


def build_report(rows: list[dict], bundle: Path) -> dict:
    sampled_groups: dict[tuple, dict] = {}
    for row in rows:
        key = (
            row["draw_class"], row["cycle"], row["fmt"], row["siz"], row["off"], row["stride"],
            row["width"], row["height"], row["sampled_low32"], row["sampled_sparse_pcrc"], row["formatsize"],
        )
        group = sampled_groups.setdefault(
            key,
            {
                "draw_class": row["draw_class"],
                "cycle": row["cycle"],
                "fmt": row["fmt"],
                "siz": row["siz"],
                "off": row["off"],
                "stride": row["stride"],
                "width": row["width"],
                "height": row["height"],
                "sampled_low32": row["sampled_low32"],
                "sampled_entry_pcrc": row["sampled_entry_pcrc"],
                "sampled_sparse_pcrc": row["sampled_sparse_pcrc"],
                "sampled_entry_count": row["sampled_entry_count"],
                "sampled_used_count": row["sampled_used_count"],
                "formatsize": row["formatsize"],
                "entry_hit": bool(row["entry_hit"]),
                "sparse_hit": bool(row["sparse_hit"]),
                "family": bool(row["family"]),
                "unique_repl_dims": row["unique_repl_dims"],
                "sample_repl_w": row["sample_repl_w"],
                "sample_repl_h": row["sample_repl_h"],
                "upload_low32s": Counter(),
                "upload_pcrcs": Counter(),
            },
        )
        group["upload_low32s"][row["upload_low32"]] += 1
        group["upload_pcrcs"][row["upload_pcrc"]] += 1

    report = {
        "bundle": str(bundle),
        "probe_event_count": len(rows),
        "sampled_group_count": len(sampled_groups),
        "sampled_groups": [],
    }
    for group in sampled_groups.values():
        group["upload_low32s"] = [
            {"value": f"{value:08x}", "count": count}
            for value, count in group["upload_low32s"].most_common()
        ]
        group["upload_pcrcs"] = [
            {"value": f"{value:08x}", "count": count}
            for value, count in group["upload_pcrcs"].most_common()
        ]
        report["sampled_groups"].append(group)
    report["sampled_groups"].sort(
        key=lambda g: (g["draw_class"], g["off"], g["stride"], g["sampled_low32"])
    )
    return report


def render_markdown(report: dict) -> str:
    lines = [
        "# Hi-Res Sampled-Object Review",
        "",
        f"- Bundle: `{report['bundle']}`",
        f"- Probe events: `{report['probe_event_count']}`",
        f"- Unique sampled groups: `{report['sampled_group_count']}`",
        "",
    ]
    for group in report["sampled_groups"]:
        lines.extend(
            [
                f"## `{group['draw_class']} off=0x{group['off']:03x} stride={group['stride']} wh={group['width']}x{group['height']} fs={group['formatsize']}`",
                "",
                f"- Sampled key: `{group['sampled_low32']:08x}`",
                f"- Sampled entry palette CRC: `{group['sampled_entry_pcrc']:08x}`",
                f"- Sampled sparse palette CRC: `{group['sampled_sparse_pcrc']:08x}`",
                f"- Sampled entry count: `{group['sampled_entry_count']}`",
                f"- Sampled used palette indices: `{group['sampled_used_count']}`",
                f"- Pack exact entry hit: `{1 if group['entry_hit'] else 0}`",
                f"- Pack exact sparse hit: `{1 if group['sparse_hit'] else 0}`",
                f"- Pack family available under sampled key: `{1 if group['family'] else 0}`",
                f"- Unique replacement-dimension families: `{group['unique_repl_dims']}`",
                f"- Sample replacement dims: `{group['sample_repl_w']}x{group['sample_repl_h']}`",
                "",
                "### Upload Families",
                "",
                "| upload low32 | events | upload pcrc set |",
                "|---|---:|---|",
            ]
        )
        upload_pcrc_values = ", ".join(item["value"] for item in group["upload_pcrcs"]) or "n/a"
        for item in group["upload_low32s"]:
            lines.append(f"| `{item['value']}` | {item['count']} | `{upload_pcrc_values}` |")
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    bundle = Path(args.bundle)
    rows = parse_probe_rows(bundle)
    report = build_report(rows, bundle)
    if args.output_json:
        Path(args.output_json).write_text(json.dumps(report, indent=2) + "\n")
    markdown = render_markdown(report)
    if args.output_markdown:
        Path(args.output_markdown).write_text(markdown + "\n")
    print(markdown)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
