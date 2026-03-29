#!/usr/bin/env python3
import argparse
import json
import re
from collections import Counter
from pathlib import Path

LINE_RE = re.compile(
    r"Hi-res keying (?P<outcome>hit|miss): mode=tile addr=0x(?P<addr>[0-9a-fA-F]+) tile=(?P<tile>\d+) "
    r"fmt=(?P<fmt>\d+) siz=(?P<siz>\d+) pal=(?P<pal>\d+) wh=(?P<width>\d+)x(?P<height>\d+) "
    r"key=(?P<key>[0-9a-fA-F]+) pcrc=(?P<pcrc>[0-9a-fA-F]+) fs=(?P<formatsize>\d+) hit=(?P<hit>[01])\."
)


def parse_args():
    parser = argparse.ArgumentParser(description='Summarize sequential title-stripe runtime keying from a bundle log.')
    parser.add_argument('--bundle', required=True, help='Runtime bundle directory with logs/retroarch.log')
    parser.add_argument('--width', type=int, default=200)
    parser.add_argument('--height', type=int, default=2)
    parser.add_argument('--formatsize', type=int, default=768)
    parser.add_argument('--fmt', type=int, default=0)
    parser.add_argument('--siz', type=int, default=3)
    parser.add_argument('--output-json')
    parser.add_argument('--output-markdown')
    return parser.parse_args()


def parse_rows(log_path: Path, width: int, height: int, formatsize: int, fmt: int, siz: int):
    rows = []
    for line in log_path.read_text().splitlines():
        match = LINE_RE.search(line)
        if not match:
            continue
        row = match.groupdict()
        if int(row['width']) != width or int(row['height']) != height:
            continue
        if int(row['formatsize']) != formatsize:
            continue
        if int(row['fmt']) != fmt or int(row['siz']) != siz:
            continue
        rows.append({
            'addr': int(row['addr'], 16),
            'key': row['key'].lower(),
            'pcrc': row['pcrc'].lower(),
            'outcome': row['outcome'],
            'hit': int(row['hit']),
            'tile': int(row['tile']),
            'fmt': int(row['fmt']),
            'siz': int(row['siz']),
            'pal': int(row['pal']),
            'formatsize': int(row['formatsize']),
        })
    return rows


def build_summary(bundle: Path, rows):
    unique_by_addr = {}
    for row in rows:
        unique_by_addr.setdefault(row['addr'], row)
    ordered = [unique_by_addr[addr] for addr in sorted(unique_by_addr)]
    deltas = [ordered[i + 1]['addr'] - ordered[i]['addr'] for i in range(len(ordered) - 1)]
    dominant_delta = Counter(deltas).most_common(1)[0][0] if deltas else None
    base_addr = ordered[0]['addr'] if ordered else None

    sequences = []
    if base_addr is not None and dominant_delta:
        for row in ordered:
            sequence_index = (row['addr'] - base_addr) // dominant_delta
            item = dict(row)
            item['sequence_index'] = int(sequence_index)
            sequences.append(item)
    else:
        for sequence_index, row in enumerate(ordered):
            item = dict(row)
            item['sequence_index'] = sequence_index
            sequences.append(item)

    key_counts = Counter(item['key'] for item in sequences)
    outcome_counts = Counter(item['outcome'] for item in sequences)
    missing = [item for item in sequences if item['hit'] == 0]
    return {
        'bundle': str(bundle),
        'log_path': str(bundle / 'logs' / 'retroarch.log'),
        'row_count': len(rows),
        'unique_addr_count': len(ordered),
        'base_addr_hex': f'0x{base_addr:06x}' if base_addr is not None else None,
        'dominant_addr_delta': dominant_delta,
        'dominant_addr_delta_hex': f'0x{dominant_delta:x}' if dominant_delta is not None else None,
        'outcome_counts': dict(outcome_counts),
        'unique_key_count': len(key_counts),
        'top_keys': [{'key': key, 'count': count} for key, count in key_counts.most_common(12)],
        'missing_sequences': [
            {
                'sequence_index': item['sequence_index'],
                'addr_hex': f"0x{item['addr']:06x}",
                'key': item['key'],
            }
            for item in missing
        ],
        'sequences': [
            {
                'sequence_index': item['sequence_index'],
                'addr_hex': f"0x{item['addr']:06x}",
                'key': item['key'],
                'outcome': item['outcome'],
                'hit': item['hit'],
            }
            for item in sequences
        ],
    }


def render_markdown(summary):
    lines = [
        '# Title Stripe Sequence Review',
        '',
        f"- Bundle: `{summary['bundle']}`",
        f"- Unique stripe uploads: `{summary['unique_addr_count']}`",
        f"- Dominant address delta: `{summary['dominant_addr_delta_hex']}`",
        f"- Outcome counts: `hit={summary['outcome_counts'].get('hit', 0)}` `miss={summary['outcome_counts'].get('miss', 0)}`",
        f"- Unique keys: `{summary['unique_key_count']}`",
        '',
        '## Top Keys',
        '',
    ]
    for row in summary['top_keys']:
        lines.append(f"- `{row['key']}` x{row['count']}")
    lines.extend(['', '## Missing Sequences', ''])
    if summary['missing_sequences']:
        for row in summary['missing_sequences']:
            lines.append(f"- seq `{row['sequence_index']}` addr `{row['addr_hex']}` key `{row['key']}`")
    else:
        lines.append('- none')
    lines.extend(['', '## Full Sequence', '', '| seq | addr | key | outcome |', '|---:|---|---|---|'])
    for row in summary['sequences']:
        lines.append(f"| `{row['sequence_index']}` | `{row['addr_hex']}` | `{row['key']}` | `{row['outcome']}` |")
    lines.append('')
    return '\n'.join(lines)


def main():
    args = parse_args()
    bundle = Path(args.bundle)
    rows = parse_rows(bundle / 'logs' / 'retroarch.log', args.width, args.height, args.formatsize, args.fmt, args.siz)
    if not rows:
        raise SystemExit('no matching stripe rows found')
    summary = build_summary(bundle, rows)
    serialized = json.dumps(summary, indent=2) + '\n'
    if args.output_json:
        output_json = Path(args.output_json)
        output_json.parent.mkdir(parents=True, exist_ok=True)
        output_json.write_text(serialized)
    else:
        print(serialized, end='')
    if args.output_markdown:
        output_markdown = Path(args.output_markdown)
        output_markdown.parent.mkdir(parents=True, exist_ok=True)
        output_markdown.write_text(render_markdown(summary))


if __name__ == '__main__':
    main()
