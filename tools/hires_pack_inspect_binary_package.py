#!/usr/bin/env python3
import argparse
import json
import struct
import sys
from pathlib import Path

MAGIC = b'PHRB'
HEADER_STRUCT = struct.Struct('<4sIIIIIII')
RECORD_STRUCT_V1 = struct.Struct('<IIIIIIIIII')
RECORD_STRUCT_V2 = struct.Struct('<IIIIIIIIIIIII')
ASSET_STRUCT = struct.Struct('<IIIIIIIIIIII')


def read_c_string(blob, offset):
    end = blob.find(b'\0', offset)
    if end < 0:
        raise ValueError(f'Missing NUL terminator for string at offset {offset}')
    return blob[offset:end].decode('utf-8')


def inspect_binary_package(path: Path):
    data = path.read_bytes()
    if len(data) < HEADER_STRUCT.size:
        raise ValueError('Package too small for header.')
    magic, version, record_count, asset_count, record_off, asset_off, string_off, blob_off = HEADER_STRUCT.unpack_from(data, 0)
    if magic != MAGIC:
        raise ValueError(f'Unexpected magic: {magic!r}')
    if version not in (1, 2):
        raise ValueError(f'Unsupported version: {version}')

    string_blob = data[string_off:blob_off]
    records = []
    record_struct = RECORD_STRUCT_V2 if version >= 2 else RECORD_STRUCT_V1
    for i in range(record_count):
        off = record_off + i * record_struct.size
        if version >= 2:
            (policy_key_off, sampled_object_id_off, fmt, siz, tex_off, stride, width, height, formatsize, sampled_low32, sampled_entry_pcrc, sampled_sparse_pcrc, asset_candidate_count) = record_struct.unpack_from(data, off)
        else:
            (policy_key_off, sampled_object_id_off, fmt, siz, tex_off, stride, width, height, formatsize, asset_candidate_count) = record_struct.unpack_from(data, off)
            sampled_low32 = 0
            sampled_entry_pcrc = 0
            sampled_sparse_pcrc = 0
        records.append({
            'record_index': i,
            'policy_key': read_c_string(string_blob, policy_key_off),
            'sampled_object_id': read_c_string(string_blob, sampled_object_id_off),
            'canonical_identity': {
                'fmt': fmt,
                'siz': siz,
                'off': tex_off,
                'stride': stride,
                'wh': f'{width}x{height}',
                'formatsize': formatsize,
                'sampled_low32': sampled_low32,
                'sampled_entry_pcrc': sampled_entry_pcrc,
                'sampled_sparse_pcrc': sampled_sparse_pcrc,
            },
            'asset_candidate_count': asset_candidate_count,
            'asset_candidates': [],
        })

    for i in range(asset_count):
        off = asset_off + i * ASSET_STRUCT.size
        (record_index, replacement_id_off, legacy_source_path_off, rgba_rel_path_off, variant_group_id_off,
         width, height, texture_format, pixel_type, legacy_formatsize, rgba_blob_off, rgba_blob_size) = ASSET_STRUCT.unpack_from(data, off)
        records[record_index]['asset_candidates'].append({
            'replacement_id': read_c_string(string_blob, replacement_id_off),
            'legacy_source_path': read_c_string(string_blob, legacy_source_path_off),
            'rgba_rel_path': read_c_string(string_blob, rgba_rel_path_off),
            'variant_group_id': read_c_string(string_blob, variant_group_id_off),
            'width': width,
            'height': height,
            'texture_format': texture_format,
            'pixel_type': pixel_type,
            'legacy_formatsize': legacy_formatsize,
            'rgba_blob_offset': rgba_blob_off,
            'rgba_blob_size': rgba_blob_size,
        })

    return {
        'path': str(path),
        'version': version,
        'record_count': record_count,
        'asset_count': asset_count,
        'string_table_bytes': len(string_blob),
        'blob_bytes': len(data) - blob_off,
        'records': records,
    }


def main():
    parser = argparse.ArgumentParser(description='Inspect a PHRB binary hi-res package.')
    parser.add_argument('--package', required=True, help='Path to .phrb package.')
    parser.add_argument('--output', help='Optional output JSON path.')
    args = parser.parse_args()

    result = inspect_binary_package(Path(args.package))
    serialized = json.dumps(result, indent=2) + '\n'
    if args.output:
        Path(args.output).write_text(serialized)
    else:
        sys.stdout.write(serialized)


if __name__ == '__main__':
    main()
