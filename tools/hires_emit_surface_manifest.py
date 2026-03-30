#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text())


def emit_manifest(surface_map: dict):
    sequences = surface_map['surface_map']
    dims = None
    for row in sequences:
        if row.get('dims'):
            dims = row['dims']
            break
    replacement_ids = []
    for row in sequences:
        rid = row.get('replacement_id')
        if rid and rid not in replacement_ids:
            replacement_ids.append(rid)
    return {
        'surface_id': f"surface-{surface_map['sampled_low32']}",
        'sampled_low32': surface_map['sampled_low32'],
        'shape_hint': surface_map.get('shape_hint'),
        'slot_count': len(sequences),
        'surface_tile_dims': dims,
        'replacement_ids': replacement_ids,
        'unresolved_sequences': surface_map.get('unresolved_sequences', []),
        'slots': [
            {
                'sequence_index': row['sequence_index'],
                'replacement_id': row.get('replacement_id'),
                'upload_key': row['upload_key'],
                'addr_hex': row.get('addr_hex'),
            }
            for row in sequences
        ],
    }


def render_markdown(manifest: dict):
    lines = [
        '# Ordered Surface Manifest',
        '',
        f"- surface_id: `{manifest['surface_id']}`",
        f"- sampled_low32: `{manifest['sampled_low32']}`",
        f"- shape_hint: `{manifest.get('shape_hint')}`",
        f"- slot_count: `{manifest['slot_count']}`",
        f"- tile_dims: `{manifest['surface_tile_dims']}`",
        f"- unique replacements: `{len(manifest['replacement_ids'])}`",
        f"- unresolved sequences: `{len(manifest['unresolved_sequences'])}`",
        '',
        '## Slots',
        '',
        '| seq | upload key | replacement |',
        '|---:|---|---|',
    ]
    for row in manifest['slots']:
        lines.append(f"| `{row['sequence_index']}` | `{row['upload_key']}` | `{row.get('replacement_id') or '-'}` |")
    lines.append('')
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description='Emit an ordered-surface manifest from a title surface map.')
    parser.add_argument('--map', required=True)
    parser.add_argument('--output-json')
    parser.add_argument('--output-markdown')
    args = parser.parse_args()

    surface_map = load_json(Path(args.map))
    manifest = emit_manifest(surface_map)
    serialized = json.dumps(manifest, indent=2) + '\n'
    if args.output_json:
        output_json = Path(args.output_json)
        output_json.parent.mkdir(parents=True, exist_ok=True)
        output_json.write_text(serialized)
    else:
        print(serialized, end='')
    if args.output_markdown:
        output_markdown = Path(args.output_markdown)
        output_markdown.parent.mkdir(parents=True, exist_ok=True)
        output_markdown.write_text(render_markdown(manifest))


if __name__ == '__main__':
    main()
