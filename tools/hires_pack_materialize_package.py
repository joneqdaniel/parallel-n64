#!/usr/bin/env python3
import argparse
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image

from hires_pack_common import decode_entry_rgba8, find_cache_entry, parse_cache_entries


def load_loader_manifest(path: Path):
    return json.loads(path.read_text())


def materialize_package(loader_manifest_path: Path, output_dir: Path):
    manifest = load_loader_manifest(loader_manifest_path)
    output_dir.mkdir(parents=True, exist_ok=True)
    assets_dir = output_dir / 'assets'
    assets_dir.mkdir(parents=True, exist_ok=True)

    cache_index = {}
    duplicate_groups = []

    def get_entries(cache_path_str):
        if cache_path_str not in cache_index:
            cache_index[cache_path_str] = parse_cache_entries(Path(cache_path_str))
        return cache_index[cache_path_str]

    package_records = []
    for record in manifest.get('records', []):
        emitted_candidates = []
        by_pixel_hash = {}
        for candidate in record.get('asset_candidates', []):
            cache_path = Path(candidate['legacy_source_path'])
            entries = get_entries(candidate['legacy_source_path'])
            checksum64 = int(candidate['legacy_checksum64'], 16)
            formatsize = int(candidate.get('legacy_formatsize') or 0)
            entry = find_cache_entry(entries, checksum64, formatsize)
            if entry is None:
                raise SystemExit(f"Missing cache entry for {candidate['replacement_id']}")
            rgba = decode_entry_rgba8(cache_path, entry)
            width = int(candidate['width'])
            height = int(candidate['height'])
            image = Image.frombytes('RGBA', (width, height), rgba)
            filename = f"{candidate['replacement_id']}.png"
            rel_path = Path('assets') / filename
            image.save(output_dir / rel_path)
            pixel_sha256 = hashlib.sha256(rgba).hexdigest()
            normalized = bytearray(rgba)
            for i in range(0, len(normalized), 4):
                if normalized[i + 3] == 0:
                    normalized[i + 0] = 0
                    normalized[i + 1] = 0
                    normalized[i + 2] = 0
            alpha_normalized_pixel_sha256 = hashlib.sha256(bytes(normalized)).hexdigest()
            emitted = {
                **candidate,
                'materialized_path': str(rel_path),
                'pixel_sha256': pixel_sha256,
                'alpha_normalized_pixel_sha256': alpha_normalized_pixel_sha256,
            }
            emitted_candidates.append(emitted)
            by_pixel_hash.setdefault(alpha_normalized_pixel_sha256, []).append(emitted['replacement_id'])
        duplicate_pixel_groups = [
            {
                'alpha_normalized_pixel_sha256': pixel_sha256,
                'replacement_ids': sorted(replacement_ids),
            }
            for pixel_sha256, replacement_ids in sorted(by_pixel_hash.items())
            if len(replacement_ids) > 1
        ]
        if duplicate_pixel_groups:
            duplicate_groups.append(
                {
                    'policy_key': record.get('policy_key'),
                    'sampled_object_id': record.get('sampled_object_id'),
                    'duplicate_pixel_groups': duplicate_pixel_groups,
                }
            )
        package_records.append(
            {
                'policy_key': record.get('policy_key'),
                'sampled_object_id': record.get('sampled_object_id'),
                'canonical_identity': record.get('canonical_identity', {}),
                'upload_low32s': record.get('upload_low32s', []),
                'upload_pcrcs': record.get('upload_pcrcs', []),
                'asset_candidate_count': len(emitted_candidates),
                'asset_candidates': emitted_candidates,
                'duplicate_pixel_group_count': len(duplicate_pixel_groups),
                'duplicate_pixel_groups': duplicate_pixel_groups,
            }
        )

    package_manifest = {
        'schema_version': 1,
        'source_loader_manifest_path': str(loader_manifest_path),
        'bundle_path': manifest.get('bundle_path'),
        'record_count': len(package_records),
        'records': package_records,
        'duplicate_record_count': len(duplicate_groups),
        'duplicate_groups': duplicate_groups,
        'unresolved_transport_cases': manifest.get('unresolved_transport_cases', []),
    }
    (output_dir / 'package-manifest.json').write_text(json.dumps(package_manifest, indent=2) + '\n')
    return package_manifest


def main():
    parser = argparse.ArgumentParser(description='Materialize a canonical hi-res package slice from a loader manifest.')
    parser.add_argument('--loader-manifest', required=True, help='Path to loader-oriented manifest JSON.')
    parser.add_argument('--output-dir', required=True, help='Output directory for the materialized package.')
    args = parser.parse_args()

    package_manifest = materialize_package(Path(args.loader_manifest), Path(args.output_dir))
    sys.stdout.write(json.dumps({
        'output_dir': args.output_dir,
        'record_count': package_manifest['record_count'],
        'unresolved_count': len(package_manifest.get('unresolved_transport_cases', [])),
    }, indent=2) + '\n')


if __name__ == '__main__':
    main()
