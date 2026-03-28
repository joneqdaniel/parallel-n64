#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path


def load_subset(path: Path):
    data = json.loads(path.read_text())
    if 'canonical_projection' not in data:
        raise SystemExit('Subset file is missing canonical_projection. Re-emit with updated hires_pack_emit_subset.py.')
    return data


def format_markdown(data):
    subset = data['imported_subset']
    projection = data['canonical_projection']
    lines = []
    lines.append('# Hi-Res Legacy vs Canonical View')
    lines.append('')
    lines.append(f"- Bundle: `{data['bundle_path']}`")
    lines.append(f"- Requested policy keys: `{', '.join(data.get('requested_policy_keys', [])) or 'all'}`")
    lines.append(f"- Legacy links: `{projection['legacy_link_count']}`")
    lines.append(f"- Canonical sampled records: `{projection['canonical_record_count']}`")
    lines.append('')
    lines.append('## Legacy Families')
    lines.append('')
    if not projection['legacy_links']:
        lines.append('- None')
    for link in projection['legacy_links']:
        lines.append(f"- `{link['policy_key']}`")
        lines.append(f"  - family_type: `{link['family_type']}`")
        if link.get('kind'):
            lines.append(f"  - kind: `{link['kind']}`")
        if link.get('reason'):
            lines.append(f"  - reason: `{link['reason']}`")
        lines.append(f"  - status: `{link.get('status')}`")
        lines.append(f"  - selection_reason: `{link.get('selection_reason')}`")
        lines.append(f"  - candidate_replacement_count: `{len(link.get('candidate_replacement_ids', []))}`")
        lines.append(f"  - canonical_sampled_object_ids: `{', '.join(link.get('canonical_sampled_object_ids', [])) or 'none'}`")
    lines.append('')
    lines.append('## Canonical Sampled Objects')
    lines.append('')
    if not projection['canonical_records']:
        lines.append('- None')
    for record in projection['canonical_records']:
        lines.append(f"- `{record['sampled_object_id']}`")
        lines.append(
            f"  - draw=`{record.get('draw_class')}` cycle=`{record.get('cycle')}` fmt=`{record.get('fmt')}` siz=`{record.get('siz')}` off=`{record.get('off')}` stride=`{record.get('stride')}` wh=`{record.get('wh')}` fs=`{record.get('formatsize')}`"
        )
        lines.append(
            f"  - sampled_low32=`{record.get('sampled_low32')}` entry_pcrc=`{record.get('sampled_entry_pcrc')}` sparse_pcrc=`{record.get('sampled_sparse_pcrc')}` runtime_ready=`{int(bool(record.get('runtime_ready')))}` authority=`{record.get('evidence_authority')}`"
        )
        lines.append(
            f"  - pack_exact_entry_hit=`{int(bool(record.get('pack_exact_entry_hit')))}` pack_exact_sparse_hit=`{int(bool(record.get('pack_exact_sparse_hit')))}` pack_family_available=`{int(bool(record.get('pack_family_available')))}`"
        )
        if record.get('runtime_proxy_count'):
            proxy_ids = ', '.join(proxy.get('sampled_object_id') for proxy in record.get('runtime_proxy_candidates', []))
            lines.append(
                f"  - runtime_proxy_count=`{record.get('runtime_proxy_count')}` proxy_unique=`{int(bool(record.get('runtime_proxy_unique')))}` proxy_identity_mismatch=`{int(bool(record.get('runtime_proxy_identity_mismatch')))}`"
            )
            lines.append(f"  - runtime_proxy_candidates: `{proxy_ids or 'none'}`")
        lines.append(f"  - linked_policy_keys: `{', '.join(record.get('linked_policy_keys', [])) or 'none'}`")
        lines.append(f"  - linked_replacement_ids: `{', '.join(record.get('linked_replacement_ids', [])) or 'none'}`")
        transport_candidates = record.get('transport_candidates', [])
        lines.append(f"  - transport_candidate_count: `{len(transport_candidates)}`")
        if transport_candidates:
            for candidate in transport_candidates:
                asset = candidate.get('replacement_asset', {})
                dims = f"{asset.get('width')}x{asset.get('height')}" if asset else 'unknown'
                palette_crc = (candidate.get('source') or {}).get('legacy_palette_crc') or 'unknown'
                lines.append(
                    f"    - `{candidate.get('replacement_id')}` palette=`{palette_crc}` dims=`{dims}` variant_group=`{candidate.get('variant_group_id')}`"
                )
        def format_upload_items(items):
            parts = []
            for item in items:
                value = item.get('value')
                count = item.get('count')
                parts.append(f"{value}x{count}" if count is not None else str(value))
            return ', '.join(parts) or 'none'

        upload_low32s = format_upload_items(record.get('upload_low32s', []))
        upload_pcrcs = format_upload_items(record.get('upload_pcrcs', []))
        lines.append(f"  - upload_low32s: `{upload_low32s}`")
        lines.append(f"  - upload_pcrcs: `{upload_pcrcs}`")
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description='Compare legacy family view against canonical sampled-object view for an emitted subset.')
    parser.add_argument('--subset', required=True, help='Path to emitted subset JSON.')
    parser.add_argument('--format', choices=('json', 'markdown'), default='markdown')
    parser.add_argument('--output', help='Optional output path.')
    args = parser.parse_args()

    data = load_subset(Path(args.subset))
    if args.format == 'json':
        serialized = json.dumps(data['canonical_projection'], indent=2) + '\n'
    else:
        serialized = format_markdown(data)

    if args.output:
        Path(args.output).write_text(serialized)
    else:
        sys.stdout.write(serialized)


if __name__ == '__main__':
    main()
