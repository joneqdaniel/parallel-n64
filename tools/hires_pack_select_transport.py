#!/usr/bin/env python3
import argparse
import json
import shutil
import sys
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text())


def merge_selections(selections_data, policy_data):
    merged = {}
    if selections_data:
        for policy_key, replacement_id in selections_data.items():
            merged[policy_key] = {
                'selected_replacement_id': replacement_id,
                'selection_source': 'selections',
            }
    if policy_data:
        for section in ('transport_families', 'transport_proxies'):
            for policy_key, record in policy_data.get(section, {}).items():
                replacement_id = record.get('selected_replacement_id')
                if not replacement_id:
                    continue
                merged[policy_key] = {
                    'selected_replacement_id': replacement_id,
                    'selection_source': 'policy',
                    'policy_record': record,
                }
    return merged


def narrow_package(package_dir: Path, output_dir: Path, selections: dict[str, dict], policy_path: Path | None):
    if output_dir.exists():
        shutil.rmtree(output_dir)
    shutil.copytree(package_dir, output_dir)

    manifest_path = output_dir / 'package-manifest.json'
    manifest = load_json(manifest_path)
    selected = []

    for record in manifest.get('records', []):
        policy_key = record.get('policy_key')
        selection = selections.get(policy_key)
        if not selection:
            continue
        replacement_id = selection['selected_replacement_id']
        candidates = record.get('asset_candidates', [])
        narrowed = [c for c in candidates if c.get('replacement_id') == replacement_id]
        if len(narrowed) != 1:
            raise SystemExit(f'Selection for {policy_key} did not resolve uniquely: {replacement_id}')
        record['asset_candidates'] = narrowed
        record['asset_candidate_count'] = 1
        record['duplicate_pixel_group_count'] = 0
        record['duplicate_pixel_groups'] = []
        if selection.get('policy_record'):
            record['transport_policy'] = selection['policy_record']
        selected.append({
            'policy_key': policy_key,
            'replacement_id': replacement_id,
            'selection_source': selection.get('selection_source', 'unknown'),
            'policy_status': selection.get('policy_record', {}).get('status') if selection.get('policy_record') else None,
        })

    manifest['transport_selection_count'] = len(selected)
    manifest['transport_selections'] = selected
    if policy_path is not None:
        manifest['transport_policy_source'] = str(policy_path)
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    return {
        'output_dir': str(output_dir),
        'selected_count': len(selected),
        'record_count': len(manifest.get('records', [])),
    }


def main():
    parser = argparse.ArgumentParser(description='Narrow a materialized canonical hi-res package to selected transport candidates.')
    parser.add_argument('--package-dir', required=True, help='Input materialized package directory.')
    parser.add_argument('--output-dir', required=True, help='Output directory for the narrowed package.')
    parser.add_argument('--selections', help='Optional JSON file mapping policy_key to replacement_id.')
    parser.add_argument('--policy', help='Optional transport-policy JSON file.')
    args = parser.parse_args()

    selections_data = load_json(Path(args.selections)) if args.selections else None
    policy_path = Path(args.policy) if args.policy else None
    policy_data = load_json(policy_path) if policy_path else None
    merged = merge_selections(selections_data, policy_data)
    if not merged:
        raise SystemExit('No transport selections were provided.')
    result = narrow_package(Path(args.package_dir), Path(args.output_dir), merged, policy_path)
    sys.stdout.write(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
