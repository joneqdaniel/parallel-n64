#!/usr/bin/env python3
import argparse
import json
import sys
from collections import Counter
from pathlib import Path


def load_index(path: Path):
    data = json.loads(path.read_text())
    if 'imported_index' in data:
        return data['imported_index']
    if 'imported_subset' in data:
        return data['imported_subset']
    raise SystemExit('Expected imported_index or imported_subset payload.')


def build_proxy_view(index):
    link_by_policy = {
        (link.get('policy_key') or link.get('alias_id')): link
        for link in index.get('legacy_transport_aliases', [])
    }
    proxies = {}

    for record in index.get('canonical_records', []):
        for proxy in record.get('runtime_proxy_candidates', []):
            proxy_id = proxy.get('sampled_object_id')
            if not proxy_id:
                continue
            group = proxies.setdefault(
                proxy_id,
                {
                    'proxy': proxy,
                    'source_hint_ids': [],
                    'source_policy_keys': [],
                    'source_hint_low32s': [],
                    'source_hint_authorities': [],
                    'transport_candidates': {},
                },
            )
            group['source_hint_ids'].append(record.get('sampled_object_id'))
            group['source_hint_low32s'].append(record.get('sampled_low32'))
            group['source_hint_authorities'].append(record.get('evidence_authority'))
            for policy_key in record.get('linked_policy_keys', []):
                if policy_key not in group['source_policy_keys']:
                    group['source_policy_keys'].append(policy_key)
            for candidate in record.get('transport_candidates', []):
                replacement_id = candidate.get('replacement_id')
                if not replacement_id:
                    continue
                group['transport_candidates'].setdefault(replacement_id, candidate)

    review = []
    for proxy_id, group in sorted(proxies.items()):
        dims_counter = Counter()
        palette_counter = Counter()
        policy_status_counter = Counter()
        suggested_groups = []
        for candidate in group['transport_candidates'].values():
            asset = candidate.get('replacement_asset', {})
            dims = f"{asset.get('width')}x{asset.get('height')}"
            dims_counter[dims] += 1
            palette_crc = (candidate.get('source') or {}).get('legacy_palette_crc')
            if palette_crc:
                palette_counter[palette_crc] += 1
        for policy_key in group['source_policy_keys']:
            link = link_by_policy.get(policy_key, {})
            status = link.get('status') or 'unknown'
            policy_status_counter[status] += 1
        review.append(
            {
                'proxy_sampled_object_id': proxy_id,
                'proxy_identity': proxy,
                'source_hint_count': len(group['source_hint_ids']),
                'source_hint_ids': sorted(group['source_hint_ids']),
                'source_hint_low32s': sorted(set(filter(None, group['source_hint_low32s']))),
                'source_policy_keys': sorted(group['source_policy_keys']),
                'source_policy_status_counts': dict(policy_status_counter),
                'transport_candidate_count': len(group['transport_candidates']),
                'transport_candidate_dims': [
                    {'dims': dims, 'count': count}
                    for dims, count in dims_counter.most_common()
                ],
                'transport_candidate_palette_count': len(palette_counter),
                'transport_candidates': sorted(group['transport_candidates'].values(), key=lambda item: item.get('replacement_id') or ''),
            }
        )
    return {
        'proxy_count': len(review),
        'proxy_groups': review,
    }


def format_markdown(review, source_path: Path):
    lines = []
    lines.append('# Hi-Res Proxy Review')
    lines.append('')
    lines.append(f'- Source: `{source_path}`')
    lines.append(f"- Proxy groups: `{review['proxy_count']}`")
    lines.append('')
    for group in review['proxy_groups']:
        proxy = group['proxy_identity']
        lines.append(f"- `{group['proxy_sampled_object_id']}`")
        lines.append(
            f"  - draw=`{proxy.get('draw_class')}` cycle=`{proxy.get('cycle')}` fs=`{proxy.get('formatsize')}` sampled_low32=`{proxy.get('sampled_low32')}` entry_pcrc=`{proxy.get('sampled_entry_pcrc')}` sparse_pcrc=`{proxy.get('sampled_sparse_pcrc')}`"
        )
        lines.append(f"  - source_hint_count: `{group['source_hint_count']}`")
        lines.append(f"  - source_hint_low32s: `{', '.join(group['source_hint_low32s']) or 'none'}`")
        lines.append(f"  - source_policy_keys: `{', '.join(group['source_policy_keys']) or 'none'}`")
        lines.append(f"  - transport_candidate_count: `{group['transport_candidate_count']}`")
        dims = ', '.join(f"{item['dims']} ({item['count']})" for item in group['transport_candidate_dims']) or 'none'
        lines.append(f"  - transport_candidate_dims: `{dims}`")
        for candidate in group['transport_candidates'][:12]:
            asset = candidate.get('replacement_asset', {})
            dims = f"{asset.get('width')}x{asset.get('height')}"
            palette_crc = (candidate.get('source') or {}).get('legacy_palette_crc') or 'unknown'
            lines.append(
                f"    - `{candidate.get('replacement_id')}` palette=`{palette_crc}` dims=`{dims}` variant_group=`{candidate.get('variant_group_id')}`"
            )
    lines.append('')
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description='Aggregate runtime-proxy-linked transport candidates from an imported index or subset.')
    parser.add_argument('--input', required=True, help='Path to imported_index or imported_subset JSON.')
    parser.add_argument('--format', choices=('json', 'markdown'), default='markdown')
    parser.add_argument('--output', help='Optional output path.')
    args = parser.parse_args()

    source_path = Path(args.input)
    review = build_proxy_view(load_index(source_path))
    serialized = json.dumps(review, indent=2) + '\n' if args.format == 'json' else format_markdown(review, source_path)
    if args.output:
        Path(args.output).write_text(serialized)
    else:
        sys.stdout.write(serialized)


if __name__ == '__main__':
    main()
