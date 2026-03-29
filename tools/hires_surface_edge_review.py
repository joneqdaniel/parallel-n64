#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text())


def classify_unresolved_slots(surface: dict):
    slots = surface.get('slots', [])
    unresolved = surface.get('unresolved_sequences', [])
    resolved_indices = [slot['sequence_index'] for slot in slots if slot.get('replacement_id')]
    first_resolved = min(resolved_indices) if resolved_indices else None
    last_resolved = max(resolved_indices) if resolved_indices else None
    by_index = {slot['sequence_index']: slot for slot in slots}

    items = []
    for row in unresolved:
        seq = row['sequence_index']
        if first_resolved is None or last_resolved is None:
            position = 'all-unresolved'
        elif seq < first_resolved:
            position = 'left-edge'
        elif seq > last_resolved:
            position = 'right-edge'
        else:
            position = 'interior'

        prev_slot = by_index.get(seq - 1)
        next_slot = by_index.get(seq + 1)
        items.append({
            'sequence_index': seq,
            'position_class': position,
            'upload_key': row.get('upload_key'),
            'addr_hex': row.get('addr_hex'),
            'prev_replacement_id': prev_slot.get('replacement_id') if prev_slot else None,
            'next_replacement_id': next_slot.get('replacement_id') if next_slot else None,
            'prev_upload_key': prev_slot.get('upload_key') if prev_slot else None,
            'next_upload_key': next_slot.get('upload_key') if next_slot else None,
        })
    return {
        'surface_id': surface['surface_id'],
        'sampled_low32': surface['sampled_low32'],
        'slot_count': surface.get('slot_count', 0),
        'first_resolved_index': first_resolved,
        'last_resolved_index': last_resolved,
        'unresolved_count': len(items),
        'edge_only': bool(items) and all(item['position_class'] != 'interior' for item in items),
        'unresolved_slots': items,
    }


def render_markdown(report: dict):
    lines = [
        '# Ordered-Surface Edge Review',
        '',
        f"- Source: `{report['source']}`",
        f"- Surface count: `{len(report['surfaces'])}`",
        '',
    ]
    for surface in report['surfaces']:
        lines.extend([
            f"## `{surface['surface_id']}`",
            '',
            f"- sampled_low32: `{surface['sampled_low32']}`",
            f"- slot_count: `{surface['slot_count']}`",
            f"- unresolved_count: `{surface['unresolved_count']}`",
            f"- edge_only: `{1 if surface['edge_only'] else 0}`",
            '',
        ])
        if not surface['unresolved_slots']:
            lines.append('- no unresolved slots')
            lines.append('')
            continue
        lines.extend([
            '| seq | class | upload key | prev replacement | next replacement |',
            '|---:|---|---|---|---|',
        ])
        for row in surface['unresolved_slots']:
            lines.append(
                f"| `{row['sequence_index']}` | `{row['position_class']}` | `{row['upload_key']}` | `{row.get('prev_replacement_id') or '-'}` | `{row.get('next_replacement_id') or '-'}` |"
            )
        lines.append('')
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description='Classify unresolved ordered-surface slots as edge-only or interior.')
    parser.add_argument('--surface-package', required=True)
    parser.add_argument('--output-json')
    parser.add_argument('--output-markdown')
    args = parser.parse_args()

    path = Path(args.surface_package)
    package = load_json(path)
    report = {
        'source': str(path),
        'surfaces': [classify_unresolved_slots(surface_entry['surface']) for surface_entry in package.get('surfaces', [])],
    }
    serialized = json.dumps(report, indent=2) + '\n'
    if args.output_json:
        out = Path(args.output_json)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(serialized)
    else:
        print(serialized, end='')
    if args.output_markdown:
        out = Path(args.output_markdown)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(render_markdown(report) + '\n')


if __name__ == '__main__':
    main()
