#!/usr/bin/env python3
import argparse
import json
import struct
import sys
from pathlib import Path

MAGIC = b'PHRB'
VERSION = 7
RECORD_FLAG_RUNTIME_READY = 1 << 0
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401
GL_RGBA8 = 0x8058


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


def _build_package_tables(package_manifest: dict,
                          asset_rgba_blobs: dict[str, bytes] | None = None,
                          asset_storage_mode: str = 'rgba'):
    records = package_manifest.get('records', [])
    asset_records = []
    strings = []
    asset_rgba_blobs = asset_rgba_blobs or {}

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
            asset_records.append({
                'record_index': record_index,
                'candidate': candidate,
            })

    string_blob, string_offsets = encode_string_table(strings)

    record_table = bytearray()
    asset_table = bytearray()
    blob_section_size = 0

    for record in records:
        policy_key_off = string_offsets[record['policy_key']]
        sampled_object_id_off = string_offsets[record['sampled_object_id']]
        identity = record['canonical_identity']
        width_str, height_str = identity['wh'].split('x', 1)
        record_flags = int(record.get('record_flags', 0) or 0)
        if record.get('runtime_ready', True):
            record_flags |= RECORD_FLAG_RUNTIME_READY
        record_table.extend(struct.pack(
            '<IIIIIIIIIIIIII',
            policy_key_off,
            sampled_object_id_off,
            record_flags,
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

    for asset_record in asset_records:
        record_index = asset_record['record_index']
        candidate = asset_record['candidate']
        rgba_rel_path = candidate['materialized_path']
        runtime_ready = bool(records[record_index].get('runtime_ready', True))
        if runtime_ready:
            if asset_storage_mode == 'legacy':
                blob_size = int(candidate.get('data_size') or 0)
                stored_format = int(candidate.get('format') or GL_RGBA8)
                stored_texture_format = int(candidate.get('texture_format') or GL_RGBA)
                stored_pixel_type = int(candidate.get('pixel_type') or GL_UNSIGNED_BYTE)
            else:
                rgba_bytes = asset_rgba_blobs.get(rgba_rel_path)
                if rgba_bytes is not None:
                    blob_size = len(rgba_bytes)
                else:
                    blob_size = int(candidate['width']) * int(candidate['height']) * 4
                stored_format = GL_RGBA8
                stored_texture_format = GL_RGBA
                stored_pixel_type = GL_UNSIGNED_BYTE
        else:
            blob_size = 0
            stored_format = int(candidate.get('format') or GL_RGBA8)
            stored_texture_format = int(candidate.get('texture_format') or GL_RGBA)
            stored_pixel_type = int(candidate.get('pixel_type') or GL_UNSIGNED_BYTE)
        blob_offset = blob_section_size
        blob_section_size += blob_size
        selector_value = candidate.get('selector_checksum64')
        selector_checksum64 = int(str(selector_value or '0'), 16)
        legacy_checksum64 = int(str(candidate.get('legacy_checksum64') or '0'), 16)
        asset_record['blob_offset'] = blob_offset
        asset_record['blob_size'] = blob_size
        asset_record['stored_format'] = stored_format
        asset_record['stored_texture_format'] = stored_texture_format
        asset_record['stored_pixel_type'] = stored_pixel_type
        asset_table.extend(struct.pack(
            '<IIIIIIIIIIIQQQQ',
            record_index,
            string_offsets[candidate['replacement_id']],
            string_offsets[candidate['legacy_source_path']],
            string_offsets[rgba_rel_path],
            string_offsets[candidate['variant_group_id']],
            int(candidate['width']),
            int(candidate['height']),
            stored_format,
            stored_texture_format,
            stored_pixel_type,
            int(candidate['legacy_formatsize']),
            selector_checksum64,
            legacy_checksum64,
            blob_offset,
            blob_size,
        ))

    header_size = struct.calcsize('<4sIIIIIII')
    record_table_offset = header_size
    asset_table_offset = record_table_offset + len(record_table)
    string_table_offset = asset_table_offset + len(asset_table)
    blob_offset = string_table_offset + len(string_blob)

    return {
        'records': records,
        'asset_records': asset_records,
        'string_blob': string_blob,
        'record_table': record_table,
        'asset_table': asset_table,
        'record_table_offset': record_table_offset,
        'asset_table_offset': asset_table_offset,
        'string_table_offset': string_table_offset,
        'blob_offset': blob_offset,
        'blob_bytes': blob_section_size,
    }


def emit_binary_package_from_manifest(package_manifest: dict,
                                      output_path: Path,
                                      asset_rgba_blobs: dict[str, bytes] | None = None,
                                      asset_blob_loader=None,
                                      asset_storage_mode: str = 'rgba'):
    package_tables = _build_package_tables(
        package_manifest,
        asset_rgba_blobs=asset_rgba_blobs,
        asset_storage_mode=asset_storage_mode,
    )
    records = package_tables['records']
    asset_records = package_tables['asset_records']
    string_blob = package_tables['string_blob']
    record_table = package_tables['record_table']
    asset_table = package_tables['asset_table']
    record_table_offset = package_tables['record_table_offset']
    asset_table_offset = package_tables['asset_table_offset']
    string_table_offset = package_tables['string_table_offset']
    blob_offset = package_tables['blob_offset']
    blob_bytes = package_tables['blob_bytes']

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
        asset_rgba_blobs = asset_rgba_blobs or {}
        for asset_record in asset_records:
            record_index = asset_record['record_index']
            candidate = asset_record['candidate']
            if not records[record_index].get('runtime_ready', True):
                continue
            blob_rel_path = candidate['materialized_path']
            blob_bytes_value = asset_rgba_blobs.get(blob_rel_path)
            if blob_bytes_value is None:
                if asset_blob_loader is None:
                    raise ValueError(f"Missing asset blob for materialized asset path: {blob_rel_path}")
                blob_bytes_value = asset_blob_loader(record_index, records[record_index], candidate)
            expected_size = int(asset_record['blob_size'])
            if len(blob_bytes_value) != expected_size:
                raise ValueError(
                    f"Unexpected asset blob size for {candidate['replacement_id']}: "
                    f"expected {expected_size}, got {len(blob_bytes_value)}"
                )
            fp.write(blob_bytes_value)

    return {
        'output_path': str(output_path),
        'record_count': len(records),
        'asset_count': len(asset_records),
        'string_table_bytes': len(string_blob),
        'blob_bytes': blob_bytes,
    }


def emit_binary_package(package_dir: Path, output_path: Path):
    package_manifest = load_package_manifest(package_dir / 'package-manifest.json')
    asset_rgba_blobs = {}

    for record in package_manifest.get('records', []):
        for candidate in record.get('asset_candidates', []):
            asset_path = package_dir / candidate['materialized_path']
            rgba_path = asset_path.with_suffix('.rgba')
            if rgba_path.exists():
                rgba_bytes = rgba_path.read_bytes()
                rgba_rel_path = str(rgba_path.relative_to(package_dir))
            else:
                from PIL import Image
                img = Image.open(asset_path).convert('RGBA')
                rgba_bytes = img.tobytes()
                rgba_path.write_bytes(rgba_bytes)
                rgba_rel_path = str(rgba_path.relative_to(package_dir))
            candidate['materialized_path'] = rgba_rel_path
            asset_rgba_blobs[rgba_rel_path] = rgba_bytes

    return emit_binary_package_from_manifest(package_manifest, output_path, asset_rgba_blobs, asset_storage_mode='rgba')


def main():
    parser = argparse.ArgumentParser(description='Emit a binary canonical hi-res package from a materialized package directory.')
    parser.add_argument('--package-dir', required=True, help='Path to materialized canonical package directory.')
    parser.add_argument('--output', required=True, help='Output binary package path.')
    args = parser.parse_args()

    result = emit_binary_package(Path(args.package_dir), Path(args.output))
    sys.stdout.write(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
