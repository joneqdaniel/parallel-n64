#!/usr/bin/env python3
import argparse
import json
import struct
import sys
from pathlib import Path

MAGIC = b'PHRB'
VERSION = 2


def load_package_manifest(path: Path):
    return json.loads(path.read_text())


def parse_u32_identity(value):
    if value is None or value == '':
        return 0
    if isinstance(value, int):
        return value
    return int(str(value), 16)


def encode_string_table(strings):
    unique = []
    offsets = {}
    blob = bytearray()
    for value in strings:
        if value in offsets:
            continue
        offsets[value] = len(blob)
        blob.extend(value.encode('utf-8'))
        blob.append(0)
        unique.append(value)
    return bytes(blob), offsets


def emit_binary_package(package_dir: Path, output_path: Path):
    package_manifest = load_package_manifest(package_dir / 'package-manifest.json')
    records = package_manifest.get('records', [])
    asset_records = []
    strings = []

    for record_index, record in enumerate(records):
        strings.append(record['policy_key'])
        strings.append(record['sampled_object_id'])
        for candidate in record.get('asset_candidates', []):
            strings.extend([
                candidate['replacement_id'],
                candidate['legacy_source_path'],
                candidate['materialized_path'],
                candidate['variant_group_id'],
                candidate['legacy_checksum64'],
                candidate['legacy_texture_crc'],
                candidate['legacy_palette_crc'],
            ])
            asset_path = package_dir / candidate['materialized_path']
            rgba_path = asset_path.with_suffix('.rgba')
            # Store raw RGBA alongside the package for direct inspection and to avoid PNG parsing at runtime.
            if not rgba_path.exists():
                from PIL import Image
                img = Image.open(asset_path).convert('RGBA')
                rgba_path.write_bytes(img.tobytes())
            strings.append(str(rgba_path.relative_to(package_dir)))
            asset_records.append((record_index, candidate, rgba_path))

    string_blob, string_offsets = encode_string_table(strings)

    record_table = bytearray()
    asset_table = bytearray()
    blob_section = bytearray()

    for record in records:
        policy_key_off = string_offsets[record['policy_key']]
        sampled_object_id_off = string_offsets[record['sampled_object_id']]
        identity = record['canonical_identity']
        width_str, height_str = identity['wh'].split('x', 1)
        record_table.extend(struct.pack(
            '<IIIIIIIIIIIII',
            policy_key_off,
            sampled_object_id_off,
            int(identity['fmt']),
            int(identity['siz']),
            int(identity['off']),
            int(identity['stride']),
            int(width_str),
            int(height_str),
            int(identity['formatsize']),
            parse_u32_identity(identity.get('sampled_low32')),
            parse_u32_identity(identity.get('sampled_entry_pcrc')),
            parse_u32_identity(identity.get('sampled_sparse_pcrc')),
            record['asset_candidate_count'],
        ))

    for record_index, candidate, rgba_path in asset_records:
        rgba_bytes = rgba_path.read_bytes()
        blob_offset = len(blob_section)
        blob_section.extend(rgba_bytes)
        asset_table.extend(struct.pack(
            '<IIIIIIIIIIII',
            record_index,
            string_offsets[candidate['replacement_id']],
            string_offsets[candidate['legacy_source_path']],
            string_offsets[str(rgba_path.relative_to(package_dir))],
            string_offsets[candidate['variant_group_id']],
            int(candidate['width']),
            int(candidate['height']),
            int(candidate['texture_format']),
            int(candidate['pixel_type']),
            int(candidate['legacy_formatsize']),
            blob_offset,
            len(rgba_bytes),
        ))

    header_size = struct.calcsize('<4sIIIIIII')
    record_table_offset = header_size
    asset_table_offset = record_table_offset + len(record_table)
    string_table_offset = asset_table_offset + len(asset_table)
    blob_offset = string_table_offset + len(string_blob)

    with output_path.open('wb') as fp:
        fp.write(struct.pack(
            '<4sIIIIIII',
            MAGIC,
            VERSION,
            len(records),
            len(asset_records),
            record_table_offset,
            asset_table_offset,
            string_table_offset,
            blob_offset,
        ))
        fp.write(record_table)
        fp.write(asset_table)
        fp.write(string_blob)
        fp.write(blob_section)

    return {
        'output_path': str(output_path),
        'record_count': len(records),
        'asset_count': len(asset_records),
        'string_table_bytes': len(string_blob),
        'blob_bytes': len(blob_section),
    }


def main():
    parser = argparse.ArgumentParser(description='Emit a binary canonical hi-res package from a materialized package directory.')
    parser.add_argument('--package-dir', required=True, help='Path to materialized canonical package directory.')
    parser.add_argument('--output', required=True, help='Output binary package path.')
    args = parser.parse_args()

    result = emit_binary_package(Path(args.package_dir), Path(args.output))
    sys.stdout.write(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
