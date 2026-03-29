#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text())


def main():
    parser = argparse.ArgumentParser(description='Expand one sampled-object binding with transport candidates from a sampled transport review.')
    parser.add_argument('--bindings', required=True, help='Input bindings.json path.')
    parser.add_argument('--review', required=True, help='Input sampled transport review.json path.')
    parser.add_argument('--sampled-low32', required=True, help='Target sampled_low32 to expand.')
    parser.add_argument('--output', required=True, help='Output bindings.json path.')
    args = parser.parse_args()

    bindings_path = Path(args.bindings)
    review_path = Path(args.review)
    output_path = Path(args.output)

    bindings = load_json(bindings_path)
    review = load_json(review_path)

    target_group = None
    for group in review.get('groups', []):
        signature = group.get('signature', {})
        if signature.get('sampled_low32') == args.sampled_low32:
            target_group = group
            break
    if target_group is None:
        raise SystemExit(f'sampled_low32 {args.sampled_low32} not found in review {review_path}')

    replacement_candidates = []
    for candidate in target_group.get('transport_candidates', []):
        replacement_candidates.append(
            {
                'replacement_id': candidate['replacement_id'],
                'source': {
                    'legacy_checksum64': candidate['checksum64'],
                    'legacy_texture_crc': candidate['texture_crc'],
                    'legacy_palette_crc': candidate['palette_crc'],
                    'legacy_formatsize': candidate['formatsize'],
                    'legacy_storage': 'hts',
                    'legacy_source_path': review['cache'],
                },
                'match': {
                    'exact_legacy_checksum64': candidate['checksum64'],
                    'texture_crc': candidate['texture_crc'],
                    'palette_crc': candidate['palette_crc'],
                    'formatsize': candidate['formatsize'],
                },
                'replacement_asset': {
                    'width': candidate['width'],
                    'height': candidate['height'],
                    'format': 2147516504,
                    'texture_format': 6408,
                    'pixel_type': 5121,
                    'data_size': candidate['data_size'],
                    'is_hires': True,
                },
                'variant_group_id': f"sampled-{args.sampled_low32}-{candidate['width']}x{candidate['height']}-{candidate['texture_crc']}",
            }
        )

    replaced = False
    for binding in bindings.get('bindings', []):
        sampled_object_id = binding.get('sampled_object_id', '')
        if f'low32{args.sampled_low32}' not in sampled_object_id:
            continue
        binding['status'] = 'transport-pool'
        binding['selection_reason'] = 'sampled-transport-review-pool'
        binding['transport_candidates'] = replacement_candidates
        replaced = True
    if not replaced:
        raise SystemExit(f'no binding found for sampled_low32 {args.sampled_low32} in {bindings_path}')

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(bindings, indent=2) + '\n')


if __name__ == '__main__':
    main()
