#!/usr/bin/env python3
import argparse
import json
import shutil
import sys
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text())


def narrow_package(package_dir: Path, output_dir: Path, selections: dict[str, str]):
    if output_dir.exists():
        shutil.rmtree(output_dir)
    shutil.copytree(package_dir, output_dir)

    manifest_path = output_dir / 'package-manifest.json'
    manifest = load_json(manifest_path)
    selected = []

    for record in manifest.get('records', []):
        policy_key = record.get('policy_key')
        replacement_id = selections.get(policy_key)
        if not replacement_id:
            continue
        candidates = record.get('asset_candidates', [])
        narrowed = [c for c in candidates if c.get('replacement_id') == replacement_id]
        if len(narrowed) != 1:
            raise SystemExit(f'Selection for {policy_key} did not resolve uniquely: {replacement_id}')
        record['asset_candidates'] = narrowed
        record['asset_candidate_count'] = 1
        record['duplicate_pixel_group_count'] = 0
        record['duplicate_pixel_groups'] = []
        selected.append({
            'policy_key': policy_key,
            'replacement_id': replacement_id,
        })

    manifest['transport_selection_count'] = len(selected)
    manifest['transport_selections'] = selected
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
    parser.add_argument('--selections', required=True, help='JSON file mapping policy_key to replacement_id.')
    args = parser.parse_args()

    selections = load_json(Path(args.selections))
    result = narrow_package(Path(args.package_dir), Path(args.output_dir), selections)
    sys.stdout.write(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
