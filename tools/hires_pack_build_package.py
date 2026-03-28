#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

from hires_pack_emit_binary_package import emit_binary_package
from hires_pack_emit_loader_manifest import build_loader_manifest
from hires_pack_materialize_package import materialize_package


def load_json(path: Path):
    return json.loads(path.read_text())


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
        'source_input_path': ' + '.join(sources),
        'binding_count': len(merged_bindings),
        'unresolved_count': len(merged_unresolved),
        'bindings': sorted(merged_bindings.values(), key=lambda item: item.get('policy_key') or ''),
        'unresolved_transport_cases': sorted(merged_unresolved.values(), key=lambda item: item.get('policy_key') or ''),
    }


def main():
    parser = argparse.ArgumentParser(description='Merge canonical hi-res binding sets and emit a runtime-ready package.')
    parser.add_argument('--bindings', action='append', required=True, help='Bindings JSON path. Pass multiple times to merge.')
    parser.add_argument('--output-dir', required=True, help='Output directory for merged bindings, loader manifest, package dir, and .phrb.')
    parser.add_argument('--package-name', default='package.phrb', help='Binary package filename relative to output-dir.')
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    binding_payloads = [(Path(path), load_json(Path(path))) for path in args.bindings]
    merged = merge_bindings(binding_payloads)

    bindings_path = output_dir / 'bindings.json'
    bindings_path.write_text(json.dumps(merged, indent=2) + '\n')

    loader_manifest = build_loader_manifest(merged, bindings_path)
    loader_manifest_path = output_dir / 'loader-manifest.json'
    loader_manifest_path.write_text(json.dumps(loader_manifest, indent=2) + '\n')

    package_dir = output_dir / 'package'
    package_manifest = materialize_package(loader_manifest_path, package_dir)
    binary_path = output_dir / args.package_name
    binary_result = emit_binary_package(package_dir, binary_path)

    result = {
        'bindings_path': str(bindings_path),
        'loader_manifest_path': str(loader_manifest_path),
        'package_dir': str(package_dir),
        'package_manifest_record_count': package_manifest.get('record_count', 0),
        'binary_package': binary_result,
    }
    sys.stdout.write(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
