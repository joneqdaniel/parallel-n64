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


def group_index(review: dict):
    return {
        group.get('signature', {}).get('sampled_low32'): group
        for group in review.get('groups', [])
        if group.get('signature', {}).get('sampled_low32')
    }


def binding_index(binding_payload: dict):
    index = {}
    for binding in binding_payload.get('bindings', []):
        canonical = binding.get('canonical_identity', {})
        sampled_low32 = canonical.get('sampled_low32')
        if sampled_low32:
            index[str(sampled_low32).lower()] = binding
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


def build_surface(surface_manifest: dict, review: dict, assets_dir: Path, canonical_bindings: dict | None):
    cache_path = Path(review['cache'])
    candidates = candidate_index(review)
    groups = group_index(review)
    entries = cache_index(cache_path)
    assets = {}
    candidate_snapshots = []
    for replacement_id in surface_manifest['replacement_ids']:
        entry = entries.get(replacement_id)
        if entry is None:
            raise SystemExit(f'missing cache entry for {replacement_id}')
        candidate = candidates.get(replacement_id)
        if candidate is None:
            raise SystemExit(f'missing transport candidate for {replacement_id}')
        assets[replacement_id] = materialize_asset(cache_path, entry, assets_dir)
        candidate_snapshots.append({
            'replacement_id': replacement_id,
            'checksum64': candidate['checksum64'],
            'texture_crc': candidate['texture_crc'],
            'palette_crc': candidate['palette_crc'],
            'formatsize': candidate['formatsize'],
            'width': candidate['width'],
            'height': candidate['height'],
            'data_size': candidate['data_size'],
        })
    group = groups.get(surface_manifest['sampled_low32'])
    if group is None:
        raise SystemExit(f"missing sampled review group for {surface_manifest['sampled_low32']}")
    canonical_identity = dict(group.get('canonical_identity', {}))
    needs_canonical_fallback = any(
        canonical_identity.get(field) in (None, '')
        for field in ('fmt', 'siz', 'off', 'stride', 'wh', 'formatsize')
    )
    if needs_canonical_fallback and canonical_bindings:
        fallback = canonical_bindings.get(surface_manifest['sampled_low32'].lower())
        if fallback:
            fallback_identity = dict(fallback.get('canonical_identity', {}))
            for field, value in fallback_identity.items():
                if canonical_identity.get(field) in (None, '') and value not in (None, ''):
                    canonical_identity[field] = value

    return {
        'surface': surface_manifest,
        'assets': assets,
        'canonical_identity': canonical_identity,
        'candidate_snapshots': candidate_snapshots,
        'source_cache_path': str(cache_path),
    }


def main():
    parser = argparse.ArgumentParser(description='Build a tool-side ordered-surface package from surface manifests.')
    parser.add_argument('--review', required=True)
    parser.add_argument('--manifest', action='append', required=True)
    parser.add_argument('--canonical-bindings-input', help='Optional bindings.json to fill canonical_identity fields missing from sampled review data.')
    parser.add_argument('--output-dir', required=True)
    args = parser.parse_args()

    review = load_json(Path(args.review))
    canonical_bindings = None
    if args.canonical_bindings_input:
        canonical_bindings = binding_index(load_json(Path(args.canonical_bindings_input)))
    output_dir = Path(args.output_dir)
    assets_dir = output_dir / 'assets'
    assets_dir.mkdir(parents=True, exist_ok=True)

    surfaces = []
    for manifest_path in args.manifest:
        manifest = load_json(Path(manifest_path))
        surfaces.append(build_surface(manifest, review, assets_dir, canonical_bindings))

    package = {
        'format': 'phrs-surface-package-v2',
        'surface_count': len(surfaces),
        'bundle_path': review.get('bundle'),
        'provenance': {
            'review_path': args.review,
        },
        'surfaces': surfaces,
    }
    (output_dir / 'surface-package.json').write_text(json.dumps(package, indent=2) + '\n')


if __name__ == '__main__':
    main()
