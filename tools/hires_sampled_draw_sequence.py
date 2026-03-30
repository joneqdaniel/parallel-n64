#!/usr/bin/env python3
import argparse
import json
from collections import Counter
from pathlib import Path


PREFIX = "Hi-res draw usage: "


def parse_args():
    parser = argparse.ArgumentParser(
        description="Summarize first-seen sampled draw usage into an ordered sequence."
    )
    parser.add_argument("--bundle", required=True, help="Runtime bundle directory with logs/retroarch.log")
    parser.add_argument("--sampled-key", required=True, help="Full sampled selector key, e.g. 52e0d2531b8530fb")
    parser.add_argument("--draw-class", default="texrect")
    parser.add_argument("--cycle", default="copy")
    parser.add_argument("--sampled-texel", type=int, default=0, choices=(0, 1))
    parser.add_argument("--varying-texel", type=int, default=1, choices=(0, 1))
    parser.add_argument("--output-json")
    parser.add_argument("--output-markdown")
    return parser.parse_args()


def parse_fields(line: str):
    if PREFIX not in line:
        return None
    try:
        payload = line.split(PREFIX, 1)[1].strip()
    except IndexError:
        return None
    fields = {}
    for token in payload.split():
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        fields[key] = value.rstrip(".").lower()
    return fields


def parse_rows(log_path: Path, sampled_key: str, draw_class: str, cycle: str, sampled_texel: int, varying_texel: int):
    sampled_field = f"texel{sampled_texel}_key"
    varying_field = f"texel{varying_texel}_key"
    sampled_hit_field = f"texel{sampled_texel}_hit"
    varying_hit_field = f"texel{varying_texel}_hit"
    rows = []
    for line_no, line in enumerate(log_path.read_text().splitlines(), start=1):
        fields = parse_fields(line)
        if not fields:
            continue
        if fields.get("draw_class") != draw_class or fields.get("cycle") != cycle:
            continue
        if fields.get(sampled_field) != sampled_key:
            continue
        varying_key = fields.get(varying_field)
        if not varying_key:
            continue
        rows.append(
            {
                "line_no": line_no,
                "sampled_key": sampled_key,
                "varying_key": varying_key,
                "sampled_hit": int(fields.get(sampled_hit_field, "0")),
                "varying_hit": int(fields.get(varying_hit_field, "0")),
                "fields": fields,
            }
        )
    return rows


def build_summary(bundle: Path, rows, sampled_key: str, draw_class: str, cycle: str, sampled_texel: int, varying_texel: int):
    first_seen = {}
    counts = Counter()
    for row in rows:
        key = row["varying_key"]
        counts[key] += 1
        if key not in first_seen:
            first_seen[key] = row

    ordered = [first_seen[key] for key in sorted(first_seen, key=lambda item: first_seen[item]["line_no"])]
    sequences = []
    key_to_sequence_index = {}
    for sequence_index, row in enumerate(ordered):
        key_to_sequence_index[row["varying_key"]] = sequence_index
        sequences.append(
            {
                "sequence_index": sequence_index,
                "line_no": row["line_no"],
                "addr_hex": f"line:{row['line_no']}",
                "upload_key": row["varying_key"],
                "key": row["varying_key"],
                "sampled_key": sampled_key,
                "occurrence_count": counts[row["varying_key"]],
                "varying_hit": row["varying_hit"],
                "sampled_hit": row["sampled_hit"],
            }
        )

    index_trace = [key_to_sequence_index[row["varying_key"]] for row in rows]
    delta_counts = Counter(
        (index_trace[i + 1] - index_trace[i]) % len(ordered)
        for i in range(len(index_trace) - 1)
    ) if len(index_trace) > 1 and ordered else Counter()
    repeated_runs = []
    run_start = 0
    for i in range(1, len(index_trace) + 1):
        if i == len(index_trace) or index_trace[i] != index_trace[run_start]:
            run_length = i - run_start
            if run_length > 1:
                repeated_runs.append(
                    {
                        "sequence_index": index_trace[run_start],
                        "key": ordered[index_trace[run_start]]["varying_key"],
                        "start_row": run_start,
                        "run_length": run_length,
                    }
                )
            run_start = i
    repeated_runs.sort(key=lambda item: (-item["run_length"], item["start_row"]))
    shape_hint = "unordered"
    dominant_delta = delta_counts.most_common(1)[0][0] if delta_counts else None
    dominant_delta_count = delta_counts.most_common(1)[0][1] if delta_counts else 0
    longest_run = repeated_runs[0]["run_length"] if repeated_runs else 1
    if dominant_delta == 1 and dominant_delta_count >= max(8, len(index_trace) // 2):
        if longest_run >= max(4, len(ordered) // 2):
            shape_hint = "rotating-stream-edge-dwell"
        else:
            shape_hint = "rotating-stream"
    elif dominant_delta in (0, 1) and len(repeated_runs) <= 1:
        shape_hint = "fixed-ordered-batch"

    return {
        "bundle": str(bundle),
        "log_path": str(bundle / "logs" / "retroarch.log"),
        "draw_class": draw_class,
        "cycle": cycle,
        "sampled_texel": sampled_texel,
        "varying_texel": varying_texel,
        "sampled_key": sampled_key,
        "row_count": len(rows),
        "unique_key_count": len(ordered),
        "top_keys": [{"key": key, "count": count} for key, count in counts.most_common(16)],
        "shape_hint": shape_hint,
        "cyclic_delta_counts": [{"delta": delta, "count": count} for delta, count in delta_counts.most_common(8)],
        "repeated_runs": repeated_runs[:16],
        "sequences": sequences,
    }


def render_markdown(summary):
    lines = [
        "# Sampled Draw Sequence Review",
        "",
        f"- Bundle: `{summary['bundle']}`",
        f"- draw_class: `{summary['draw_class']}`",
        f"- cycle: `{summary['cycle']}`",
        f"- sampled_key: `{summary['sampled_key']}`",
        f"- sampled_texel: `{summary['sampled_texel']}`",
        f"- varying_texel: `{summary['varying_texel']}`",
        f"- Total matching draw rows: `{summary['row_count']}`",
        f"- Unique varying keys: `{summary['unique_key_count']}`",
        f"- shape_hint: `{summary['shape_hint']}`",
        "",
        "## Top Keys",
        "",
    ]
    for row in summary["top_keys"]:
        lines.append(f"- `{row['key']}` x{row['count']}")
    lines.extend(["", "## Stream Shape", ""])
    if summary["cyclic_delta_counts"]:
        for row in summary["cyclic_delta_counts"]:
            lines.append(f"- cyclic delta `{row['delta']}` x{row['count']}")
    else:
        lines.append("- no cyclic delta data")
    if summary["repeated_runs"]:
        lines.append("")
        lines.append("Repeated runs:")
        for row in summary["repeated_runs"]:
            lines.append(
                f"- seq `{row['sequence_index']}` key `{row['key']}` start_row `{row['start_row']}` run_length `{row['run_length']}`"
            )
    lines.extend(["", "## Ordered Sequence", "", "| seq | line | varying key | count | varying hit |", "|---:|---:|---|---:|---:|"])
    for row in summary["sequences"]:
        lines.append(
            f"| `{row['sequence_index']}` | `{row['line_no']}` | `{row['key']}` | `{row['occurrence_count']}` | `{row['varying_hit']}` |"
        )
    lines.append("")
    return "\n".join(lines)


def main():
    args = parse_args()
    bundle = Path(args.bundle)
    rows = parse_rows(
        bundle / "logs" / "retroarch.log",
        args.sampled_key.lower(),
        args.draw_class,
        args.cycle,
        args.sampled_texel,
        args.varying_texel,
    )
    if not rows:
        raise SystemExit("no matching sampled draw rows found")
    summary = build_summary(
        bundle,
        rows,
        args.sampled_key.lower(),
        args.draw_class,
        args.cycle,
        args.sampled_texel,
        args.varying_texel,
    )
    serialized = json.dumps(summary, indent=2) + "\n"
    if args.output_json:
        output_json = Path(args.output_json)
        output_json.parent.mkdir(parents=True, exist_ok=True)
        output_json.write_text(serialized)
    else:
        print(serialized, end="")
    if args.output_markdown:
        output_markdown = Path(args.output_markdown)
        output_markdown.parent.mkdir(parents=True, exist_ok=True)
        output_markdown.write_text(render_markdown(summary))


if __name__ == "__main__":
    main()
