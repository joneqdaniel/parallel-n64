#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

from hires_pack_emit_binary_package import emit_binary_package
from hires_pack_emit_loader_manifest import build_loader_manifest
from hires_pack_emit_proxy_bindings import build_proxy_bindings, load_policy
from hires_pack_materialize_package import materialize_package


def merge_bindings(binding_payloads):
    merged_bindings = {}
    merged_unresolved = {}
    sources = []
    for path, data in binding_payloads:
        sources.append(str(path))
        for binding in data.get('bindings', []):
            merged_bindings[binding.get('policy_key')] = binding
        for unresolved in data.get('unresolved_transport_cases', []):
            merged_unresolved[unresolved.get('policy_key')] = unresolved
    for key in list(merged_unresolved):
        if key in merged_bindings:
            del merged_unresolved[key]
    return {
        'schema_version': 1,
        'source_input_paths': sources,
        'binding_count': len(merged_bindings),
        'unresolved_count': len(merged_unresolved),
        'bindings': sorted(merged_bindings.values(), key=lambda item: item.get('policy_key') or ''),
        'unresolved_transport_cases': sorted(merged_unresolved.values(), key=lambda item: item.get('policy_key') or ''),
    }


def main():
    parser = argparse.ArgumentParser(
        description='Build a selected canonical hi-res package directly from imported index/subset inputs and transport policy.'
    )
    parser.add_argument('--input', action='append', required=True, help='Path to imported_index or imported_subset JSON. Pass multiple times to merge sources.')
    parser.add_argument('--policy', required=True, help='Transport policy JSON path.')
    parser.add_argument('--output-dir', required=True, help='Output directory for bindings, manifest, package dir, and binary package.')
    parser.add_argument('--package-name', default='package.phrb', help='Binary package filename relative to output-dir.')
    parser.add_argument('--allow-unresolved', action='store_true', help='Allow unresolved transport cases in the emitted binding set.')
    args = parser.parse_args()

    input_paths = [Path(path) for path in args.input]
    policy_path = Path(args.policy)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    binding_payloads = []
    policy_data = load_policy(policy_path)
    for input_path in input_paths:
        binding_payloads.append((input_path, build_proxy_bindings(input_path, policy_data)))
    bindings = merge_bindings(binding_payloads)

    unresolved = bindings.get('unresolved_transport_cases', [])
    if unresolved and not args.allow_unresolved:
        unresolved_keys = [item.get('policy_key') for item in unresolved]
        raise SystemExit(
            'Selected package build still has unresolved transport cases. '
            'Pass --allow-unresolved to keep them in metadata only. '
            f'Unresolved: {unresolved_keys}'
        )

    bindings_path = output_dir / 'bindings.json'
    bindings_path.write_text(json.dumps(bindings, indent=2) + '\n')

    loader_manifest = build_loader_manifest(bindings, bindings_path)
    loader_manifest_path = output_dir / 'loader-manifest.json'
    loader_manifest_path.write_text(json.dumps(loader_manifest, indent=2) + '\n')

    package_dir = output_dir / 'package'
    package_manifest = materialize_package(loader_manifest_path, package_dir)
    binary_path = output_dir / args.package_name
    binary_result = emit_binary_package(package_dir, binary_path)

    result = {
        'input_paths': [str(path) for path in input_paths],
        'policy_path': str(policy_path),
        'bindings_path': str(bindings_path),
        'loader_manifest_path': str(loader_manifest_path),
        'package_dir': str(package_dir),
        'binding_count': bindings.get('binding_count', 0),
        'unresolved_count': len(unresolved),
        'package_manifest_record_count': package_manifest.get('record_count', 0),
        'binary_package': binary_result,
    }
    sys.stdout.write(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
