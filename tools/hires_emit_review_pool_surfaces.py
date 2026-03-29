#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

from hires_pack_emit_proxy_bindings import load_policy


def load_json(path: Path):
    return json.loads(path.read_text())


def resolve_review_pool_keys(policy_data, selected_keys, group_keys):
    review_pool_policy = policy_data.get('transport_review_pools', {}) if policy_data else {}
    review_pool_groups = policy_data.get('transport_review_pool_groups', {}) if policy_data else {}
    resolved = []
    seen = set()

    unknown_group_keys = [key for key in (group_keys or []) if key not in review_pool_groups]
    if unknown_group_keys:
        raise SystemExit(f'unknown --review-pool-group-key values: {unknown_group_keys}')

    unknown_keys = [key for key in (selected_keys or []) if key not in review_pool_policy]
    if unknown_keys:
        raise SystemExit(f'unknown --review-pool-key values: {unknown_keys}')

    for policy_key in selected_keys or []:
        if policy_key not in seen:
            resolved.append(policy_key)
            seen.add(policy_key)

    for group_key in group_keys or []:
        for policy_key in review_pool_groups[group_key].get('review_pool_keys', []):
            if policy_key not in review_pool_policy:
                raise SystemExit(
                    f'review-pool group {group_key} references unknown policy key {policy_key}'
                )
            if policy_key not in seen:
                resolved.append(policy_key)
                seen.add(policy_key)
    return resolved


def review_group_index(review: dict):
    groups = {}
    for group in review.get('groups', []):
        signature = group.get('signature', {})
        sampled_low32 = signature.get('sampled_low32')
        formatsize = signature.get('formatsize')
        if sampled_low32 is not None and formatsize is not None:
            groups[(sampled_low32, int(formatsize))] = group
    return groups


def selected_candidate(group: dict, replacement_id: str):
    matches = [c for c in group.get('transport_candidates', []) if c.get('replacement_id') == replacement_id]
    if len(matches) != 1:
        raise SystemExit(
            f'selected_replacement_id {replacement_id} matched {len(matches)} candidates '
            f'for sampled_low32 {group.get("signature", {}).get("sampled_low32")}'
        )
    return matches[0]


def canonical_surface_manifest(policy_key: str, record: dict, group: dict):
    canonical_identity = dict(group.get('canonical_identity', {}))
    if not canonical_identity:
        raise SystemExit(f'{policy_key} is missing canonical_identity in review group')
    selected_replacement_id = record.get('selected_replacement_id')
    if not selected_replacement_id:
        candidates = list(group.get('transport_candidates', []))
        if len(candidates) != 1:
            raise SystemExit(
                f'{policy_key} is missing selected_replacement_id and review group has {len(candidates)} candidates'
            )
        selected_replacement_id = candidates[0]['replacement_id']
    candidate = selected_candidate(group, selected_replacement_id)
    selector_mode = record.get('selector_mode', 'legacy')
    selector_checksum64 = candidate['checksum64'] if selector_mode == 'legacy' else '0000000000000000'
    return {
        'surface_id': policy_key,
        'sampled_low32': canonical_identity.get('sampled_low32'),
        'slot_count': 1,
        'surface_tile_dims': canonical_identity.get('wh'),
        'replacement_ids': [selected_replacement_id],
        'unresolved_sequences': [],
        'selector_mode': selector_mode,
        'slots': [
            {
                'sequence_index': 0,
                'replacement_id': selected_replacement_id,
                'upload_key': selector_checksum64.lower(),
                'addr_hex': canonical_identity.get('off_hex') or f"0x{int(canonical_identity.get('off', 0)):x}",
            }
        ],
        'source_policy_status': record.get('status'),
        'source_policy_key': policy_key,
        'source_group_signature': group.get('signature', {}),
    }


def render_markdown(package: dict):
    lines = [
        '# Review-Pool Surface Package',
        '',
        f"- review: `{package['review']}`",
        f"- surface_count: `{package['surface_count']}`",
        '',
    ]
    for surface_entry in package['surfaces']:
        surface = surface_entry['surface']
        slot = surface['slots'][0]
        lines.extend([
            f"## {surface['surface_id']}",
            '',
            f"- sampled_low32: `{surface['sampled_low32']}`",
            f"- tile_dims: `{surface['surface_tile_dims']}`",
            f"- replacement_id: `{slot['replacement_id']}`",
            f"- selector_checksum64: `{slot['upload_key']}`",
            f"- selector_mode: `{surface.get('selector_mode')}`",
            '',
        ])
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(
        description='Emit a phrs-surface-package-v1 from selected review-pool keys or group keys.'
    )
    parser.add_argument('--review', required=True)
    parser.add_argument('--policy', required=True)
    parser.add_argument('--review-pool-key', action='append')
    parser.add_argument('--review-pool-group-key', action='append')
    parser.add_argument('--output-json', required=True)
    parser.add_argument('--output-markdown')
    args = parser.parse_args()

    review_path = Path(args.review)
    policy_path = Path(args.policy)
    review = load_json(review_path)
    policy_data = load_policy(policy_path)
    review_pool_policy = policy_data.get('transport_review_pools', {}) if policy_data else {}
    group_index = review_group_index(review)
    resolved_keys = resolve_review_pool_keys(policy_data, args.review_pool_key, args.review_pool_group_key)
    if not resolved_keys:
        raise SystemExit('at least one --review-pool-key or --review-pool-group-key is required')

    surfaces = []
    for policy_key in resolved_keys:
        record = review_pool_policy[policy_key]
        sampled_low32 = record.get('sampled_low32')
        formatsize = int(record.get('formatsize'))
        group = group_index.get((sampled_low32, formatsize))
        if group is None:
            raise SystemExit(
                f'no review group found for policy {policy_key} sampled_low32={sampled_low32} formatsize={formatsize}'
            )
        surfaces.append({'surface': canonical_surface_manifest(policy_key, record, group), 'assets': {}})

    package = {
        'format': 'phrs-surface-package-v1',
        'review': str(review_path),
        'surface_count': len(surfaces),
        'surfaces': surfaces,
        'source_policy_path': str(policy_path),
        'resolved_review_pool_keys': resolved_keys,
    }
    output_json = Path(args.output_json)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(package, indent=2) + '\n')
    if args.output_markdown:
        output_markdown = Path(args.output_markdown)
        output_markdown.parent.mkdir(parents=True, exist_ok=True)
        output_markdown.write_text(render_markdown(package) + '\n')
    else:
        sys.stdout.write(json.dumps(package, indent=2) + '\n')


if __name__ == '__main__':
    main()
