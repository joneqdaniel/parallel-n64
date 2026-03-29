#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

from hires_compile_surface_package import compile_surface_package
from hires_pack_emit_binary_package import emit_binary_package
from hires_pack_emit_loader_manifest import build_loader_manifest
from hires_pack_emit_probe_pool_binding import build_binding as build_review_pool_binding
from hires_pack_emit_proxy_bindings import build_proxy_bindings, load_policy
from hires_pack_materialize_package import materialize_package


def load_binding_payload(path: Path):
    data = json.loads(path.read_text())
    required = {"schema_version", "bindings", "unresolved_transport_cases"}
    missing = required.difference(data)
    if missing:
        raise SystemExit(f'binding input {path} is missing keys: {sorted(missing)}')
    return data


def build_review_pool_bindings(review_paths, policy_data, selected_keys):
    review_pool_policy = policy_data.get('transport_review_pools', {}) if policy_data else {}
    selected_keys = list(selected_keys or [])
    if not review_pool_policy or not selected_keys:
        return {
            'schema_version': 1,
            'source_input_path': '',
            'binding_count': 0,
            'unresolved_count': 0,
            'bindings': [],
            'unresolved_transport_cases': [],
        }

    review_docs = [(path, json.loads(path.read_text())) for path in review_paths]
    bindings = []
    unknown_keys = [key for key in selected_keys if key not in review_pool_policy]
    if unknown_keys:
        raise SystemExit(f'unknown --review-pool-key values: {unknown_keys}')

    for policy_key in selected_keys:
        record = review_pool_policy[policy_key]
        sampled_low32 = record.get('sampled_low32')
        formatsize = record.get('formatsize')
        max_candidates = record.get('max_candidates')
        selected_replacement_id = record.get('selected_replacement_id')
        selector_mode = record.get('selector_mode', 'legacy')
        if not sampled_low32:
            raise SystemExit(f'review-pool policy {policy_key} is missing sampled_low32')

        matched_review = None
        for review_path, review in review_docs:
            for group in review.get('groups', []):
                signature = group.get('signature', {})
                if signature.get('sampled_low32') != sampled_low32:
                    continue
                if formatsize is not None and int(signature.get('formatsize', -1)) != int(formatsize):
                    continue
                matched_review = (review_path, review)
                break
            if matched_review is not None:
                break

        if matched_review is None:
            raise SystemExit(f'no review group found for policy {policy_key} sampled_low32={sampled_low32} formatsize={formatsize}')

        review_path, review = matched_review
        emitted = build_review_pool_binding(review, sampled_low32, max_candidates, selected_replacement_id, selector_mode)
        binding = emitted['bindings'][0]
        binding['policy_key'] = policy_key
        binding['family_type'] = 'policy-review-transport-pool'
        binding['status'] = record.get('status') or ('selected-review-candidate' if selected_replacement_id else 'selected-pool')
        binding['selection_reason'] = record.get('justification') or ('policy-selected-review-candidate' if selected_replacement_id else 'policy-review-transport-pool')
        binding['transport_policy'] = record
        binding['review_source_path'] = str(review_path)
        bindings.append(binding)

    return {
        'schema_version': 1,
        'source_input_path': ' + '.join(str(path) for path in review_paths),
        'binding_count': len(bindings),
        'unresolved_count': 0,
        'bindings': bindings,
        'unresolved_transport_cases': [],
    }


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
        description='Build a selected canonical hi-res package directly from imported index/subset inputs, ordered surfaces, and transport policy.'
    )
    parser.add_argument('--input', action='append', help='Path to imported_index or imported_subset JSON. Pass multiple times to merge sources.')
    parser.add_argument('--bindings-input', action='append', help='Path to an existing bindings.json payload. Pass multiple times to extend a selected package.')
    parser.add_argument('--surface-package-input', action='append', help='Path to a phrs-surface-package-v1 JSON. Pass multiple times to fold ordered surfaces into the build.')
    parser.add_argument('--review-input', action='append', help='Path to sampled transport review JSON. Pass multiple times to provide transport-pool review sources.')
    parser.add_argument('--review-pool-key', action='append', help='Policy key from transport_review_pools to include in this package build. Pass multiple times.')
    parser.add_argument('--policy', required=True, help='Transport policy JSON path.')
    parser.add_argument('--output-dir', required=True, help='Output directory for bindings, manifest, package dir, and binary package.')
    parser.add_argument('--package-name', default='package.phrb', help='Binary package filename relative to output-dir.')
    parser.add_argument('--allow-unresolved', action='store_true', help='Allow unresolved transport cases in the emitted binding set.')
    args = parser.parse_args()

    input_paths = [Path(path) for path in (args.input or [])]
    bindings_input_paths = [Path(path) for path in (args.bindings_input or [])]
    surface_package_input_paths = [Path(path) for path in (args.surface_package_input or [])]
    review_input_paths = [Path(path) for path in (args.review_input or [])]
    review_pool_keys = args.review_pool_key or []
    if review_pool_keys and not review_input_paths:
        raise SystemExit('--review-pool-key requires at least one --review-input')
    if not input_paths and not bindings_input_paths and not surface_package_input_paths and not review_input_paths:
        raise SystemExit('at least one --input, --bindings-input, --surface-package-input, or --review-input is required')

    policy_path = Path(args.policy)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    binding_payloads = []
    policy_data = load_policy(policy_path)
    for input_path in input_paths:
        binding_payloads.append((input_path, build_proxy_bindings(input_path, policy_data)))
    for bindings_input_path in bindings_input_paths:
        binding_payloads.append((bindings_input_path, load_binding_payload(bindings_input_path)))
    for surface_package_input_path in surface_package_input_paths:
        binding_payloads.append((surface_package_input_path, compile_surface_package(surface_package_input_path)))
    if review_input_paths and review_pool_keys:
        binding_payloads.append((Path('review-pools'), build_review_pool_bindings(review_input_paths, policy_data, review_pool_keys)))
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
        'bindings_input_paths': [str(path) for path in bindings_input_paths],
        'surface_package_input_paths': [str(path) for path in surface_package_input_paths],
        'review_input_paths': [str(path) for path in review_input_paths],
        'review_pool_keys': review_pool_keys,
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
