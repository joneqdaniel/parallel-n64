#!/usr/bin/env python3
import argparse
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image

from hires_pack_common import decode_entry_rgba8, parse_cache_entries


def load_loader_manifest(path: Path):
    return json.loads(path.read_text())


def classify_runtime_record_class(native_count, compat_count):
    native_count = int(native_count or 0)
    compat_count = int(compat_count or 0)
    if native_count > 0 and compat_count == 0:
        return 'native-sampled-only'
    if native_count == 0 and compat_count > 0:
        return 'compat-only'
    if native_count > 0 and compat_count > 0:
        return 'mixed-native-and-compat'
    return 'none'


def summarize_runtime_counts(runtime_ready_record_count,
                             runtime_deferred_record_count,
                             runtime_ready_record_kind_counts,
                             runtime_deferred_record_kind_counts):
    runtime_ready_native_sampled_record_count = int(runtime_ready_record_kind_counts.get('canonical-sampled', 0))
    runtime_deferred_native_sampled_record_count = int(runtime_deferred_record_kind_counts.get('canonical-sampled', 0))
    runtime_ready_compat_record_count = int(runtime_ready_record_count - runtime_ready_native_sampled_record_count)
    runtime_deferred_compat_record_count = int(runtime_deferred_record_count - runtime_deferred_native_sampled_record_count)
    return {
        'runtime_ready_native_sampled_record_count': runtime_ready_native_sampled_record_count,
        'runtime_ready_compat_record_count': runtime_ready_compat_record_count,
        'runtime_deferred_native_sampled_record_count': runtime_deferred_native_sampled_record_count,
        'runtime_deferred_compat_record_count': runtime_deferred_compat_record_count,
        'runtime_ready_record_class': classify_runtime_record_class(
            runtime_ready_native_sampled_record_count,
            runtime_ready_compat_record_count,
        ),
        'runtime_deferred_record_class': classify_runtime_record_class(
            runtime_deferred_native_sampled_record_count,
            runtime_deferred_compat_record_count,
        ),
    }


def _build_materialized_package(loader_manifest_path: Path,
                                output_dir: Path | None,
                                emit_png_assets: bool,
                                persist_assets: bool,
                                defer_runtime_deferred_assets: bool,
                                include_asset_blobs: bool,
                                compute_review_hashes: bool,
                                progress_callback=None,
                                progress_interval: int = 100):
    manifest = load_loader_manifest(loader_manifest_path)
    if output_dir is not None:
        output_dir.mkdir(parents=True, exist_ok=True)
    assets_dir = output_dir / 'assets' if output_dir is not None else None
    if persist_assets and assets_dir is not None:
        assets_dir.mkdir(parents=True, exist_ok=True)

    cache_index = {}
    duplicate_groups = []
    asset_blobs = {}

    def get_entries(cache_path_str):
        if cache_path_str not in cache_index:
            cache_path = Path(cache_path_str)
            entries = parse_cache_entries(cache_path)
            exact_index = {}
            generic_index = {}
            for entry in entries:
                checksum64 = int(entry.get('checksum64', 0))
                formatsize = int(entry.get('formatsize', 0))
                exact_index[(checksum64, formatsize)] = entry
                if formatsize == 0 and checksum64 not in generic_index:
                    generic_index[checksum64] = entry
            cache_index[cache_path_str] = {
                'entries': entries,
                'exact_index': exact_index,
                'generic_index': generic_index,
                'cache_bytes': cache_path.read_bytes() if cache_path.suffix.lower() == '.hts' else None,
            }
        return cache_index[cache_path_str]

    package_records = []
    runtime_ready_record_count = 0
    runtime_deferred_record_count = 0
    runtime_ready_record_kind_counts = {}
    runtime_deferred_record_kind_counts = {}
    total_asset_candidate_count = 0
    records = manifest.get('records', [])
    total_records = len(records)
    for index, record in enumerate(records, start=1):
        emitted_candidates = []
        by_pixel_hash = {} if compute_review_hashes else None
        runtime_ready = bool(record.get('runtime_ready', False))
        for candidate in record.get('asset_candidates', []):
            width = int(candidate['width'])
            height = int(candidate['height'])
            if emit_png_assets:
                filename = f"{candidate['replacement_id']}.png"
            else:
                filename = f"{candidate['replacement_id']}.rgba"
            rel_path = Path('assets') / filename
            emitted = {
                **candidate,
                'materialized_path': str(rel_path),
            }

            if defer_runtime_deferred_assets and not runtime_ready:
                emitted['pixel_sha256'] = None
                emitted['alpha_normalized_pixel_sha256'] = None
                emitted['asset_blob_included'] = False
                emitted_candidates.append(emitted)
                total_asset_candidate_count += 1
                continue

            need_decoded_asset = emit_png_assets or persist_assets or include_asset_blobs or compute_review_hashes
            if need_decoded_asset:
                cache_path = Path(candidate['legacy_source_path'])
                cache_view = get_entries(candidate['legacy_source_path'])
                checksum64 = int(candidate['legacy_checksum64'], 16)
                formatsize = int(candidate.get('legacy_formatsize') or 0)
                entry = cache_view['exact_index'].get((checksum64, formatsize)) or cache_view['generic_index'].get(checksum64)
                if entry is None:
                    raise SystemExit(f"Missing cache entry for {candidate['replacement_id']}")
                rgba = decode_entry_rgba8(cache_path, entry, cache_bytes=cache_view.get('cache_bytes'))
                if emit_png_assets:
                    image = Image.frombytes('RGBA', (width, height), rgba)
                    if persist_assets:
                        image.save(output_dir / rel_path)
                else:
                    if persist_assets:
                        (output_dir / rel_path).write_bytes(rgba)
                if include_asset_blobs:
                    asset_blobs[str(rel_path)] = rgba
                if compute_review_hashes:
                    pixel_sha256 = hashlib.sha256(rgba).hexdigest()
                    normalized = bytearray(rgba)
                    for i in range(0, len(normalized), 4):
                        if normalized[i + 3] == 0:
                            normalized[i + 0] = 0
                            normalized[i + 1] = 0
                            normalized[i + 2] = 0
                    alpha_normalized_pixel_sha256 = hashlib.sha256(bytes(normalized)).hexdigest()
                    emitted['pixel_sha256'] = pixel_sha256
                    emitted['alpha_normalized_pixel_sha256'] = alpha_normalized_pixel_sha256
                    by_pixel_hash.setdefault(alpha_normalized_pixel_sha256, []).append(emitted['replacement_id'])
                else:
                    emitted['pixel_sha256'] = None
                    emitted['alpha_normalized_pixel_sha256'] = None
            else:
                emitted['pixel_sha256'] = None
                emitted['alpha_normalized_pixel_sha256'] = None
            emitted['asset_blob_included'] = bool(include_asset_blobs)
            emitted_candidates.append(emitted)
            total_asset_candidate_count += 1
        duplicate_pixel_groups = []
        if compute_review_hashes:
            duplicate_pixel_groups = [
                {
                    'alpha_normalized_pixel_sha256': pixel_sha256,
                    'replacement_ids': sorted(replacement_ids),
                }
                for pixel_sha256, replacement_ids in sorted(by_pixel_hash.items())
                if len(replacement_ids) > 1
            ]
        if duplicate_pixel_groups:
            duplicate_groups.append(
                {
                    'policy_key': record.get('policy_key'),
                    'sampled_object_id': record.get('sampled_object_id'),
                    'duplicate_pixel_groups': duplicate_pixel_groups,
                }
            )
        if runtime_ready:
            runtime_ready_record_count += 1
            record_kind = str(record.get('record_kind') or 'unknown')
            runtime_ready_record_kind_counts[record_kind] = runtime_ready_record_kind_counts.get(record_kind, 0) + 1
        else:
            runtime_deferred_record_count += 1
            record_kind = str(record.get('record_kind') or 'unknown')
            runtime_deferred_record_kind_counts[record_kind] = runtime_deferred_record_kind_counts.get(record_kind, 0) + 1
        package_records.append(
            {
                'policy_key': record.get('policy_key'),
                'sampled_object_id': record.get('sampled_object_id'),
                'record_kind': record.get('record_kind'),
                'record_flags': int(record.get('record_flags', 0) or 0),
                'runtime_ready': runtime_ready,
                'canonical_identity': record.get('canonical_identity', {}),
                'upload_low32s': record.get('upload_low32s', []),
                'upload_pcrcs': record.get('upload_pcrcs', []),
                'asset_candidate_count': len(emitted_candidates),
                'asset_candidates': emitted_candidates,
                'duplicate_pixel_group_count': len(duplicate_pixel_groups),
                'duplicate_pixel_groups': duplicate_pixel_groups,
            }
        )
        if progress_callback and (index == total_records or index % max(int(progress_interval), 1) == 0):
            runtime_summary = summarize_runtime_counts(
                runtime_ready_record_count,
                runtime_deferred_record_count,
                runtime_ready_record_kind_counts,
                runtime_deferred_record_kind_counts,
            )
            progress_callback(
                {
                    'records_complete': index,
                    'record_total': total_records,
                    'runtime_ready_record_count': runtime_ready_record_count,
                    'runtime_deferred_record_count': runtime_deferred_record_count,
                    'runtime_ready_record_kind_counts': dict(sorted(runtime_ready_record_kind_counts.items())),
                    'runtime_deferred_record_kind_counts': dict(sorted(runtime_deferred_record_kind_counts.items())),
                    **runtime_summary,
                    'asset_candidate_total': total_asset_candidate_count,
                }
            )

    runtime_summary = summarize_runtime_counts(
        runtime_ready_record_count,
        runtime_deferred_record_count,
        runtime_ready_record_kind_counts,
        runtime_deferred_record_kind_counts,
    )

    package_manifest = {
        'schema_version': 1,
        'source_loader_manifest_path': str(loader_manifest_path),
        'bundle_path': manifest.get('bundle_path'),
        'record_count': len(package_records),
        'runtime_ready_record_count': runtime_ready_record_count,
        'runtime_deferred_record_count': runtime_deferred_record_count,
        'runtime_ready_record_kind_counts': dict(sorted(runtime_ready_record_kind_counts.items())),
        'runtime_deferred_record_kind_counts': dict(sorted(runtime_deferred_record_kind_counts.items())),
        **runtime_summary,
        'asset_candidate_total': total_asset_candidate_count,
        'records': package_records,
        'duplicate_record_count': len(duplicate_groups),
        'duplicate_groups': duplicate_groups,
        'unresolved_transport_cases': manifest.get('unresolved_transport_cases', []),
    }
    if output_dir is not None:
        (output_dir / 'package-manifest.json').write_text(json.dumps(package_manifest, indent=2) + '\n')
    return package_manifest, asset_blobs


def materialize_package(loader_manifest_path: Path,
                        output_dir: Path,
                        emit_png_assets: bool = True,
                        compute_review_hashes: bool = True,
                        progress_callback=None,
                        progress_interval: int = 100):
    package_manifest, _ = _build_materialized_package(
        loader_manifest_path,
        output_dir,
        emit_png_assets=emit_png_assets,
        persist_assets=True,
        defer_runtime_deferred_assets=False,
        include_asset_blobs=True,
        compute_review_hashes=compute_review_hashes,
        progress_callback=progress_callback,
        progress_interval=progress_interval,
    )
    return package_manifest


def materialize_package_in_memory(loader_manifest_path: Path,
                                  output_dir: Path | None = None,
                                  emit_png_assets: bool = False,
                                  include_asset_blobs: bool = True,
                                  compute_review_hashes: bool = True,
                                  progress_callback=None,
                                  progress_interval: int = 100):
    return _build_materialized_package(
        loader_manifest_path,
        output_dir,
        emit_png_assets=emit_png_assets,
        persist_assets=False,
        defer_runtime_deferred_assets=True,
        include_asset_blobs=include_asset_blobs,
        compute_review_hashes=compute_review_hashes,
        progress_callback=progress_callback,
        progress_interval=progress_interval,
    )


def main():
    parser = argparse.ArgumentParser(description='Materialize a canonical hi-res package slice from a loader manifest.')
    parser.add_argument('--loader-manifest', required=True, help='Path to loader-oriented manifest JSON.')
    parser.add_argument('--output-dir', required=True, help='Output directory for the materialized package.')
    parser.add_argument('--no-png-assets', action='store_true', help='Emit raw .rgba assets instead of PNG preview assets.')
    args = parser.parse_args()

    package_manifest = materialize_package(Path(args.loader_manifest), Path(args.output_dir), emit_png_assets=not args.no_png_assets)
    sys.stdout.write(json.dumps({
        'output_dir': args.output_dir,
        'record_count': package_manifest['record_count'],
        'unresolved_count': len(package_manifest.get('unresolved_transport_cases', [])),
    }, indent=2) + '\n')


if __name__ == '__main__':
    main()
