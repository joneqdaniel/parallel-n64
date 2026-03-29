#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

from PIL import Image

from hires_pack_common import decode_entry_rgba8, parse_cache_entries


def load_json(path: Path):
    return json.loads(path.read_text())


def review_candidates(review: dict):
    by_id = {}
    for group in review.get('groups', []):
        for candidate in group.get('transport_candidates', []):
            by_id[candidate['replacement_id']] = candidate
    return by_id


def main():
    parser = argparse.ArgumentParser(description='Build a stitched preview from an ordered title surface map.')
    parser.add_argument('--map', required=True)
    parser.add_argument('--review', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--missing-color', default='00000000', help='RGBA hex for unresolved slots, default transparent black')
    args = parser.parse_args()

    surface_map = load_json(Path(args.map))
    review = load_json(Path(args.review))
    cache_path = Path(review['cache'])
    cache_entries = parse_cache_entries(cache_path)
    entries_by_id = {f"legacy-{entry['texture_crc']:08x}-{entry['palette_crc']:08x}-fs{entry['formatsize']}-{entry['width']}x{entry['height']}": entry for entry in cache_entries}
    candidates_by_id = review_candidates(review)

    rows = surface_map['surface_map']
    sample_dims = None
    for row in rows:
        if row.get('dims'):
            w, h = row['dims'].split('x')
            sample_dims = (int(w), int(h))
            break
    if sample_dims is None:
        raise SystemExit('no mapped dims found in surface map')
    width, height = sample_dims
    out = Image.new('RGBA', (width, height * len(rows)))
    missing_rgba = bytes.fromhex(args.missing_color)
    missing_tile = Image.new('RGBA', (width, height), tuple(missing_rgba))

    for idx, row in enumerate(rows):
        y = idx * height
        replacement_id = row.get('replacement_id')
        if not replacement_id:
            out.paste(missing_tile, (0, y))
            continue
        entry = entries_by_id.get(replacement_id)
        if entry is None:
            raise SystemExit(f'missing cache entry for {replacement_id}')
        rgba = decode_entry_rgba8(cache_path, entry)
        tile = Image.frombytes('RGBA', (entry['width'], entry['height']), rgba)
        out.paste(tile, (0, y))

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    out.save(output)


if __name__ == '__main__':
    main()
