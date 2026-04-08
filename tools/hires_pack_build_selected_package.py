#!/usr/bin/env python3
import argparse
import copy
import json
import sys
from pathlib import Path

from hires_apply_surface_transport_policy import apply_surface_transport_policy, load_json as load_surface_policy_json
from hires_pack_apply_alias_group_review import apply_alias_group_reviews
from hires_compile_surface_package import compile_surface_package
from hires_pack_apply_duplicate_review import dedupe_loader_manifest
from hires_pack_emit_binary_package import emit_binary_package
from hires_pack_emit_loader_manifest import build_loader_manifest
from hires_pack_emit_probe_pool_binding import build_binding as build_review_pool_binding
from hires_pack_emit_proxy_bindings import build_proxy_bindings, load_policy
from hires_pack_emit_transport_bridge_bindings import build_transport_bridge_bindings
from hires_pack_materialize_package import materialize_package


def merge_unique_strings(*groups):
    merged = []
    seen = set()
    for group in groups:
        for value in group or []:
            if value in seen:
                continue
            seen.add(value)
            merged.append(value)
    return merged


def load_binding_payload(path: Path):
    data = json.loads(path.read_text())
    required = {"schema_version", "bindings", "unresolved_transport_cases"}
    missing = required.difference(data)
    if missing:
        raise SystemExit(f'binding input {path} is missing keys: {sorted(missing)}')
    return data


def load_review_profile(path: Path):
    data = json.loads(path.read_text())
    schema_version = int(data.get('schema_version') or 0)
    if schema_version != 1:
        raise SystemExit(f'review profile {path} must have schema_version=1')

    def resolve_paths(key):
        values = data.get(key) or []
        if not isinstance(values, list):
            raise SystemExit(f'review profile {path} key {key} must be a list')
        resolved = []
        for value in values:
            if not isinstance(value, str) or not value:
                raise SystemExit(f'review profile {path} key {key} must contain non-empty strings')
            candidate = Path(value)
            if not candidate.is_absolute():
                candidate = (path.parent / candidate).resolve()
            resolved.append(str(candidate))
        return resolved

    def read_string_list(key):
        values = data.get(key) or []
        if not isinstance(values, list):
            raise SystemExit(f'review profile {path} key {key} must be a list')
        for value in values:
            if not isinstance(value, str) or not value:
                raise SystemExit(f'review profile {path} key {key} must contain non-empty strings')
        return list(values)

    return {
        'path': str(path),
        'duplicate_review_paths': resolve_paths('duplicate_review_paths'),
        'alias_group_review_paths': resolve_paths('alias_group_review_paths'),
        'surface_transport_policy_paths': resolve_paths('surface_transport_policy_paths'),
        'review_input_paths': resolve_paths('review_input_paths'),
        'review_pool_keys': read_string_list('review_pool_keys'),
        'review_pool_group_keys': read_string_list('review_pool_group_keys'),
    }


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
        members = review_pool_groups[group_key].get('review_pool_keys', [])
        for policy_key in members:
            if policy_key not in review_pool_policy:
                raise SystemExit(
                    f'review-pool group {group_key} references unknown policy key {policy_key}'
                )
            if policy_key not in seen:
                resolved.append(policy_key)
                seen.add(policy_key)

    return resolved


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


def materialize_reviewed_surface_package(surface_package_input_path: Path, policy_paths, output_dir: Path):
    data = load_surface_policy_json(surface_package_input_path)
    if not policy_paths:
        return surface_package_input_path

    reviewed_dir = output_dir / 'reviewed-surface-packages'
    reviewed_dir.mkdir(parents=True, exist_ok=True)
    reviewed_name = surface_package_input_path.name
    reviewed_path = reviewed_dir / reviewed_name
    if reviewed_path == surface_package_input_path:
        reviewed_path = reviewed_dir / f"{surface_package_input_path.stem}-reviewed{surface_package_input_path.suffix}"

    for policy_path in policy_paths:
        data = apply_surface_transport_policy(copy.deepcopy(data), load_surface_policy_json(policy_path), policy_path)

    reviewed_path.write_text(json.dumps(data, indent=2) + '\n')
    return reviewed_path


def main():
    parser = argparse.ArgumentParser(
        description='Build a selected canonical hi-res package directly from imported index/subset inputs, ordered surfaces, and transport policy.'
    )
    parser.add_argument('--input', action='append', help='Path to imported_index or imported_subset JSON. Pass multiple times to merge sources.')
    parser.add_argument('--bindings-input', action='append', help='Path to an existing bindings.json payload. Pass multiple times to extend a selected package.')
    parser.add_argument('--surface-package-input', action='append', help='Path to a phrs-surface-package-v1 or phrs-surface-package-v2 JSON. Pass multiple times to fold ordered surfaces into the build.')
    parser.add_argument('--surface-transport-policy', action='append', help='Review-only surface transport policy JSON to apply to every --surface-package-input before compile. Pass multiple times.')
    parser.add_argument('--review-input', action='append', help='Path to sampled transport review JSON. Pass multiple times to provide transport-pool review sources.')
    parser.add_argument('--review-profile', action='append', help='Review-only profile JSON that bundles duplicate/alias/pool/surface review inputs. Pass multiple times to layer tracked review decisions.')
    parser.add_argument('--review-pool-key', action='append', help='Policy key from transport_review_pools to include in this package build. Pass multiple times.')
    parser.add_argument('--review-pool-group-key', action='append', help='Group key from transport_review_pool_groups to include in this package build. Pass multiple times.')
    parser.add_argument('--bridge-key', action='append', help='Policy key from transport_synthetic_bridges to include in this package build. Pass multiple times.')
    parser.add_argument('--cache', help='Legacy .hts/.htc cache path required when using --bridge-key.')
    parser.add_argument('--duplicate-review', action='append', help='Review-only duplicate-review JSON to apply as offline loader-manifest dedupe before materialization. Pass multiple times.')
    parser.add_argument('--alias-group-review', action='append', help='Review-only alias-group review JSON to apply as offline asset-level aliasing before materialization. Pass multiple times.')
    parser.add_argument('--policy', required=True, help='Transport policy JSON path.')
    parser.add_argument('--output-dir', required=True, help='Output directory for bindings, manifest, package dir, and binary package.')
    parser.add_argument('--package-name', default='package.phrb', help='Binary package filename relative to output-dir.')
    parser.add_argument('--allow-unresolved', action='store_true', help='Allow unresolved transport cases in the emitted binding set.')
    args = parser.parse_args()

    input_paths = [Path(path) for path in (args.input or [])]
    bindings_input_paths = [Path(path) for path in (args.bindings_input or [])]
    surface_package_input_paths = [Path(path) for path in (args.surface_package_input or [])]
    surface_transport_policy_paths = [Path(path) for path in (args.surface_transport_policy or [])]
    review_input_paths = [Path(path) for path in (args.review_input or [])]
    duplicate_review_paths = [Path(path) for path in (args.duplicate_review or [])]
    alias_group_review_paths = [Path(path) for path in (args.alias_group_review or [])]
    review_profile_paths = [Path(path) for path in (args.review_profile or [])]
    review_pool_keys = args.review_pool_key or []
    review_pool_group_keys = args.review_pool_group_key or []
    bridge_keys = args.bridge_key or []
    cache_path = Path(args.cache) if args.cache else None
    loaded_review_profiles = [load_review_profile(path) for path in review_profile_paths]
    surface_transport_policy_paths = [
        Path(path)
        for path in merge_unique_strings(
            [str(path) for path in surface_transport_policy_paths],
            *[profile['surface_transport_policy_paths'] for profile in loaded_review_profiles],
        )
    ]
    review_input_paths = [
        Path(path)
        for path in merge_unique_strings(
            [str(path) for path in review_input_paths],
            *[profile['review_input_paths'] for profile in loaded_review_profiles],
        )
    ]
    duplicate_review_paths = [
        Path(path)
        for path in merge_unique_strings(
            [str(path) for path in duplicate_review_paths],
            *[profile['duplicate_review_paths'] for profile in loaded_review_profiles],
        )
    ]
    alias_group_review_paths = [
        Path(path)
        for path in merge_unique_strings(
            [str(path) for path in alias_group_review_paths],
            *[profile['alias_group_review_paths'] for profile in loaded_review_profiles],
        )
    ]
    review_pool_keys = merge_unique_strings(
        review_pool_keys,
        *[profile['review_pool_keys'] for profile in loaded_review_profiles],
    )
    review_pool_group_keys = merge_unique_strings(
        review_pool_group_keys,
        *[profile['review_pool_group_keys'] for profile in loaded_review_profiles],
    )
    if (review_pool_keys or review_pool_group_keys) and not review_input_paths:
        raise SystemExit('--review-pool-key/--review-pool-group-key requires at least one --review-input')
    if bridge_keys and cache_path is None:
        raise SystemExit('--bridge-key requires --cache')
    if not input_paths and not bindings_input_paths and not surface_package_input_paths and not review_input_paths and not bridge_keys:
        raise SystemExit('at least one --input, --bindings-input, --surface-package-input, --review-input, or --bridge-key is required')

    policy_path = Path(args.policy)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    binding_payloads = []
    policy_data = load_policy(policy_path)
    for input_path in input_paths:
        binding_payloads.append((input_path, build_proxy_bindings(input_path, policy_data)))
    for bindings_input_path in bindings_input_paths:
        binding_payloads.append((bindings_input_path, load_binding_payload(bindings_input_path)))
    reviewed_surface_package_paths = []
    for surface_package_input_path in surface_package_input_paths:
        compiled_surface_package_path = materialize_reviewed_surface_package(
            surface_package_input_path,
            surface_transport_policy_paths,
            output_dir,
        )
        reviewed_surface_package_paths.append(str(compiled_surface_package_path))
        binding_payloads.append((compiled_surface_package_path, compile_surface_package(compiled_surface_package_path)))
    resolved_review_pool_keys = resolve_review_pool_keys(policy_data, review_pool_keys, review_pool_group_keys)
    if review_input_paths and resolved_review_pool_keys:
        binding_payloads.append((Path('review-pools'), build_review_pool_bindings(review_input_paths, policy_data, resolved_review_pool_keys)))
    if bridge_keys:
        binding_payloads.append((Path('transport-bridges'), build_transport_bridge_bindings(policy_data, cache_path, bridge_keys)))
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
    duplicate_review_changes = []
    alias_group_review_changes = []
    if duplicate_review_paths:
        duplicate_review_docs = [json.loads(path.read_text()) for path in duplicate_review_paths]
        loader_manifest, duplicate_review_changes = dedupe_loader_manifest(loader_manifest, duplicate_review_docs)
    if alias_group_review_paths:
        alias_group_review_docs = [json.loads(path.read_text()) for path in alias_group_review_paths]
        loader_manifest, alias_group_review_changes = apply_alias_group_reviews(loader_manifest, alias_group_review_docs)
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
        'surface_transport_policy_paths': [str(path) for path in surface_transport_policy_paths],
        'reviewed_surface_package_paths': reviewed_surface_package_paths,
        'review_input_paths': [str(path) for path in review_input_paths],
        'review_profile_paths': [str(path) for path in review_profile_paths],
        'duplicate_review_paths': [str(path) for path in duplicate_review_paths],
        'alias_group_review_paths': [str(path) for path in alias_group_review_paths],
        'review_pool_keys': review_pool_keys,
        'review_pool_group_keys': review_pool_group_keys,
        'resolved_review_pool_keys': resolved_review_pool_keys,
        'bridge_keys': bridge_keys,
        'cache_path': str(cache_path) if cache_path else None,
        'policy_path': str(policy_path),
        'bindings_path': str(bindings_path),
        'loader_manifest_path': str(loader_manifest_path),
        'package_dir': str(package_dir),
        'binding_count': bindings.get('binding_count', 0),
        'unresolved_count': len(unresolved),
        'duplicate_review_change_count': len(duplicate_review_changes),
        'duplicate_review_changes': duplicate_review_changes,
        'alias_group_review_change_count': len(alias_group_review_changes),
        'alias_group_review_changes': alias_group_review_changes,
        'package_manifest_record_count': package_manifest.get('record_count', 0),
        'binary_package': binary_result,
    }
    sys.stdout.write(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
