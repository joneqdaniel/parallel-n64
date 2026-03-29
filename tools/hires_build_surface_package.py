#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path

from hires_pack_common import decode_entry_rgba8, parse_cache_entries


def load_json(path: Path):
    return json.loads(path.read_text())


def candidate_index(review: dict):
    index = {}
    for group in review.get('groups', []):
        for candidate in group.get('transport_candidates', []):
            index[candidate['replacement_id']] = candidate
    return index


def cache_index(cache_path: Path):
    entries = parse_cache_entries(cache_path)
    return {
        f"legacy-{entry['texture_crc']:08x}-{entry['palette_crc']:08x}-fs{entry['formatsize']}-{entry['width']}x{entry['height']}": entry
        for entry in entries
    }


def materialize_asset(cache_path: Path, entry: dict, out_dir: Path):
    rgba = decode_entry_rgba8(cache_path, entry)
    asset_name = f"{entry['texture_crc']:08x}-{entry['palette_crc']:08x}-{entry['width']}x{entry['height']}.rgba"
    asset_path = out_dir / asset_name
    asset_path.write_bytes(rgba)
    return {
        'asset_name': asset_name,
        'width': entry['width'],
        'height': entry['height'],
        'pixel_sha256': hashlib.sha256(rgba).hexdigest(),
        'byte_size': len(rgba),
    }


def build_surface(surface_manifest: dict, review: dict, assets_dir: Path):
    cache_path = Path(review['cache'])
    candidates = candidate_index(review)
    entries = cache_index(cache_path)
    assets = {}
    for replacement_id in surface_manifest['replacement_ids']:
        entry = entries.get(replacement_id)
        if entry is None:
            raise SystemExit(f'missing cache entry for {replacement_id}')
        assets[replacement_id] = materialize_asset(cache_path, entry, assets_dir)
    return {
        'surface': surface_manifest,
        'assets': assets,
    }


def main():
    parser = argparse.ArgumentParser(description='Build a tool-side ordered-surface package from surface manifests.')
    parser.add_argument('--review', required=True)
    parser.add_argument('--manifest', action='append', required=True)
    parser.add_argument('--output-dir', required=True)
    args = parser.parse_args()

    review = load_json(Path(args.review))
    output_dir = Path(args.output_dir)
    assets_dir = output_dir / 'assets'
    assets_dir.mkdir(parents=True, exist_ok=True)

    surfaces = []
    for manifest_path in args.manifest:
        manifest = load_json(Path(manifest_path))
        surfaces.append(build_surface(manifest, review, assets_dir))

    package = {
        'format': 'phrs-surface-package-v1',
        'review': args.review,
        'surface_count': len(surfaces),
        'surfaces': surfaces,
    }
    (output_dir / 'surface-package.json').write_text(json.dumps(package, indent=2) + '\n')


if __name__ == '__main__':
    main()
