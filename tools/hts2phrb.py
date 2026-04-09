#!/usr/bin/env python3
import argparse
import hashlib
import json
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

from hires_pack_apply_alias_group_review import apply_alias_group_reviews
from hires_pack_apply_duplicate_review import dedupe_loader_manifest
from hires_pack_common import (
    decode_entry_rgba8,
    parse_bundle_ci_context,
    parse_bundle_families,
    parse_bundle_sampled_object_context,
    parse_cache_entries,
    read_entry_blob,
    resolve_bundle_input_path,
    resolve_context_bundle_input_paths,
    resolve_legacy_cache_path,
)
from hires_pack_emit_binary_package import emit_binary_package_from_manifest
from hires_pack_emit_loader_manifest import build_canonical_loader_manifest, build_loader_manifest
from hires_pack_emit_proxy_bindings import build_proxy_bindings, load_policy as load_transport_policy
from hires_pack_materialize_package import materialize_package_in_memory
from hires_pack_migrate import build_imported_index, build_migration_plan, load_import_policy

HTS2PHRB_ARTIFACT_VERSION = 7


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


def load_review_profile(path: Path):
    data = json.loads(path.read_text())
    schema_version = int(data.get("schema_version") or 0)
    if schema_version != 1:
        raise SystemExit(f"review profile {path} must have schema_version=1")

    def resolve_paths(key):
        values = data.get(key) or []
        if not isinstance(values, list):
            raise SystemExit(f"review profile {path} key {key} must be a list")
        resolved = []
        for value in values:
            if not isinstance(value, str) or not value:
                raise SystemExit(f"review profile {path} key {key} must contain non-empty strings")
            candidate = Path(value)
            if not candidate.is_absolute():
                candidate = (path.parent / candidate).resolve()
            resolved.append(str(candidate))
        return resolved

    return {
        "path": str(path.resolve()),
        "transport_policy_paths": resolve_paths("transport_policy_paths"),
        "duplicate_review_paths": resolve_paths("duplicate_review_paths"),
        "alias_group_review_paths": resolve_paths("alias_group_review_paths"),
    }


def resolve_manifest_review_inputs(args):
    review_profile_paths = [Path(path).resolve() for path in (args.review_profile or [])]
    loaded_review_profiles = [load_review_profile(path) for path in review_profile_paths]
    transport_policy_paths = merge_unique_strings(
        [str(Path(args.transport_policy).resolve())] if args.transport_policy else [],
        *[profile["transport_policy_paths"] for profile in loaded_review_profiles],
    )
    if len(transport_policy_paths) > 1:
        raise SystemExit(
            "hts2phrb only supports one effective transport policy input; "
            f"got {transport_policy_paths!r}"
        )
    transport_policy_path = Path(transport_policy_paths[0]) if transport_policy_paths else None
    duplicate_review_paths = [
        Path(path)
        for path in merge_unique_strings(
            [str(Path(path).resolve()) for path in (args.duplicate_review or [])],
            *[profile["duplicate_review_paths"] for profile in loaded_review_profiles],
        )
    ]
    alias_group_review_paths = [
        Path(path)
        for path in merge_unique_strings(
            [str(Path(path).resolve()) for path in (args.alias_group_review or [])],
            *[profile["alias_group_review_paths"] for profile in loaded_review_profiles],
        )
    ]
    return {
        "review_profile_paths": review_profile_paths,
        "transport_policy_path": transport_policy_path,
        "duplicate_review_paths": duplicate_review_paths,
        "alias_group_review_paths": alias_group_review_paths,
    }


def apply_loader_manifest_reviews(loader_manifest, duplicate_review_paths, alias_group_review_paths):
    duplicate_review_changes = []
    duplicate_review_skips = []
    alias_group_review_changes = []
    alias_group_review_skips = []
    if duplicate_review_paths:
        duplicate_review_docs = [json.loads(path.read_text()) for path in duplicate_review_paths]
        for review_doc in duplicate_review_docs:
            try:
                loader_manifest, changes = dedupe_loader_manifest(loader_manifest, [review_doc])
            except SystemExit as exc:
                skip = classify_duplicate_review_skip(loader_manifest, review_doc, str(exc))
                if skip is None:
                    raise
                duplicate_review_skips.append(skip)
                continue
            duplicate_review_changes.extend(changes)
    if alias_group_review_paths:
        alias_group_review_docs = [json.loads(path.read_text()) for path in alias_group_review_paths]
        for review_doc in alias_group_review_docs:
            try:
                loader_manifest, changes = apply_alias_group_reviews(loader_manifest, [review_doc])
            except SystemExit as exc:
                skip = classify_alias_group_review_skip(loader_manifest, review_doc, str(exc))
                if skip is None:
                    raise
                alias_group_review_skips.append(skip)
                continue
            alias_group_review_changes.extend(changes)
    return (
        loader_manifest,
        duplicate_review_changes,
        duplicate_review_skips,
        alias_group_review_changes,
        alias_group_review_skips,
    )


def resolve_manifest_review_record(loader_manifest, sampled_low32, policy_key):
    normalized_low32 = str(sampled_low32 or "").lower()
    normalized_policy_key = str(policy_key or "")
    records = loader_manifest.get("records") or []
    exact_record = None
    for record in records:
        record_low32 = str((record.get("canonical_identity") or {}).get("sampled_low32") or "").lower()
        if record_low32 == normalized_low32 and str(record.get("policy_key") or "") == normalized_policy_key:
            exact_record = record
            break
    if exact_record is not None:
        return exact_record, "policy-key-exact"

    sampled_matches = [
        record
        for record in records
        if str((record.get("canonical_identity") or {}).get("sampled_low32") or "").lower() == normalized_low32
    ]
    if len(sampled_matches) == 1:
        return sampled_matches[0], "sampled-low32-unique"
    if not sampled_matches:
        return None, "record-not-in-scope"
    raise SystemExit(
        f"multiple records found for sampled_low32={normalized_low32} policy={normalized_policy_key}; "
        f"candidates={sorted(str(record.get('policy_key') or '') for record in sampled_matches)}"
    )


def classify_duplicate_review_skip(loader_manifest, review_doc, error_message):
    sampled_low32 = str(review_doc.get("sampled_low32") or "").lower()
    bucket = review_doc.get("duplicate_bucket") or {}
    policy_key = str(bucket.get("policy") or "")
    selector = str(review_doc.get("selector") or "").lower()
    active_replacement_id = str(bucket.get("replacement_id") or "")
    record, record_resolution = resolve_manifest_review_record(loader_manifest, sampled_low32, policy_key)
    if record is None:
        return {
            "sampled_low32": sampled_low32,
            "policy_key": policy_key,
            "resolved_policy_key": None,
            "record_resolution": record_resolution,
            "selector": selector,
            "active_replacement_id": active_replacement_id,
            "skip_reason": "record-not-in-scope",
            "status": "skipped",
            "error": error_message,
        }
    if not (record.get("asset_candidates") or []):
        return {
            "sampled_low32": sampled_low32,
            "policy_key": policy_key,
            "resolved_policy_key": str(record.get("policy_key") or ""),
            "record_resolution": record_resolution,
            "selector": selector,
            "active_replacement_id": active_replacement_id,
            "skip_reason": "no-asset-candidates",
            "status": "skipped",
            "error": error_message,
        }
    return None


def classify_alias_group_review_skip(loader_manifest, review_doc, error_message):
    sampled_low32 = str(review_doc.get("sampled_low32") or "").lower()
    policy_key = str(review_doc.get("policy_key") or "")
    canonical_replacement_id = str(review_doc.get("suggested_canonical_replacement_id") or "")
    record, record_resolution = resolve_manifest_review_record(loader_manifest, sampled_low32, policy_key)
    if record is None:
        return {
            "sampled_low32": sampled_low32,
            "policy_key": policy_key,
            "resolved_policy_key": None,
            "record_resolution": record_resolution,
            "canonical_replacement_id": canonical_replacement_id,
            "skip_reason": "record-not-in-scope",
            "status": "skipped",
            "error": error_message,
        }
    if not (record.get("asset_candidates") or []):
        return {
            "sampled_low32": sampled_low32,
            "policy_key": policy_key,
            "resolved_policy_key": str(record.get("policy_key") or ""),
            "record_resolution": record_resolution,
            "canonical_replacement_id": canonical_replacement_id,
            "skip_reason": "no-asset-candidates",
            "status": "skipped",
            "error": error_message,
        }
    return None


def classify_review_overlay_state(input_count, applied_count, skipped_count):
    input_count = int(input_count or 0)
    applied_count = int(applied_count or 0)
    skipped_count = int(skipped_count or 0)
    if input_count <= 0:
        return "none"
    if applied_count > 0 and skipped_count > 0:
        return "mixed"
    if applied_count > 0:
        return "applied"
    if skipped_count > 0:
        return "skipped"
    return "present-no-effect"


def slugify_component(value):
    lowered = str(value).strip().lower()
    pieces = []
    last_was_dash = False
    for ch in lowered:
        if ch.isalnum():
            pieces.append(ch)
            last_was_dash = False
        else:
            if not last_was_dash:
                pieces.append("-")
                last_was_dash = True
    slug = "".join(pieces).strip("-")
    return slug or "cache"


def derive_request_slug(args, bundle_resolution=None):
    if args.bundle:
        if bundle_resolution and bundle_resolution.get("resolved_bundle_path"):
            resolved_bundle_path = Path(bundle_resolution["resolved_bundle_path"]).resolve()
            bundle_slug = slugify_component(resolved_bundle_path.name)
            bundle_path_tag = hashlib.sha1(str(resolved_bundle_path).encode("utf-8")).hexdigest()[:8]
            return f"bundle-{bundle_slug}-{bundle_path_tag}"
        bundle_input_path = Path(args.bundle).resolve()
        bundle_slug = slugify_component(bundle_input_path.stem if bundle_input_path.suffix else bundle_input_path.name)
        bundle_path_tag = hashlib.sha1(str(bundle_input_path).encode("utf-8")).hexdigest()[:8]
        return f"bundle-{bundle_slug}-{bundle_path_tag}"
    if args.low32:
        return "selected-families"
    if args.all_families:
        return "all-families"
    return "all-families"


def derive_context_bundle_tag(context_bundle_resolutions):
    if not context_bundle_resolutions:
        return None
    normalized = [
        str(Path(item["resolved_bundle_path"]).resolve())
        for item in context_bundle_resolutions
    ]
    digest = hashlib.sha1("\n".join(sorted(normalized)).encode("utf-8")).hexdigest()[:8]
    return f"context-{digest}"


def resolve_output_dir(args, cache_input_path, cache_resolution=None, bundle_resolution=None):
    if args.output_dir:
        return Path(args.output_dir), False
    if cache_resolution is not None:
        resolved_cache_path = Path(cache_resolution["resolved_path"]).resolve()
        cache_slug = slugify_component(resolved_cache_path.stem if resolved_cache_path.suffix else resolved_cache_path.name)
        cache_path_tag = hashlib.sha1(str(resolved_cache_path).encode("utf-8")).hexdigest()[:8]
        cache_slug = f"{cache_slug}-{cache_path_tag}"
    else:
        cache_slug = slugify_component(cache_input_path.stem if cache_input_path.suffix else cache_input_path.name)
    request_slug = derive_request_slug(args, bundle_resolution=bundle_resolution)
    context_bundle_tag = derive_context_bundle_tag(getattr(args, "context_bundle_resolutions", None))
    if context_bundle_tag:
        request_slug = f"{request_slug}-{context_bundle_tag}"
    return Path.cwd() / "artifacts" / "hts2phrb" / f"{cache_slug}-{request_slug}", True


def should_build_runtime_overlay(args):
    if args.runtime_overlay_mode == "always":
        return True, "forced"
    if args.runtime_overlay_mode == "never":
        return False, "disabled"
    if args.bundle or args.low32 or getattr(args, "resolved_transport_policy_path", None) or args.context_bundle:
        return True, "runtime-context-available"
    return False, "no-runtime-context"


def resolve_runtime_overlay_plan(args, canonical_loader_manifest):
    runtime_overlay_built, runtime_overlay_reason = should_build_runtime_overlay(args)
    runtime_ready_record_count = int(
        canonical_loader_manifest.get("runtime_ready_record_count")
        or sum(1 for record in canonical_loader_manifest.get("records", []) if bool(record.get("runtime_ready")))
    )
    if (
        runtime_overlay_built
        and args.runtime_overlay_mode == "auto"
        and runtime_ready_record_count <= 0
    ):
        return False, "no-runtime-ready-records"
    return runtime_overlay_built, runtime_overlay_reason


def normalize_optional_path(value):
    if not value:
        return None
    return str(Path(value).resolve())


def fingerprint_path(value):
    normalized = normalize_optional_path(value)
    if not normalized:
        return None
    path = Path(normalized)
    if not path.exists():
        return {
            "path": normalized,
            "exists": False,
        }
    stat = path.stat()
    return {
        "path": normalized,
        "exists": True,
        "size": int(stat.st_size),
        "mtime_ns": int(stat.st_mtime_ns),
    }


def make_pre_request_signature(args, cache_resolution, bundle_resolution):
    return {
        "artifact_contract_version": HTS2PHRB_ARTIFACT_VERSION,
        "resolved_cache_path": str(Path(cache_resolution["resolved_path"]).resolve()),
        "resolved_cache_storage": cache_resolution["resolved_storage"],
        "cache_fingerprint": fingerprint_path(cache_resolution["resolved_path"]),
        "resolved_bundle_path": (
            str(Path(bundle_resolution["resolved_bundle_path"]).resolve())
            if bundle_resolution and bundle_resolution.get("resolved_bundle_path")
            else None
        ),
        "resolved_bundle_hires_path": (
            str(Path(bundle_resolution["resolved_hires_path"]).resolve())
            if bundle_resolution and bundle_resolution.get("resolved_hires_path")
            else None
        ),
        "bundle_fingerprint": (
            fingerprint_path(bundle_resolution["resolved_hires_path"])
            if bundle_resolution and bundle_resolution.get("resolved_hires_path")
            else None
        ),
        "bundle_mode": args.bundle_mode,
        "bundle_step": args.bundle_step,
        "context_bundle_paths": [
            str(Path(item["resolved_bundle_path"]).resolve())
            for item in getattr(args, "context_bundle_resolutions", [])
        ],
        "context_bundle_fingerprints": [
            fingerprint_path(item["resolved_hires_path"])
            for item in getattr(args, "context_bundle_resolutions", [])
        ],
        "import_policy_path": normalize_optional_path(args.import_policy),
        "import_policy_fingerprint": fingerprint_path(args.import_policy),
        "transport_policy_path": normalize_optional_path(getattr(args, "resolved_transport_policy_path", None)),
        "transport_policy_fingerprint": fingerprint_path(getattr(args, "resolved_transport_policy_path", None)),
        "review_profile_paths": [
            str(path)
            for path in getattr(args, "resolved_review_profile_paths", [])
        ],
        "review_profile_fingerprints": [
            fingerprint_path(path)
            for path in getattr(args, "resolved_review_profile_paths", [])
        ],
        "duplicate_review_paths": [
            str(path)
            for path in getattr(args, "resolved_duplicate_review_paths", [])
        ],
        "duplicate_review_fingerprints": [
            fingerprint_path(path)
            for path in getattr(args, "resolved_duplicate_review_paths", [])
        ],
        "alias_group_review_paths": [
            str(path)
            for path in getattr(args, "resolved_alias_group_review_paths", [])
        ],
        "alias_group_review_fingerprints": [
            fingerprint_path(path)
            for path in getattr(args, "resolved_alias_group_review_paths", [])
        ],
        "package_name": args.package_name,
        "runtime_overlay_mode": args.runtime_overlay_mode,
        "all_families": bool(args.all_families),
        "low32": [normalize_low32(value) for value in (args.low32 or [])],
        "formatsize": [int(value) for value in (args.formatsize or [])],
    }


def make_request_signature(args, cache_resolution, request_mode, requested_pairs, bundle_resolution):
    return {
        "artifact_contract_version": HTS2PHRB_ARTIFACT_VERSION,
        "resolved_cache_path": str(Path(cache_resolution["resolved_path"]).resolve()),
        "resolved_cache_storage": cache_resolution["resolved_storage"],
        "cache_fingerprint": fingerprint_path(cache_resolution["resolved_path"]),
        "request_mode": request_mode,
        "requested_pairs": [[int(low32), int(formatsize)] for low32, formatsize in requested_pairs],
        "resolved_bundle_path": (
            str(Path(bundle_resolution["resolved_bundle_path"]).resolve())
            if bundle_resolution and bundle_resolution.get("resolved_bundle_path")
            else None
        ),
        "resolved_bundle_hires_path": (
            str(Path(bundle_resolution["resolved_hires_path"]).resolve())
            if bundle_resolution and bundle_resolution.get("resolved_hires_path")
            else None
        ),
        "bundle_fingerprint": (
            fingerprint_path(bundle_resolution["resolved_hires_path"])
            if bundle_resolution and bundle_resolution.get("resolved_hires_path")
            else None
        ),
        "bundle_mode": args.bundle_mode,
        "bundle_step": args.bundle_step,
        "context_bundle_paths": [
            str(Path(item["resolved_bundle_path"]).resolve())
            for item in getattr(args, "context_bundle_resolutions", [])
        ],
        "context_bundle_fingerprints": [
            fingerprint_path(item["resolved_hires_path"])
            for item in getattr(args, "context_bundle_resolutions", [])
        ],
        "import_policy_path": normalize_optional_path(args.import_policy),
        "import_policy_fingerprint": fingerprint_path(args.import_policy),
        "transport_policy_path": normalize_optional_path(getattr(args, "resolved_transport_policy_path", None)),
        "transport_policy_fingerprint": fingerprint_path(getattr(args, "resolved_transport_policy_path", None)),
        "review_profile_paths": [
            str(path)
            for path in getattr(args, "resolved_review_profile_paths", [])
        ],
        "review_profile_fingerprints": [
            fingerprint_path(path)
            for path in getattr(args, "resolved_review_profile_paths", [])
        ],
        "duplicate_review_paths": [
            str(path)
            for path in getattr(args, "resolved_duplicate_review_paths", [])
        ],
        "duplicate_review_fingerprints": [
            fingerprint_path(path)
            for path in getattr(args, "resolved_duplicate_review_paths", [])
        ],
        "alias_group_review_paths": [
            str(path)
            for path in getattr(args, "resolved_alias_group_review_paths", [])
        ],
        "alias_group_review_fingerprints": [
            fingerprint_path(path)
            for path in getattr(args, "resolved_alias_group_review_paths", [])
        ],
        "package_name": args.package_name,
        "runtime_overlay_mode": args.runtime_overlay_mode,
    }


def try_load_reusable_report_from_pre_signature(report_path: Path, pre_request_signature: dict):
    if not report_path.exists():
        return None
    report = json.loads(report_path.read_text())
    report_contract_version = int(report.get("artifact_contract_version", 0) or 0)
    if report_contract_version <= 0 or report_contract_version > HTS2PHRB_ARTIFACT_VERSION:
        return None
    if report.get("pre_request_signature") != pre_request_signature:
        return None
    if not reusable_report_artifacts_are_consistent(report):
        return None
    summary_path = Path(report.get("summary_path") or "")
    binary_package = report.get("binary_package") or {}
    binary_path = Path(binary_package.get("output_path") or "")
    if not summary_path.exists() or not binary_path.exists():
        return None
    return report


def try_load_reusable_report(report_path: Path, request_signature: dict):
    if not report_path.exists():
        return None
    report = json.loads(report_path.read_text())
    report_contract_version = int(report.get("artifact_contract_version", 0) or 0)
    if report_contract_version <= 0 or report_contract_version > HTS2PHRB_ARTIFACT_VERSION:
        return None
    report_signature = report.get("request_signature")
    if report_signature is not None:
        if report_signature != request_signature:
            return None
    elif not legacy_report_matches_request(report, request_signature):
        return None
    if not reusable_report_artifacts_are_consistent(report):
        return None
    summary_path = Path(report.get("summary_path") or "")
    binary_package = report.get("binary_package") or {}
    binary_path = Path(binary_package.get("output_path") or "")
    if not summary_path.exists() or not binary_path.exists():
        return None
    return report


def _manifest_value_or_default(manifest, key, default):
    value = manifest.get(key, default)
    return default if value is None else value


def _normalize_runtime_manifest_summary(manifest):
    records = manifest.get("records", [])
    runtime_ready_count = sum(1 for record in records if bool(record.get("runtime_ready")))
    runtime_deferred_count = max(int(manifest.get("record_count", len(records))) - runtime_ready_count, 0)
    runtime_ready_record_kind_counts = Counter()
    runtime_deferred_record_kind_counts = Counter()
    for record in records:
        record_kind = str(record.get("record_kind") or "unknown")
        if bool(record.get("runtime_ready")):
            runtime_ready_record_kind_counts[record_kind] += 1
        else:
            runtime_deferred_record_kind_counts[record_kind] += 1

    runtime_ready_native_sampled_record_count = int(runtime_ready_record_kind_counts.get("canonical-sampled", 0))
    runtime_deferred_native_sampled_record_count = int(runtime_deferred_record_kind_counts.get("canonical-sampled", 0))
    runtime_ready_compat_record_count = max(runtime_ready_count - runtime_ready_native_sampled_record_count, 0)
    runtime_deferred_compat_record_count = max(runtime_deferred_count - runtime_deferred_native_sampled_record_count, 0)

    return {
        "record_count": int(_manifest_value_or_default(manifest, "record_count", len(records))),
        "runtime_ready_record_count": int(_manifest_value_or_default(manifest, "runtime_ready_record_count", runtime_ready_count)),
        "runtime_deferred_record_count": int(_manifest_value_or_default(manifest, "runtime_deferred_record_count", runtime_deferred_count)),
        "runtime_ready_records_from_entries": runtime_ready_count,
        "runtime_deferred_records_from_entries": runtime_deferred_count,
        "runtime_ready_record_kind_counts": dict(
            _manifest_value_or_default(
                manifest,
                "runtime_ready_record_kind_counts",
                dict(sorted(runtime_ready_record_kind_counts.items())),
            )
        ),
        "runtime_ready_record_kind_counts_from_entries": dict(sorted(runtime_ready_record_kind_counts.items())),
        "runtime_deferred_record_kind_counts": dict(
            _manifest_value_or_default(
                manifest,
                "runtime_deferred_record_kind_counts",
                dict(sorted(runtime_deferred_record_kind_counts.items())),
            )
        ),
        "runtime_deferred_record_kind_counts_from_entries": dict(sorted(runtime_deferred_record_kind_counts.items())),
        "runtime_ready_native_sampled_record_count": int(
            _manifest_value_or_default(
                manifest,
                "runtime_ready_native_sampled_record_count",
                runtime_ready_native_sampled_record_count,
            )
        ),
        "runtime_ready_compat_record_count": int(
            _manifest_value_or_default(
                manifest,
                "runtime_ready_compat_record_count",
                runtime_ready_compat_record_count,
            )
        ),
        "runtime_deferred_native_sampled_record_count": int(
            _manifest_value_or_default(
                manifest,
                "runtime_deferred_native_sampled_record_count",
                runtime_deferred_native_sampled_record_count,
            )
        ),
        "runtime_deferred_compat_record_count": int(
            _manifest_value_or_default(
                manifest,
                "runtime_deferred_compat_record_count",
                runtime_deferred_compat_record_count,
            )
        ),
        "runtime_ready_record_class": str(
            _manifest_value_or_default(
                manifest,
                "runtime_ready_record_class",
                classify_runtime_record_class(
                    runtime_ready_native_sampled_record_count,
                    runtime_ready_compat_record_count,
                ),
            )
        ),
        "runtime_deferred_record_class": str(
            _manifest_value_or_default(
                manifest,
                "runtime_deferred_record_class",
                classify_runtime_record_class(
                    runtime_deferred_native_sampled_record_count,
                    runtime_deferred_compat_record_count,
                ),
            )
        ),
    }


def _backfill_runtime_manifest_summary(manifest):
    stats = _normalize_runtime_manifest_summary(manifest)
    changed = False
    for key in (
        "record_count",
        "runtime_ready_record_count",
        "runtime_deferred_record_count",
        "runtime_ready_record_kind_counts",
        "runtime_deferred_record_kind_counts",
        "runtime_ready_native_sampled_record_count",
        "runtime_ready_compat_record_count",
        "runtime_deferred_native_sampled_record_count",
        "runtime_deferred_compat_record_count",
        "runtime_ready_record_class",
        "runtime_deferred_record_class",
    ):
        if manifest.get(key) != stats[key]:
            manifest[key] = stats[key]
            changed = True
    return stats, changed


def _load_runtime_manifest_stats(manifest_path: Path):
    manifest = json.loads(manifest_path.read_text())
    stats, changed = _backfill_runtime_manifest_summary(manifest)
    if changed:
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest, stats


def _count_runtime_ready_records(manifest_path: Path):
    _, stats = _load_runtime_manifest_stats(manifest_path)
    return stats


def _runtime_stats_are_self_consistent(stats):
    if int(stats["runtime_ready_record_count"]) + int(stats["runtime_deferred_record_count"]) != int(stats["record_count"]):
        return False
    if dict(stats["runtime_ready_record_kind_counts"]) != dict(stats["runtime_ready_record_kind_counts_from_entries"]):
        return False
    if dict(stats["runtime_deferred_record_kind_counts"]) != dict(stats["runtime_deferred_record_kind_counts_from_entries"]):
        return False
    if int(stats["runtime_ready_native_sampled_record_count"]) + int(stats["runtime_ready_compat_record_count"]) != int(stats["runtime_ready_record_count"]):
        return False
    if int(stats["runtime_deferred_native_sampled_record_count"]) + int(stats["runtime_deferred_compat_record_count"]) != int(stats["runtime_deferred_record_count"]):
        return False
    if str(stats["runtime_ready_record_class"]) != classify_runtime_record_class(
        stats["runtime_ready_native_sampled_record_count"],
        stats["runtime_ready_compat_record_count"],
    ):
        return False
    if str(stats["runtime_deferred_record_class"]) != classify_runtime_record_class(
        stats["runtime_deferred_native_sampled_record_count"],
        stats["runtime_deferred_compat_record_count"],
    ):
        return False
    return True


def reusable_report_artifacts_are_consistent(report):
    loader_manifest_path = Path(report.get("loader_manifest_path") or "")
    package_dir = Path(report.get("package_dir") or "")
    package_manifest_path = package_dir / "package-manifest.json"
    if not loader_manifest_path.exists() or not package_manifest_path.exists():
        return False

    loader_stats = _count_runtime_ready_records(loader_manifest_path)
    package_stats = _count_runtime_ready_records(package_manifest_path)

    if package_stats["record_count"] != loader_stats["record_count"]:
        return False
    if package_stats["runtime_ready_record_count"] != package_stats["runtime_ready_records_from_entries"]:
        return False
    if package_stats["runtime_deferred_record_count"] != package_stats["runtime_deferred_records_from_entries"]:
        return False
    if not _runtime_stats_are_self_consistent(package_stats):
        return False
    if loader_stats["runtime_ready_record_count"] != loader_stats["runtime_ready_records_from_entries"]:
        return False
    if loader_stats["runtime_deferred_record_count"] != loader_stats["runtime_deferred_records_from_entries"]:
        return False
    if not _runtime_stats_are_self_consistent(loader_stats):
        return False
    if package_stats["runtime_ready_record_count"] != loader_stats["runtime_ready_record_count"]:
        return False
    if package_stats["runtime_deferred_record_count"] != loader_stats["runtime_deferred_record_count"]:
        return False
    if package_stats["runtime_ready_native_sampled_record_count"] != loader_stats["runtime_ready_native_sampled_record_count"]:
        return False
    if package_stats["runtime_ready_compat_record_count"] != loader_stats["runtime_ready_compat_record_count"]:
        return False
    if package_stats["runtime_deferred_native_sampled_record_count"] != loader_stats["runtime_deferred_native_sampled_record_count"]:
        return False
    if package_stats["runtime_deferred_compat_record_count"] != loader_stats["runtime_deferred_compat_record_count"]:
        return False
    if package_stats["runtime_ready_record_class"] != loader_stats["runtime_ready_record_class"]:
        return False
    if package_stats["runtime_deferred_record_class"] != loader_stats["runtime_deferred_record_class"]:
        return False
    if package_stats["runtime_ready_record_kind_counts"] != loader_stats["runtime_ready_record_kind_counts"]:
        return False
    if package_stats["runtime_deferred_record_kind_counts"] != loader_stats["runtime_deferred_record_kind_counts"]:
        return False

    report_runtime_ready_count = report.get("package_manifest_runtime_ready_record_count")
    if report_runtime_ready_count is not None and int(report_runtime_ready_count) != package_stats["runtime_ready_record_count"]:
        return False
    report_runtime_deferred_count = report.get("package_manifest_runtime_deferred_record_count")
    if report_runtime_deferred_count is not None and int(report_runtime_deferred_count) != package_stats["runtime_deferred_record_count"]:
        return False
    for report_key, stats_key in (
        ("package_manifest_runtime_ready_native_sampled_record_count", "runtime_ready_native_sampled_record_count"),
        ("package_manifest_runtime_ready_compat_record_count", "runtime_ready_compat_record_count"),
        ("package_manifest_runtime_deferred_native_sampled_record_count", "runtime_deferred_native_sampled_record_count"),
        ("package_manifest_runtime_deferred_compat_record_count", "runtime_deferred_compat_record_count"),
        ("package_manifest_runtime_ready_record_class", "runtime_ready_record_class"),
        ("package_manifest_runtime_deferred_record_class", "runtime_deferred_record_class"),
    ):
        report_value = report.get(report_key)
        if report_value is not None and report_value != package_stats[stats_key]:
            return False

    return True


def try_load_reusable_progress(progress_path: Path, pre_request_signature: dict):
    if not progress_path.exists():
        return None
    progress = json.loads(progress_path.read_text())
    if progress.get("pre_request_signature") != pre_request_signature:
        return None
    return progress


def legacy_report_matches_request(report, request_signature):
    try:
        report_cache_path = str(Path(report.get("cache_path") or "").resolve())
    except Exception:
        return False
    if report_cache_path != request_signature["resolved_cache_path"]:
        return False
    if str(report.get("request_mode") or "") != request_signature["request_mode"]:
        return False
    if int(report.get("requested_family_count", -1)) != len(request_signature["requested_pairs"]):
        return False
    if str(report.get("runtime_overlay_mode") or "") != request_signature["runtime_overlay_mode"]:
        return False
    report_bundle_path = report.get("resolved_bundle_path")
    if report_bundle_path:
        report_bundle_path = str(Path(report_bundle_path).resolve())
    if report_bundle_path != request_signature["resolved_bundle_path"]:
        return False
    return True


def make_runtime_overlay_placeholder(source_input_path: Path, reason: str):
    return {
        "schema_version": 1,
        "source_input_path": str(source_input_path),
        "binding_count": 0,
        "unresolved_count": 0,
        "bindings": [],
        "unresolved_transport_cases": [],
        "overlay_status": "skipped",
        "overlay_reason": reason,
    }


def merge_bundle_ci_contexts(base_context, extra_context):
    merged = dict(base_context or {})
    for key, value in (extra_context or {}).items():
        merged.setdefault(key, value)
    return merged


def merge_bundle_sampled_object_contexts(base_context, extra_context):
    merged = {
        key: list(values)
        for key, values in (base_context or {}).items()
    }
    for key, values in (extra_context or {}).items():
        dest = merged.setdefault(key, [])
        existing_ids = {
            item.get("sampled_object_id")
            for item in dest
            if item.get("sampled_object_id")
        }
        for item in values:
            sampled_object_id = item.get("sampled_object_id")
            if sampled_object_id and sampled_object_id in existing_ids:
                continue
            dest.append(item)
            if sampled_object_id:
                existing_ids.add(sampled_object_id)
    return merged


def dedupe_context_bundle_resolutions(context_bundle_resolutions):
    deduped = []
    seen = set()
    for resolution in context_bundle_resolutions:
        key = (
            str(Path(resolution["resolved_bundle_path"]).resolve()),
            str(Path(resolution["resolved_hires_path"]).resolve()),
        )
        if key in seen:
            continue
        seen.add(key)
        deduped.append(resolution)
    return deduped


def normalize_low32(value):
    if value is None or value == "":
        return None
    if isinstance(value, int):
        return f"{value:08x}"
    return f"{int(str(value), 16):08x}"


def make_family_key(low32, formatsize):
    normalized_low32 = normalize_low32(low32)
    if normalized_low32 is None or formatsize is None:
        return None
    return f"{normalized_low32}:fs{int(formatsize)}"


def policy_family_key(policy_key):
    if not policy_key:
        return None
    prefix = "legacy-low32-"
    if not str(policy_key).startswith(prefix):
        return None
    remainder = str(policy_key)[len(prefix):]
    if "-fs" not in remainder:
        return None
    low32, formatsize = remainder.split("-fs", 1)
    try:
        return make_family_key(low32, int(formatsize))
    except ValueError:
        return None


def record_family_keys(record):
    keys = []
    identity = record.get("canonical_identity") or {}
    canonical_key = make_family_key(identity.get("sampled_low32"), identity.get("formatsize"))
    if canonical_key:
        keys.append(canonical_key)
    policy_key = policy_family_key(record.get("policy_key"))
    if policy_key and policy_key not in keys:
        keys.append(policy_key)
    for candidate in record.get("asset_candidates") or []:
        candidate_key = make_family_key(
            candidate.get("legacy_texture_crc"),
            candidate.get("legacy_formatsize"),
        )
        if candidate_key and candidate_key not in keys:
            keys.append(candidate_key)
    return keys


def binding_family_key(binding):
    canonical_identity = binding.get("canonical_identity") or {}
    return make_family_key(
        canonical_identity.get("sampled_low32"),
        canonical_identity.get("formatsize"),
    )


def unresolved_family_key(unresolved):
    canonical_identity = unresolved.get("canonical_identity") or {}
    return make_family_key(
        canonical_identity.get("sampled_low32"),
        canonical_identity.get("formatsize"),
    )


def summarize_migration_plan(plan):
    families = plan.get("families", [])
    active_pool_counts = Counter(str(family.get("active_pool") or "unknown") for family in families)
    return {
        "family_count": len(families),
        "tier_counts": dict(plan.get("tier_counts", {})),
        "active_pool_counts": dict(active_pool_counts),
    }


def summarize_imported_index(imported_index):
    canonical_records = imported_index.get("canonical_records", [])
    runtime_ready_count = 0
    runtime_proxy_unique_count = 0
    runtime_proxy_candidate_total = 0
    canonical_family_keys = Counter()
    for record in canonical_records:
        if record.get("runtime_ready"):
            runtime_ready_count += 1
        if record.get("runtime_proxy_unique"):
            runtime_proxy_unique_count += 1
        runtime_proxy_candidate_total += int(record.get("runtime_proxy_count", 0) or 0)
        family_key = make_family_key(record.get("sampled_low32"), record.get("formatsize"))
        if family_key:
            canonical_family_keys[family_key] += 1

    return {
        "record_count": len(imported_index.get("records", [])),
        "exact_authority_count": len(imported_index.get("exact_authorities", [])),
        "compatibility_alias_count": len(imported_index.get("compatibility_aliases", [])),
        "unresolved_family_count": len(imported_index.get("unresolved_families", [])),
        "canonical_record_count": len(canonical_records),
        "canonical_sampled_record_count": len(canonical_records),
        "canonical_runtime_ready_count": runtime_ready_count,
        "canonical_runtime_proxy_unique_count": runtime_proxy_unique_count,
        "canonical_runtime_proxy_candidate_total": runtime_proxy_candidate_total,
        "canonical_family_key_count": len(canonical_family_keys),
        "legacy_transport_alias_count": len(imported_index.get("legacy_transport_aliases", [])),
    }


def summarize_package_manifest(package_manifest):
    records = package_manifest.get("records", [])
    family_key_counts = Counter()
    runtime_ready_family_keys = set()
    runtime_ready_record_kind_counts = Counter()
    runtime_deferred_record_kind_counts = Counter()
    for record in records:
        record_kind = str(record.get("record_kind") or "unknown")
        if record.get("runtime_ready"):
            runtime_ready_record_kind_counts[record_kind] += 1
        else:
            runtime_deferred_record_kind_counts[record_kind] += 1
        for family_key in record_family_keys(record):
            family_key_counts[family_key] += 1
            if record.get("runtime_ready"):
                runtime_ready_family_keys.add(family_key)

    return {
        "record_count": int(_manifest_value_or_default(package_manifest, "record_count", 0)),
        "runtime_ready_record_count": int(_manifest_value_or_default(package_manifest, "runtime_ready_record_count", 0)),
        "runtime_deferred_record_count": int(_manifest_value_or_default(package_manifest, "runtime_deferred_record_count", 0)),
        "asset_candidate_total": int(_manifest_value_or_default(package_manifest, "asset_candidate_total", 0)),
        "family_key_count": len(family_key_counts),
        "family_key_counts": dict(sorted(family_key_counts.items())),
        "runtime_ready_family_keys": sorted(runtime_ready_family_keys),
        "runtime_ready_record_kind_counts": dict(
            _manifest_value_or_default(
                package_manifest,
                "runtime_ready_record_kind_counts",
                dict(sorted(runtime_ready_record_kind_counts.items())),
            )
        ),
        "runtime_deferred_record_kind_counts": dict(
            _manifest_value_or_default(
                package_manifest,
                "runtime_deferred_record_kind_counts",
                dict(sorted(runtime_deferred_record_kind_counts.items())),
            )
        ),
        "runtime_ready_native_sampled_record_count": int(
            _manifest_value_or_default(
                package_manifest,
                "runtime_ready_native_sampled_record_count",
                runtime_ready_record_kind_counts.get("canonical-sampled", 0),
            )
        ),
        "runtime_ready_compat_record_count": int(
            _manifest_value_or_default(
                package_manifest,
                "runtime_ready_compat_record_count",
                sum(count for kind, count in runtime_ready_record_kind_counts.items() if kind != "canonical-sampled"),
            )
        ),
        "runtime_deferred_native_sampled_record_count": int(
            _manifest_value_or_default(
                package_manifest,
                "runtime_deferred_native_sampled_record_count",
                runtime_deferred_record_kind_counts.get("canonical-sampled", 0),
            )
        ),
        "runtime_deferred_compat_record_count": int(
            _manifest_value_or_default(
                package_manifest,
                "runtime_deferred_compat_record_count",
                sum(count for kind, count in runtime_deferred_record_kind_counts.items() if kind != "canonical-sampled"),
            )
        ),
        "runtime_ready_record_class": str(
            _manifest_value_or_default(
                package_manifest,
                "runtime_ready_record_class",
                classify_runtime_record_class(
                    _manifest_value_or_default(
                        package_manifest,
                        "runtime_ready_native_sampled_record_count",
                        runtime_ready_record_kind_counts.get("canonical-sampled", 0),
                    ),
                    _manifest_value_or_default(
                        package_manifest,
                        "runtime_ready_compat_record_count",
                        sum(count for kind, count in runtime_ready_record_kind_counts.items() if kind != "canonical-sampled"),
                    ),
                ),
            )
        ),
        "runtime_deferred_record_class": str(
            _manifest_value_or_default(
                package_manifest,
                "runtime_deferred_record_class",
                classify_runtime_record_class(
                    _manifest_value_or_default(
                        package_manifest,
                        "runtime_deferred_native_sampled_record_count",
                        runtime_deferred_record_kind_counts.get("canonical-sampled", 0),
                    ),
                    _manifest_value_or_default(
                        package_manifest,
                        "runtime_deferred_compat_record_count",
                        sum(count for kind, count in runtime_deferred_record_kind_counts.items() if kind != "canonical-sampled"),
                    ),
                ),
            )
        ),
    }


def make_streaming_asset_blob_loader(package_manifest, asset_storage_mode: str = "rgba"):
    cache_views = {}

    def get_cache_view(cache_path_str):
        if cache_path_str not in cache_views:
            cache_path = Path(cache_path_str)
            entries = parse_cache_entries(cache_path)
            exact_index = {}
            generic_index = {}
            for entry in entries:
                checksum64 = int(entry.get("checksum64", 0))
                formatsize = int(entry.get("formatsize", 0))
                exact_index[(checksum64, formatsize)] = entry
                if formatsize == 0 and checksum64 not in generic_index:
                    generic_index[checksum64] = entry
            cache_views[cache_path_str] = {
                "cache_path": cache_path,
                "exact_index": exact_index,
                "generic_index": generic_index,
                "cache_bytes": cache_path.read_bytes() if cache_path.suffix.lower() == ".hts" else None,
            }
        return cache_views[cache_path_str]

    def load_asset_blob(record_index, record, candidate):
        if not bool(record.get("runtime_ready", True)):
            return b""
        cache_view = get_cache_view(candidate["legacy_source_path"])
        checksum64 = int(str(candidate.get("legacy_checksum64") or "0"), 16)
        formatsize = int(candidate.get("legacy_formatsize") or 0)
        entry = cache_view["exact_index"].get((checksum64, formatsize)) or cache_view["generic_index"].get(checksum64)
        if entry is None:
            raise ValueError(f"Missing cache entry for {candidate['replacement_id']}")
        if asset_storage_mode == "legacy":
            return read_entry_blob(cache_view["cache_path"], entry, cache_bytes=cache_view.get("cache_bytes"))
        return decode_entry_rgba8(cache_view["cache_path"], entry, cache_bytes=cache_view.get("cache_bytes"))

    return load_asset_blob


def summarize_requested_family_states(migrate_result, bindings, package_manifest):
    plan = migrate_result.get("plan", {})
    imported_index = migrate_result.get("imported_index", {})
    exact_authority_keys = {
        make_family_key(record.get("match", {}).get("texture_crc"), record.get("match", {}).get("formatsize"))
        for record in imported_index.get("exact_authorities", [])
    }
    compatibility_alias_keys = {
        make_family_key(record.get("match", {}).get("texture_crc"), record.get("match", {}).get("formatsize"))
        for record in imported_index.get("compatibility_aliases", [])
    }
    unresolved_import_keys = {
        make_family_key(record.get("family_low32"), record.get("formatsize"))
        for record in imported_index.get("unresolved_families", [])
    }
    binding_keys = {
        family_key
        for family_key in (
            binding_family_key(binding)
            for binding in bindings.get("bindings", [])
        )
        if family_key
    }
    unresolved_transport_keys = {
        family_key
        for family_key in (
            unresolved_family_key(unresolved)
            for unresolved in bindings.get("unresolved_transport_cases", [])
        )
        if family_key
    }
    package_record_counts = Counter()
    runtime_ready_package_keys = set()
    for record in package_manifest.get("records", []):
        for family_key in record_family_keys(record):
            package_record_counts[family_key] += 1
            if record.get("runtime_ready"):
                runtime_ready_package_keys.add(family_key)

    family_states = []
    import_state_counts = Counter()
    runtime_state_counts = Counter()
    for family in plan.get("families", []):
        family_key = make_family_key(family.get("low32"), family.get("formatsize"))
        if family_key in exact_authority_keys:
            import_state = "exact-authority"
        elif family_key in compatibility_alias_keys:
            import_state = "compatibility-alias"
        elif family_key in unresolved_import_keys:
            import_state = "import-unresolved"
        else:
            import_state = "not-imported"

        if family_key in binding_keys:
            runtime_state = "runtime-bound"
        elif family_key in unresolved_transport_keys:
            runtime_state = "transport-unresolved"
        elif family_key in runtime_ready_package_keys:
            runtime_state = "runtime-ready-package"
        elif family_key in package_record_counts:
            runtime_state = "canonical-only"
        else:
            runtime_state = "diagnostic-only"

        import_state_counts[import_state] += 1
        runtime_state_counts[runtime_state] += 1
        family_states.append(
            {
                "family_key": family_key,
                "low32": normalize_low32(family.get("low32")),
                "formatsize": int(family.get("formatsize", 0)),
                "recommended_tier": family.get("recommended_tier"),
                "active_pool": family.get("active_pool"),
                "import_state": import_state,
                "runtime_state": runtime_state,
                "canonical_record_count": package_record_counts.get(family_key, 0),
                "runtime_ready_package_record": family_key in runtime_ready_package_keys,
            }
        )

    family_states.sort(key=lambda family: family["family_key"] or "")
    return {
        "import_state_counts": dict(import_state_counts),
        "runtime_state_counts": dict(runtime_state_counts),
        "families": family_states,
        "binding_family_keys": sorted(binding_keys),
        "transport_unresolved_family_keys": sorted(unresolved_transport_keys),
    }


def summarize_promotion_blockers(migration_plan_summary, requested_family_states, package_manifest_summary):
    blockers = []
    tier_counts = migration_plan_summary.get("tier_counts", {})
    runtime_state_counts = requested_family_states.get("runtime_state_counts", {})

    blocker_specs = [
        ("missing-active-pool-families", int(tier_counts.get("missing-active-pool", 0))),
        ("ambiguous-import-or-policy-families", int(tier_counts.get("ambiguous-import-or-policy", 0))),
        ("transport-unresolved-families", int(runtime_state_counts.get("transport-unresolved", 0))),
        ("canonical-only-families", int(runtime_state_counts.get("canonical-only", 0))),
        ("diagnostic-only-families", int(runtime_state_counts.get("diagnostic-only", 0))),
        ("no-canonical-package-records", int(migration_plan_summary.get("family_count", 0)) if int(package_manifest_summary.get("record_count", 0)) == 0 else 0),
    ]
    for code, count in blocker_specs:
        if count <= 0:
            continue
        blockers.append({"code": code, "count": count})
    return blockers


PROMOTION_BLOCKER_RUNTIME_STATES = (
    "transport-unresolved",
    "canonical-only",
    "diagnostic-only",
)


def summarize_promotion_blocker_runtime_state_counts(requested_family_states):
    runtime_state_counts = requested_family_states.get("runtime_state_counts") or {}
    blocker_state_counts = {}
    for state_name in PROMOTION_BLOCKER_RUNTIME_STATES:
        count = int(runtime_state_counts.get(state_name, 0) or 0)
        if count > 0:
            blocker_state_counts[state_name] = count
    return blocker_state_counts


def summarize_promotion_blocker_reason_counts(unresolved_family_review_summary):
    blocker_reason_counts = Counter()
    for family in unresolved_family_review_summary.get("families") or []:
        runtime_state = str(family.get("runtime_state") or "")
        if runtime_state not in PROMOTION_BLOCKER_RUNTIME_STATES:
            continue
        reason = str(family.get("reason") or "unknown")
        blocker_reason_counts[reason] += 1
    return dict(sorted(blocker_reason_counts.items()))


def format_nested_count_summary(nested_counts):
    parts = []
    for outer_key, inner_counts in sorted((nested_counts or {}).items()):
        inner_summary = ", ".join(
            f"{inner_key}={count}"
            for inner_key, count in sorted((inner_counts or {}).items())
        ) or "none"
        parts.append(f"{outer_key}[{inner_summary}]")
    return ", ".join(parts) if parts else "none"


def build_family_inventory_payload(report):
    requested_family_states = report.get("requested_family_states") or {}
    return {
        "requested_family_count": int(report.get("requested_family_count") or 0),
        "conversion_outcome": report.get("conversion_outcome"),
        "import_state_counts": requested_family_states.get("import_state_counts") or {},
        "runtime_state_counts": requested_family_states.get("runtime_state_counts") or {},
        "promotion_blockers": report.get("promotion_blockers") or [],
        "promotion_blocker_runtime_state_counts": report.get("promotion_blocker_runtime_state_counts") or {},
        "promotion_blocker_reason_counts": report.get("promotion_blocker_reason_counts") or {},
        "promotion_blocker_reason_unclassified_family_count": int(report.get("promotion_blocker_reason_unclassified_family_count") or 0),
        "unresolved_family_reason_runtime_state_counts": report.get("unresolved_family_reason_runtime_state_counts") or {},
        "unresolved_family_reason_variant_group_count_counts": report.get("unresolved_family_reason_variant_group_count_counts") or {},
        "families": requested_family_states.get("families") or [],
    }


def _get_cache_entry_view(cache_path_str, cache_views):
    if cache_path_str not in cache_views:
        cache_path = Path(cache_path_str)
        entries = parse_cache_entries(cache_path)
        exact_index = {}
        generic_index = {}
        cache_bytes = cache_path.read_bytes() if cache_path.suffix.lower() == ".hts" else None
        for entry in entries:
            checksum64 = int(entry.get("checksum64", 0))
            formatsize = int(entry.get("formatsize", 0))
            exact_index[(checksum64, formatsize)] = entry
            if checksum64 not in generic_index:
                generic_index[checksum64] = entry
        cache_views[cache_path_str] = {
            "exact_index": exact_index,
            "generic_index": generic_index,
            "cache_bytes": cache_bytes,
            "cache_path": cache_path,
        }
    return cache_views[cache_path_str]


def _decode_transport_candidate_rgba(candidate, cache_views):
    source = candidate.get("source") or {}
    cache_path_str = source.get("legacy_source_path")
    if not cache_path_str:
        return None, "missing-legacy-source-path"
    checksum64 = source.get("legacy_checksum64")
    if not checksum64:
        return None, "missing-legacy-checksum64"
    formatsize = int(source.get("legacy_formatsize") or 0)
    try:
        cache_view = _get_cache_entry_view(cache_path_str, cache_views)
    except Exception as exc:
        return None, f"cache-open-failed:{type(exc).__name__}"
    checksum64_value = int(str(checksum64), 16)
    entry = cache_view["exact_index"].get((checksum64_value, formatsize)) or cache_view["generic_index"].get(checksum64_value)
    if entry is None:
        return None, "missing-cache-entry"
    try:
        rgba = decode_entry_rgba8(cache_view["cache_path"], entry, cache_bytes=cache_view["cache_bytes"])
    except Exception as exc:
        return None, f"decode-failed:{type(exc).__name__}"
    return rgba, None


def build_transport_candidate_hash_review(transport_candidates):
    cache_views = {}
    alpha_hashes = []
    pixel_hashes = []
    dims = []
    decode_error_counts = Counter()
    candidate_reviews = []

    for candidate in transport_candidates or []:
        rgba, error = _decode_transport_candidate_rgba(candidate, cache_views)
        width = candidate.get("replacement_asset", {}).get("width")
        height = candidate.get("replacement_asset", {}).get("height")
        dims_value = f"{width}x{height}" if width and height else None
        pixel_sha256 = None
        alpha_normalized_pixel_sha256 = None
        if error is None:
            pixel_sha256 = hashlib.sha256(rgba).hexdigest()
            normalized = bytearray(rgba)
            for i in range(0, len(normalized), 4):
                if normalized[i + 3] == 0:
                    normalized[i + 0] = 0
                    normalized[i + 1] = 0
                    normalized[i + 2] = 0
            alpha_normalized_pixel_sha256 = hashlib.sha256(bytes(normalized)).hexdigest()
            pixel_hashes.append(pixel_sha256)
            alpha_hashes.append(alpha_normalized_pixel_sha256)
            if dims_value:
                dims.append(dims_value)
        else:
            decode_error_counts[error] += 1

        candidate_reviews.append(
            {
                "replacement_id": candidate.get("replacement_id"),
                "legacy_texture_crc": (candidate.get("source") or {}).get("legacy_texture_crc"),
                "legacy_palette_crc": (candidate.get("source") or {}).get("legacy_palette_crc"),
                "variant_group_id": candidate.get("variant_group_id"),
                "dims": dims_value,
                "pixel_sha256": pixel_sha256,
                "alpha_normalized_pixel_sha256": alpha_normalized_pixel_sha256,
                "decode_error": error,
            }
        )

    unique_dims = sorted({value for value in dims if value})
    unique_pixel_hashes = sorted(set(pixel_hashes))
    unique_alpha_hashes = sorted(set(alpha_hashes))
    alpha_histogram = Counter(alpha_hashes)
    pixel_histogram = Counter(pixel_hashes)

    if not transport_candidates:
        hash_review_class = "no-transport-candidates"
    elif decode_error_counts and not unique_alpha_hashes:
        hash_review_class = "hash-unavailable"
    elif len(unique_alpha_hashes) == 1 and len(unique_dims) <= 1:
        hash_review_class = "pixel-identical-single-dim"
    elif len(unique_alpha_hashes) == 1:
        hash_review_class = "pixel-identical-multi-dim"
    elif len(unique_dims) <= 1:
        hash_review_class = "pixel-divergent-single-dim"
    else:
        hash_review_class = "pixel-divergent-multi-dim"

    return {
        "hash_review_class": hash_review_class,
        "decoded_transport_candidate_count": len(alpha_hashes),
        "transport_candidate_hash_error_count": sum(decode_error_counts.values()),
        "transport_candidate_hash_error_counts": dict(sorted(decode_error_counts.items())),
        "transport_candidate_pixel_hash_count": len(unique_pixel_hashes),
        "transport_candidate_alpha_hash_count": len(unique_alpha_hashes),
        "transport_candidate_unique_dims": unique_dims,
        "transport_candidate_alpha_hash_counts": {
            key: count for key, count in sorted(alpha_histogram.items())
        },
        "transport_candidate_pixel_hash_counts": {
            key: count for key, count in sorted(pixel_histogram.items())
        },
        "transport_candidate_hash_candidates": candidate_reviews,
        "_alpha_hashes": unique_alpha_hashes,
    }


def build_unresolved_family_review_payload(migrate_result, requested_family_states):
    imported_index = migrate_result.get("imported_index") or {}
    requested_families = {
        family.get("family_key"): family
        for family in (requested_family_states.get("families") or [])
        if family.get("family_key")
    }
    review_families = []
    reason_counts = Counter()
    runtime_state_counts = Counter()
    import_state_counts = Counter()
    variant_group_count_counts = Counter()
    candidate_replacement_count_counts = Counter()
    canonical_sampled_object_count_counts = Counter()
    reason_runtime_state_counts = defaultdict(Counter)
    reason_variant_group_count_counts = defaultdict(Counter)

    for family in imported_index.get("unresolved_families", []):
        family_key = make_family_key(family.get("family_low32"), family.get("formatsize"))
        requested_state = requested_families.get(family_key, {})
        variant_groups = family.get("variant_groups") or []
        canonical_sampled_objects = family.get("canonical_sampled_objects") or []
        review_entry = {
            "family_key": family_key,
            "low32": normalize_low32(family.get("family_low32")),
            "formatsize": int(family.get("formatsize") or 0),
            "reason": family.get("reason") or "unknown",
            "active_pool": family.get("active_pool") or "unknown",
            "import_state": requested_state.get("import_state") or "unknown",
            "runtime_state": requested_state.get("runtime_state") or "unknown",
            "variant_group_count": len(variant_groups),
            "candidate_replacement_count": len(family.get("candidate_replacement_ids") or []),
            "canonical_sampled_object_count": len(canonical_sampled_objects),
            "active_unique_repl_dim_count": int(family.get("active_unique_repl_dim_count") or 0),
            "active_unique_palette_count": int(family.get("active_unique_palette_count") or 0),
            "active_replacement_dims": family.get("active_replacement_dims") or [],
            "variant_group_dims": [group.get("dims") for group in variant_groups if group.get("dims")],
            "sampled_object_ids": [
                sampled.get("sampled_object_id")
                for sampled in canonical_sampled_objects
                if sampled.get("sampled_object_id")
            ],
        }
        review_families.append(review_entry)
        reason_counts[review_entry["reason"]] += 1
        runtime_state_counts[review_entry["runtime_state"]] += 1
        import_state_counts[review_entry["import_state"]] += 1
        variant_group_count_counts[review_entry["variant_group_count"]] += 1
        candidate_replacement_count_counts[review_entry["candidate_replacement_count"]] += 1
        canonical_sampled_object_count_counts[review_entry["canonical_sampled_object_count"]] += 1
        reason_runtime_state_counts[review_entry["reason"]][review_entry["runtime_state"]] += 1
        reason_variant_group_count_counts[review_entry["reason"]][str(review_entry["variant_group_count"])] += 1

    review_families.sort(key=lambda item: (item["runtime_state"], item["family_key"] or ""))
    return {
        "unresolved_family_count": len(review_families),
        "reason_counts": dict(sorted(reason_counts.items())),
        "import_state_counts": dict(sorted(import_state_counts.items())),
        "runtime_state_counts": dict(sorted(runtime_state_counts.items())),
        "variant_group_count_counts": {
            str(key): count
            for key, count in sorted(variant_group_count_counts.items())
        },
        "candidate_replacement_count_counts": {
            str(key): count
            for key, count in sorted(candidate_replacement_count_counts.items())
        },
        "canonical_sampled_object_count_counts": {
            str(key): count
            for key, count in sorted(canonical_sampled_object_count_counts.items())
        },
        "reason_runtime_state_counts": {
            reason: dict(sorted(inner_counts.items()))
            for reason, inner_counts in sorted(reason_runtime_state_counts.items())
        },
        "reason_variant_group_count_counts": {
            reason: {
                str(key): count
                for key, count in sorted(inner_counts.items(), key=lambda item: int(item[0]))
            }
            for reason, inner_counts in sorted(reason_variant_group_count_counts.items())
        },
        "families": review_families,
    }


def build_transport_candidate_set_signature(transport_candidates):
    replacement_ids = sorted(
        str(candidate.get("replacement_id") or "")
        for candidate in (transport_candidates or [])
        if str(candidate.get("replacement_id") or "")
    )
    if not replacement_ids:
        return None
    return hashlib.sha1("\n".join(replacement_ids).encode("utf-8")).hexdigest()[:16]


def classify_runtime_overlay_blocker_cluster(entry):
    if int(entry.get("linked_unresolved_family_count") or 0) > 0:
        return "linked-import-ambiguity"
    if int(entry.get("candidate_set_equivalent_case_count") or 0) > 0:
        return "candidate-set-equivalent"

    transport_candidate_count = int(entry.get("transport_candidate_count") or 0)
    multi_dim = len(entry.get("transport_candidate_unique_dims") or []) > 1
    if transport_candidate_count >= 16:
        return "large-multi-dim-cluster" if multi_dim else "large-single-dim-cluster"
    if transport_candidate_count <= 4:
        return "small-multi-dim-cluster" if multi_dim else "small-single-dim-cluster"
    return "medium-multi-dim-cluster" if multi_dim else "medium-single-dim-cluster"


def classify_runtime_overlay_action_hint(entry):
    cluster_class = entry.get("blocker_cluster_class") or classify_runtime_overlay_blocker_cluster(entry)
    if cluster_class == "linked-import-ambiguity":
        return "defer-to-import-family-work"
    if cluster_class == "candidate-set-equivalent":
        return "candidate-set-review"
    if cluster_class.startswith("large-"):
        return "defer-large-transport-cluster"
    return "manual-selection-review"


def build_runtime_overlay_review_payload(migrate_result, bindings, report):
    imported_index = migrate_result.get("imported_index") or {}
    requested_families = {
        family.get("family_key"): family
        for family in (report.get("requested_family_states") or {}).get("families", [])
        if family.get("family_key")
    }
    unresolved_family_links = defaultdict(list)
    for family in imported_index.get("unresolved_families", []):
        family_key = make_family_key(family.get("family_low32"), family.get("formatsize"))
        requested_state = requested_families.get(family_key, {})
        link = {
            "family_key": family_key,
            "reason": family.get("reason") or "unknown",
            "runtime_state": requested_state.get("runtime_state") or "unknown",
            "candidate_replacement_count": len(family.get("candidate_replacement_ids") or []),
            "variant_group_count": len(family.get("variant_groups") or []),
        }
        for sampled in family.get("canonical_sampled_objects") or []:
            sampled_object_id = sampled.get("sampled_object_id")
            if sampled_object_id:
                unresolved_family_links[str(sampled_object_id)].append(link)

    review_entries = []
    status_counts = Counter()
    reason_counts = Counter()
    transport_candidate_count_counts = Counter()
    transport_candidate_palette_count_counts = Counter()
    linked_unresolved_family_count_counts = Counter()
    linked_unresolved_runtime_state_totals = Counter()
    linked_unresolved_reason_totals = Counter()
    hash_review_class_counts = Counter()
    transport_candidate_alpha_hash_count_counts = Counter()
    transport_candidate_hash_error_count_counts = Counter()
    identical_alpha_hash_case_count_counts = Counter()
    alpha_hash_overlap_case_count_counts = Counter()
    candidate_set_cluster_size_counts = Counter()
    blocker_cluster_class_counts = Counter()
    action_hint_counts = Counter()

    for unresolved in bindings.get("unresolved_transport_cases", []):
        sampled_object_id = str(unresolved.get("sampled_object_id") or "")
        linked_families = unresolved_family_links.get(sampled_object_id, [])
        linked_runtime_state_counts = Counter(
            link.get("runtime_state") or "unknown"
            for link in linked_families
        )
        linked_reason_counts = Counter(
            link.get("reason") or "unknown"
            for link in linked_families
        )
        transport_candidate_count = int(unresolved.get("transport_candidate_count") or 0)
        transport_candidate_palette_count = int(unresolved.get("transport_candidate_palette_count") or 0)
        hash_review = build_transport_candidate_hash_review(unresolved.get("transport_candidates") or [])
        entry = {
            "policy_key": str(unresolved.get("policy_key") or ""),
            "sampled_object_id": sampled_object_id or None,
            "family_type": unresolved.get("family_type") or "unknown",
            "status": unresolved.get("status") or "unknown",
            "reason": unresolved.get("reason") or "unknown",
            "selection_reason": unresolved.get("selection_reason"),
            "suggested_replacement_id": unresolved.get("suggested_replacement_id"),
            "transport_candidate_count": transport_candidate_count,
            "transport_candidate_palette_count": transport_candidate_palette_count,
            "transport_candidate_dims": unresolved.get("transport_candidate_dims") or [],
            "source_hint_count": len(unresolved.get("source_hint_ids") or []),
            "source_hint_low32_count": len(unresolved.get("source_hint_low32s") or []),
            "source_policy_status_counts": unresolved.get("source_policy_status_counts") or {},
            "linked_unresolved_family_count": len(linked_families),
            "linked_unresolved_family_keys": [
                link.get("family_key")
                for link in linked_families
                if link.get("family_key")
            ],
            "linked_unresolved_runtime_state_counts": dict(sorted(linked_runtime_state_counts.items())),
            "linked_unresolved_reason_counts": dict(sorted(linked_reason_counts.items())),
            "hash_review_class": hash_review["hash_review_class"],
            "decoded_transport_candidate_count": hash_review["decoded_transport_candidate_count"],
            "transport_candidate_hash_error_count": hash_review["transport_candidate_hash_error_count"],
            "transport_candidate_hash_error_counts": hash_review["transport_candidate_hash_error_counts"],
            "transport_candidate_pixel_hash_count": hash_review["transport_candidate_pixel_hash_count"],
            "transport_candidate_alpha_hash_count": hash_review["transport_candidate_alpha_hash_count"],
            "transport_candidate_unique_dims": hash_review["transport_candidate_unique_dims"],
            "transport_candidate_alpha_hash_counts": hash_review["transport_candidate_alpha_hash_counts"],
            "transport_candidate_pixel_hash_counts": hash_review["transport_candidate_pixel_hash_counts"],
            "transport_candidate_hash_candidates": hash_review["transport_candidate_hash_candidates"],
            "candidate_set_signature": build_transport_candidate_set_signature(
                unresolved.get("transport_candidates") or []
            ),
            "_alpha_hashes": hash_review["_alpha_hashes"],
        }
        review_entries.append(entry)
        status_counts[entry["status"]] += 1
        reason_counts[entry["reason"]] += 1
        transport_candidate_count_counts[transport_candidate_count] += 1
        transport_candidate_palette_count_counts[transport_candidate_palette_count] += 1
        linked_unresolved_family_count_counts[entry["linked_unresolved_family_count"]] += 1
        linked_unresolved_runtime_state_totals.update(linked_runtime_state_counts)
        linked_unresolved_reason_totals.update(linked_reason_counts)
        hash_review_class_counts[entry["hash_review_class"]] += 1
        transport_candidate_alpha_hash_count_counts[entry["transport_candidate_alpha_hash_count"]] += 1
        transport_candidate_hash_error_count_counts[entry["transport_candidate_hash_error_count"]] += 1

    alpha_hash_sets = {
        entry["policy_key"]: set(entry.pop("_alpha_hashes", []))
        for entry in review_entries
    }
    candidate_set_clusters = defaultdict(list)
    for entry in review_entries:
        candidate_set_signature = entry.get("candidate_set_signature")
        if candidate_set_signature:
            candidate_set_clusters[candidate_set_signature].append(entry["policy_key"])
    for entry in review_entries:
        policy_key = entry["policy_key"]
        alpha_hashes = alpha_hash_sets.get(policy_key, set())
        identical_policy_keys = []
        overlapping_policy_keys = []
        if alpha_hashes:
            for other_policy_key, other_hashes in alpha_hash_sets.items():
                if other_policy_key == policy_key or not other_hashes:
                    continue
                if alpha_hashes == other_hashes:
                    identical_policy_keys.append(other_policy_key)
                elif alpha_hashes & other_hashes:
                    overlapping_policy_keys.append(other_policy_key)
        entry["identical_alpha_hash_policy_keys"] = sorted(identical_policy_keys)
        entry["identical_alpha_hash_case_count"] = len(identical_policy_keys)
        entry["alpha_hash_overlap_policy_keys"] = sorted(overlapping_policy_keys)
        entry["alpha_hash_overlap_case_count"] = len(overlapping_policy_keys)
        candidate_set_equivalent_policy_keys = []
        candidate_set_signature = entry.get("candidate_set_signature")
        if candidate_set_signature:
            candidate_set_equivalent_policy_keys = sorted(
                other_policy_key
                for other_policy_key in candidate_set_clusters.get(candidate_set_signature, [])
                if other_policy_key != policy_key
            )
        entry["candidate_set_equivalent_policy_keys"] = candidate_set_equivalent_policy_keys
        entry["candidate_set_equivalent_case_count"] = len(candidate_set_equivalent_policy_keys)
        entry["candidate_set_cluster_size"] = len(candidate_set_equivalent_policy_keys) + 1 if candidate_set_signature else 0
        entry["blocker_cluster_class"] = classify_runtime_overlay_blocker_cluster(entry)
        entry["action_hint"] = classify_runtime_overlay_action_hint(entry)
        identical_alpha_hash_case_count_counts[entry["identical_alpha_hash_case_count"]] += 1
        alpha_hash_overlap_case_count_counts[entry["alpha_hash_overlap_case_count"]] += 1
        if entry["candidate_set_cluster_size"] > 0:
            candidate_set_cluster_size_counts[entry["candidate_set_cluster_size"]] += 1
        blocker_cluster_class_counts[entry["blocker_cluster_class"]] += 1
        action_hint_counts[entry["action_hint"]] += 1

    review_entries.sort(key=lambda item: (item["status"], item["policy_key"]))
    return {
        "unresolved_overlay_count": len(review_entries),
        "status_counts": dict(sorted(status_counts.items())),
        "reason_counts": dict(sorted(reason_counts.items())),
        "transport_candidate_count_counts": {
            str(key): count
            for key, count in sorted(transport_candidate_count_counts.items())
        },
        "transport_candidate_palette_count_counts": {
            str(key): count
            for key, count in sorted(transport_candidate_palette_count_counts.items())
        },
        "hash_review_class_counts": dict(sorted(hash_review_class_counts.items())),
        "transport_candidate_alpha_hash_count_counts": {
            str(key): count
            for key, count in sorted(transport_candidate_alpha_hash_count_counts.items())
        },
        "transport_candidate_hash_error_count_counts": {
            str(key): count
            for key, count in sorted(transport_candidate_hash_error_count_counts.items())
        },
        "linked_unresolved_family_count_counts": {
            str(key): count
            for key, count in sorted(linked_unresolved_family_count_counts.items())
        },
        "identical_alpha_hash_case_count_counts": {
            str(key): count
            for key, count in sorted(identical_alpha_hash_case_count_counts.items())
        },
        "alpha_hash_overlap_case_count_counts": {
            str(key): count
            for key, count in sorted(alpha_hash_overlap_case_count_counts.items())
        },
        "candidate_set_cluster_count": len(candidate_set_clusters),
        "candidate_set_cluster_size_counts": {
            str(key): count
            for key, count in sorted(candidate_set_cluster_size_counts.items())
        },
        "blocker_cluster_class_counts": dict(sorted(blocker_cluster_class_counts.items())),
        "action_hint_counts": dict(sorted(action_hint_counts.items())),
        "linked_unresolved_runtime_state_totals": dict(sorted(linked_unresolved_runtime_state_totals.items())),
        "linked_unresolved_reason_totals": dict(sorted(linked_unresolved_reason_totals.items())),
        "entries": review_entries,
    }


def build_runtime_overlay_candidate_set_review_payload(review):
    if not review:
        return {
            "candidate_set_review_group_count": 0,
            "candidate_set_signature_counts": {},
            "groups": [],
        }

    grouped_entries = defaultdict(list)
    for entry in review.get("entries") or []:
        candidate_set_signature = entry.get("candidate_set_signature")
        if not candidate_set_signature:
            continue
        if int(entry.get("candidate_set_cluster_size") or 0) <= 1:
            continue
        grouped_entries[candidate_set_signature].append(entry)

    groups = []
    candidate_set_signature_counts = {}
    for candidate_set_signature, cluster_entries in sorted(grouped_entries.items()):
        policy_keys = sorted(
            entry.get("policy_key")
            for entry in cluster_entries
            if entry.get("policy_key")
        )
        sampled_object_ids = sorted(
            {
                entry.get("sampled_object_id")
                for entry in cluster_entries
                if entry.get("sampled_object_id")
            }
        )
        linked_unresolved_family_keys = sorted(
            {
                family_key
                for entry in cluster_entries
                for family_key in (entry.get("linked_unresolved_family_keys") or [])
                if family_key
            }
        )
        action_hint_counts = Counter(
            entry.get("action_hint") or "unknown"
            for entry in cluster_entries
        )
        reason_counts = Counter(
            entry.get("reason") or "unknown"
            for entry in cluster_entries
        )
        hash_review_class_counts = Counter(
            entry.get("hash_review_class") or "unknown"
            for entry in cluster_entries
        )
        template_transport_proxies = {
            policy_key: {
                "selected_replacement_id": None,
                "status": "selected-review-candidate",
                "justification": f"candidate-set-review:{candidate_set_signature}",
            }
            for policy_key in policy_keys
        }
        groups.append(
            {
                "candidate_set_signature": candidate_set_signature,
                "policy_key_count": len(policy_keys),
                "policy_keys": policy_keys,
                "sampled_object_ids": sampled_object_ids,
                "linked_unresolved_family_keys": linked_unresolved_family_keys,
                "transport_candidate_count": int(cluster_entries[0].get("transport_candidate_count") or 0),
                "transport_candidate_unique_dims": cluster_entries[0].get("transport_candidate_unique_dims") or [],
                "candidate_replacements": cluster_entries[0].get("transport_candidate_hash_candidates") or [],
                "action_hint_counts": dict(sorted(action_hint_counts.items())),
                "reason_counts": dict(sorted(reason_counts.items())),
                "hash_review_class_counts": dict(sorted(hash_review_class_counts.items())),
                "transport_policy_template": {
                    "schema_version": 1,
                    "transport_proxies": template_transport_proxies,
                },
            }
        )
        candidate_set_signature_counts[candidate_set_signature] = len(policy_keys)

    return {
        "candidate_set_review_group_count": len(groups),
        "candidate_set_signature_counts": dict(sorted(candidate_set_signature_counts.items())),
        "groups": groups,
    }


def render_unresolved_family_review_markdown(review):
    lines = [
        "# hts2phrb Unresolved Family Review",
        "",
        f"- Unresolved families: `{review.get('unresolved_family_count')}`",
    ]

    for title, counts in (
        ("Reason Counts", review.get("reason_counts") or {}),
        ("Import State Counts", review.get("import_state_counts") or {}),
        ("Runtime State Counts", review.get("runtime_state_counts") or {}),
        ("Variant Group Counts", review.get("variant_group_count_counts") or {}),
        ("Candidate Replacement Counts", review.get("candidate_replacement_count_counts") or {}),
        ("Canonical Sampled Object Counts", review.get("canonical_sampled_object_count_counts") or {}),
    ):
        lines.extend(["", f"## {title}", ""])
        if counts:
            for key, count in counts.items():
                lines.append(f"- `{key}`: `{count}`")
        else:
            lines.append("- none")

    nested_sections = (
        ("Reason Runtime State Counts", review.get("reason_runtime_state_counts") or {}),
        ("Reason Variant Group Counts", review.get("reason_variant_group_count_counts") or {}),
    )
    for title, nested_counts in nested_sections:
        lines.extend(["", f"## {title}", ""])
        if nested_counts:
            for outer_key, inner_counts in sorted(nested_counts.items()):
                inner_summary = ", ".join(
                    f"`{key}`=`{count}`"
                    for key, count in sorted((inner_counts or {}).items(), key=lambda item: item[0])
                ) or "none"
                lines.append(f"- `{outer_key}`: {inner_summary}")
        else:
            lines.append("- none")

    lines.extend(["", "## Families", ""])
    families = review.get("families") or []
    if not families:
        lines.append("- none")
    else:
        for family in families:
            dims = ", ".join(family.get("variant_group_dims") or []) or "none"
            sampled_object_ids = ", ".join(family.get("sampled_object_ids") or []) or "none"
            lines.append(
                f"- `{family['family_key']}`: reason=`{family['reason']}` "
                f"import=`{family['import_state']}` runtime=`{family['runtime_state']}` "
                f"variant_groups=`{family['variant_group_count']}` "
                f"candidate_replacements=`{family['candidate_replacement_count']}` "
                f"sampled_objects=`{family['canonical_sampled_object_count']}` "
                f"dims=`{dims}` sampled_ids=`{sampled_object_ids}`"
            )
    lines.append("")
    return "\n".join(lines)


def render_runtime_overlay_review_markdown(review):
    lines = [
        "# hts2phrb Runtime Overlay Unresolved Review",
        "",
        f"- Unresolved overlay cases: `{review.get('unresolved_overlay_count')}`",
    ]

    for title, counts in (
        ("Status Counts", review.get("status_counts") or {}),
        ("Reason Counts", review.get("reason_counts") or {}),
        ("Transport Candidate Counts", review.get("transport_candidate_count_counts") or {}),
        ("Transport Candidate Palette Counts", review.get("transport_candidate_palette_count_counts") or {}),
        ("Hash Review Classes", review.get("hash_review_class_counts") or {}),
        ("Transport Candidate Alpha Hash Counts", review.get("transport_candidate_alpha_hash_count_counts") or {}),
        ("Transport Candidate Hash Error Counts", review.get("transport_candidate_hash_error_count_counts") or {}),
        ("Linked Unresolved Family Counts", review.get("linked_unresolved_family_count_counts") or {}),
        ("Identical Alpha Hash Case Counts", review.get("identical_alpha_hash_case_count_counts") or {}),
        ("Alpha Hash Overlap Case Counts", review.get("alpha_hash_overlap_case_count_counts") or {}),
        ("Candidate Set Cluster Size Counts", review.get("candidate_set_cluster_size_counts") or {}),
        ("Blocker Cluster Classes", review.get("blocker_cluster_class_counts") or {}),
        ("Action Hints", review.get("action_hint_counts") or {}),
        ("Linked Unresolved Runtime State Totals", review.get("linked_unresolved_runtime_state_totals") or {}),
        ("Linked Unresolved Reason Totals", review.get("linked_unresolved_reason_totals") or {}),
    ):
        lines.extend(["", f"## {title}", ""])
        if counts:
            for key, count in counts.items():
                lines.append(f"- `{key}`: `{count}`")
        else:
            lines.append("- none")

    lines.extend(["", "## Overlay Cases", ""])
    entries = review.get("entries") or []
    if not entries:
        lines.append("- none")
    else:
        for entry in entries:
            dims = ", ".join(
                f"{item.get('dims')}:{item.get('count')}"
                for item in (entry.get("transport_candidate_dims") or [])
                if item.get("dims")
            ) or "none"
            linked_keys = ", ".join(entry.get("linked_unresolved_family_keys") or []) or "none"
            identical_keys = ", ".join(entry.get("identical_alpha_hash_policy_keys") or []) or "none"
            overlap_keys = ", ".join(entry.get("alpha_hash_overlap_policy_keys") or []) or "none"
            lines.append(
                f"- `{entry['policy_key']}`: status=`{entry['status']}` "
                f"reason=`{entry['reason']}` candidates=`{entry['transport_candidate_count']}` "
                f"candidate_palettes=`{entry['transport_candidate_palette_count']}` "
                f"hash_review=`{entry['hash_review_class']}` alpha_hashes=`{entry['transport_candidate_alpha_hash_count']}` "
                f"cluster=`{entry['blocker_cluster_class']}` action=`{entry['action_hint']}` "
                f"source_hints=`{entry['source_hint_count']}` linked_unresolved_families=`{entry['linked_unresolved_family_count']}` "
                f"dims=`{dims}` linked_keys=`{linked_keys}` identical_alpha_keys=`{identical_keys}` overlap_alpha_keys=`{overlap_keys}`"
            )
    lines.append("")
    return "\n".join(lines)


def render_runtime_overlay_candidate_set_review_markdown(review):
    lines = [
        "# hts2phrb Runtime Overlay Candidate-Set Review",
        "",
        f"- Candidate-set review groups: `{review.get('candidate_set_review_group_count', 0)}`",
        "",
        "## Groups",
        "",
    ]
    groups = review.get("groups") or []
    if not groups:
        lines.append("- none")
        lines.append("")
        return "\n".join(lines)

    for group in groups:
        policy_keys = ", ".join(group.get("policy_keys") or []) or "none"
        sampled_object_ids = ", ".join(group.get("sampled_object_ids") or []) or "none"
        linked_unresolved = ", ".join(group.get("linked_unresolved_family_keys") or []) or "none"
        candidate_replacement_ids = ", ".join(
            candidate.get("replacement_id") or ""
            for candidate in (group.get("candidate_replacements") or [])
            if candidate.get("replacement_id")
        ) or "none"
        lines.append(
            f"- `{group['candidate_set_signature']}`: policy_keys=`{group['policy_key_count']}` "
            f"candidates=`{group['transport_candidate_count']}` "
            f"policy_list=`{policy_keys}` sampled_ids=`{sampled_object_ids}` "
            f"linked_unresolved=`{linked_unresolved}` candidate_replacements=`{candidate_replacement_ids}`"
        )
    lines.append("")
    return "\n".join(lines)


def render_family_inventory_markdown(inventory):
    lines = [
        "# hts2phrb Family Inventory",
        "",
        f"- Requested families: `{inventory.get('requested_family_count')}`",
        f"- Conversion outcome: `{inventory.get('conversion_outcome')}`",
        "",
        "## Runtime State Counts",
        "",
    ]
    runtime_state_counts = inventory.get("runtime_state_counts") or {}
    if runtime_state_counts:
        for state_name, count in sorted(runtime_state_counts.items()):
            lines.append(f"- `{state_name}`: `{count}`")
    else:
        lines.append("- none")

    lines.extend(["", "## Import State Counts", ""])
    import_state_counts = inventory.get("import_state_counts") or {}
    if import_state_counts:
        for state_name, count in sorted(import_state_counts.items()):
            lines.append(f"- `{state_name}`: `{count}`")
    else:
        lines.append("- none")

    lines.extend(["", "## Promotion Blockers", ""])
    blockers = inventory.get("promotion_blockers") or []
    if blockers:
        for blocker in blockers:
            lines.append(f"- `{blocker['code']}`: `{blocker['count']}`")
    else:
        lines.append("- none")
    blocker_runtime_state_counts = inventory.get("promotion_blocker_runtime_state_counts") or {}
    if blocker_runtime_state_counts:
        lines.append(
            "- Blocker runtime states: " + ", ".join(
                f"`{name}`=`{count}`" for name, count in sorted(blocker_runtime_state_counts.items())
            )
        )
    blocker_reason_counts = inventory.get("promotion_blocker_reason_counts") or {}
    if blocker_reason_counts:
        lines.append(
            "- Blocker reasons (review-backed): " + ", ".join(
                f"`{name}`=`{count}`" for name, count in sorted(blocker_reason_counts.items())
            )
        )
    blocker_reason_unclassified = int(inventory.get("promotion_blocker_reason_unclassified_family_count") or 0)
    if blocker_reason_unclassified > 0:
        lines.append(f"- Blocker families without unresolved-review reasons: `{blocker_reason_unclassified}`")
    unresolved_reason_runtime_state_counts = inventory.get("unresolved_family_reason_runtime_state_counts") or {}
    if unresolved_reason_runtime_state_counts:
        lines.append(
            "- Unresolved reasons by runtime state: "
            + format_nested_count_summary(unresolved_reason_runtime_state_counts)
        )
    unresolved_reason_variant_group_count_counts = inventory.get("unresolved_family_reason_variant_group_count_counts") or {}
    if unresolved_reason_variant_group_count_counts:
        lines.append(
            "- Unresolved reasons by variant-group count: "
            + format_nested_count_summary(unresolved_reason_variant_group_count_counts)
        )

    lines.extend(["", "## Families", ""])
    for family in inventory.get("families") or []:
        lines.append(
            f"- `{family['family_key']}`: import=`{family['import_state']}` "
            f"runtime=`{family['runtime_state']}` tier=`{family['recommended_tier']}` "
            f"pool=`{family['active_pool']}` canonical_records=`{family['canonical_record_count']}` "
            f"runtime_ready=`{1 if family.get('runtime_ready_package_record') else 0}`"
        )
    if not (inventory.get("families") or []):
        lines.append("- none")
    lines.append("")
    return "\n".join(lines)


def write_family_inventory_artifacts(output_dir: Path, report: dict):
    inventory = build_family_inventory_payload(report)
    inventory_json_path = output_dir / "hts2phrb-family-inventory.json"
    inventory_markdown_path = output_dir / "hts2phrb-family-inventory.md"
    inventory_json_path.write_text(json.dumps(inventory, indent=2) + "\n")
    inventory_markdown_path.write_text(render_family_inventory_markdown(inventory))
    return inventory_json_path, inventory_markdown_path


def write_unresolved_family_review_artifacts(output_dir: Path, migrate_result: dict, report: dict):
    review = build_unresolved_family_review_payload(
        migrate_result,
        report.get("requested_family_states") or {},
    )
    review_json_path = output_dir / "hts2phrb-unresolved-family-review.json"
    review_markdown_path = output_dir / "hts2phrb-unresolved-family-review.md"
    review_json_path.write_text(json.dumps(review, indent=2) + "\n")
    review_markdown_path.write_text(render_unresolved_family_review_markdown(review))
    return review, review_json_path, review_markdown_path


def write_runtime_overlay_review_artifacts(output_dir: Path, migrate_result: dict, bindings: dict, report: dict):
    review = build_runtime_overlay_review_payload(migrate_result, bindings, report)
    review_json_path = output_dir / "hts2phrb-runtime-overlay-review.json"
    review_markdown_path = output_dir / "hts2phrb-runtime-overlay-review.md"
    review_json_path.write_text(json.dumps(review, indent=2) + "\n")
    review_markdown_path.write_text(render_runtime_overlay_review_markdown(review))
    return review, review_json_path, review_markdown_path


def write_runtime_overlay_candidate_set_review_artifacts(output_dir: Path, runtime_overlay_review: dict):
    review = build_runtime_overlay_candidate_set_review_payload(runtime_overlay_review)
    review_json_path = output_dir / "hts2phrb-runtime-overlay-candidate-set-review.json"
    review_markdown_path = output_dir / "hts2phrb-runtime-overlay-candidate-set-review.md"
    review_json_path.write_text(json.dumps(review, indent=2) + "\n")
    review_markdown_path.write_text(render_runtime_overlay_candidate_set_review_markdown(review))
    return review, review_json_path, review_markdown_path


def summarize_runtime_overlay_blockers(runtime_overlay_review_summary: dict):
    if not runtime_overlay_review_summary:
        return []

    blockers = []
    reason_counts = runtime_overlay_review_summary.get("reason_counts") or {}
    hash_review_class_counts = runtime_overlay_review_summary.get("hash_review_class_counts") or {}
    identical_case_counts = runtime_overlay_review_summary.get("identical_alpha_hash_case_count_counts") or {}

    blocker_specs = [
        ("overlay-proxy-transport-selection-required-cases", int(reason_counts.get("proxy-transport-selection-required", 0))),
        ("overlay-pixel-divergent-single-dim-cases", int(hash_review_class_counts.get("pixel-divergent-single-dim", 0))),
        ("overlay-pixel-divergent-multi-dim-cases", int(hash_review_class_counts.get("pixel-divergent-multi-dim", 0))),
        (
            "overlay-identical-alpha-hash-paired-cases",
            sum(
                int(count)
                for case_count, count in identical_case_counts.items()
                if int(case_count) > 0
            ),
        ),
    ]
    for code, count in blocker_specs:
        if count <= 0:
            continue
        blockers.append({"code": code, "count": count})
    return blockers


def load_migration_result_for_report(report: dict):
    migration_plan_path = Path(report.get("migration_plan_path") or "")
    if not migration_plan_path.exists():
        return None
    return json.loads(migration_plan_path.read_text())


def load_bindings_for_report(report: dict):
    bindings_path_value = report.get("bindings_path")
    if not bindings_path_value:
        return None
    bindings_path = Path(bindings_path_value)
    if not bindings_path.is_file():
        return None
    return json.loads(bindings_path.read_text())


def classify_runtime_record_class(native_count: int, compat_count: int) -> str:
    native_count = int(native_count or 0)
    compat_count = int(compat_count or 0)
    if native_count > 0 and compat_count == 0:
        return "native-sampled-only"
    if native_count == 0 and compat_count > 0:
        return "compat-only"
    if native_count > 0 and compat_count > 0:
        return "mixed-native-and-compat"
    return "none"


def synchronize_report_summary_fields(report: dict):
    package_manifest_path = None
    if report.get("package_dir"):
        candidate = Path(report["package_dir"]) / "package-manifest.json"
        if candidate.exists():
            package_manifest_path = candidate
    if package_manifest_path is not None:
        package_manifest, _ = _load_runtime_manifest_stats(package_manifest_path)
        report["package_manifest_summary"] = summarize_package_manifest(package_manifest)
        report["package_manifest_record_count"] = int(_manifest_value_or_default(package_manifest, "record_count", 0))
        report["package_manifest_runtime_ready_record_count"] = int(
            _manifest_value_or_default(package_manifest, "runtime_ready_record_count", 0)
        )
        report["package_manifest_runtime_deferred_record_count"] = int(
            _manifest_value_or_default(package_manifest, "runtime_deferred_record_count", 0)
        )
    requested_family_states = report.get("requested_family_states") or {}
    package_manifest_summary = report.get("package_manifest_summary") or {}
    imported_index_summary = report.get("imported_index_summary") or {}
    report["import_state_counts"] = requested_family_states.get("import_state_counts") or {}
    report["runtime_state_counts"] = requested_family_states.get("runtime_state_counts") or {}
    report["total_runtime_ms"] = float((report.get("stage_timings_ms") or {}).get("total", 0.0))
    report["total_ms"] = report["total_runtime_ms"]
    report["context_bundle_input_count"] = len(report.get("context_bundle_paths") or [])
    report["context_bundle_resolution_count"] = len(report.get("context_bundle_resolutions") or [])
    report["artifact_contract_version"] = HTS2PHRB_ARTIFACT_VERSION
    report["runtime_overlay_artifacts_emitted"] = bool(
        report.get(
            "runtime_overlay_artifacts_emitted",
            bool(report.get("bindings_path") or report.get("runtime_loader_manifest_path")),
        )
    )
    runtime_ready_total = int(report.get("package_manifest_runtime_ready_record_count") or 0)
    runtime_deferred_total = int(report.get("package_manifest_runtime_deferred_record_count") or 0)
    runtime_ready_native = package_manifest_summary.get("runtime_ready_native_sampled_record_count")
    if runtime_ready_native is None:
        runtime_ready_native = imported_index_summary.get("canonical_runtime_ready_count", 0)
    runtime_deferred_native = package_manifest_summary.get("runtime_deferred_native_sampled_record_count", 0)
    report["package_manifest_runtime_ready_native_sampled_record_count"] = int(runtime_ready_native)
    report["package_manifest_runtime_ready_compat_record_count"] = int(
        package_manifest_summary.get(
            "runtime_ready_compat_record_count",
            max(runtime_ready_total - int(runtime_ready_native), 0),
        )
    )
    report["package_manifest_runtime_deferred_native_sampled_record_count"] = int(runtime_deferred_native)
    report["package_manifest_runtime_deferred_compat_record_count"] = int(
        package_manifest_summary.get(
            "runtime_deferred_compat_record_count",
            max(runtime_deferred_total - int(runtime_deferred_native), 0),
        )
    )
    has_runtime_context_input = bool(report.get("bundle_resolution")) or int(report["context_bundle_resolution_count"]) > 0
    report["context_bundle_class"] = "context-enriched" if has_runtime_context_input else "zero-context"
    report["package_manifest_runtime_ready_record_class"] = classify_runtime_record_class(
        report["package_manifest_runtime_ready_native_sampled_record_count"],
        report["package_manifest_runtime_ready_compat_record_count"],
    )
    report["package_manifest_runtime_deferred_record_class"] = classify_runtime_record_class(
        report["package_manifest_runtime_deferred_native_sampled_record_count"],
        report["package_manifest_runtime_deferred_compat_record_count"],
    )
    promotion_blocker_runtime_state_counts = summarize_promotion_blocker_runtime_state_counts(requested_family_states)
    report["promotion_blocker_runtime_state_counts"] = promotion_blocker_runtime_state_counts
    report["promotion_blocker_family_count"] = sum(
        int(count) for count in promotion_blocker_runtime_state_counts.values()
    )
    promotion_blocker_reason_counts = summarize_promotion_blocker_reason_counts(
        report.get("unresolved_family_review_summary") or {}
    )
    report["promotion_blocker_reason_counts"] = promotion_blocker_reason_counts
    report["promotion_blocker_reason_family_count"] = sum(
        int(count) for count in promotion_blocker_reason_counts.values()
    )
    report["promotion_blocker_reason_unclassified_family_count"] = max(
        int(report["promotion_blocker_family_count"]) - int(report["promotion_blocker_reason_family_count"]),
        0,
    )
    unresolved_family_review_summary = report.get("unresolved_family_review_summary") or {}
    report["unresolved_family_reason_runtime_state_counts"] = (
        unresolved_family_review_summary.get("reason_runtime_state_counts") or {}
    )
    report["unresolved_family_reason_variant_group_count_counts"] = (
        unresolved_family_review_summary.get("reason_variant_group_count_counts") or {}
    )
    runtime_overlay_review_summary = report.get("runtime_overlay_review_summary") or {}
    report["runtime_overlay_unresolved_count"] = int(
        runtime_overlay_review_summary.get("unresolved_overlay_count") or 0
    )
    report["runtime_overlay_reason_counts"] = runtime_overlay_review_summary.get("reason_counts") or {}
    report["runtime_overlay_hash_review_class_counts"] = (
        runtime_overlay_review_summary.get("hash_review_class_counts") or {}
    )
    report["runtime_overlay_candidate_set_cluster_count"] = int(
        runtime_overlay_review_summary.get("candidate_set_cluster_count") or 0
    )
    report["runtime_overlay_candidate_set_cluster_size_counts"] = (
        runtime_overlay_review_summary.get("candidate_set_cluster_size_counts") or {}
    )
    report["runtime_overlay_blocker_cluster_class_counts"] = (
        runtime_overlay_review_summary.get("blocker_cluster_class_counts") or {}
    )
    report["runtime_overlay_action_hint_counts"] = (
        runtime_overlay_review_summary.get("action_hint_counts") or {}
    )
    runtime_overlay_candidate_set_review_summary = (
        report.get("runtime_overlay_candidate_set_review_summary") or {}
    )
    report["runtime_overlay_candidate_set_review_group_count"] = int(
        runtime_overlay_candidate_set_review_summary.get("candidate_set_review_group_count") or 0
    )
    return report


def build_markdown_summary(report):
    runtime_overlay_artifacts_emitted = bool(
        report.get("runtime_overlay_artifacts_emitted",
                   bool(report.get("bindings_path") or report.get("runtime_loader_manifest_path")))
    )
    lines = [
        "# hts2phrb Summary",
        "",
        f"- Outcome: `{report['conversion_outcome']}`",
        f"- Output dir: `{report['output_dir']}`",
        f"- Cache input: `{report['cache_input_path']}`",
        f"- Resolved cache: `{report['cache_path']}`",
        f"- Request mode: `{report['request_mode']}`",
        f"- Context bundle inputs: `{report.get('context_bundle_input_count', len(report.get('context_bundle_paths') or []))}`",
        f"- Expanded context bundles: `{report.get('context_bundle_resolution_count', len(report.get('context_bundle_resolutions') or []))}` (`{report.get('context_bundle_class')}`)",
        f"- Runtime overlay: `{'built' if report['runtime_overlay_built'] else 'skipped'}` (`{report['runtime_overlay_reason']}`)",
        f"- Runtime overlay artifacts emitted: `{'yes' if runtime_overlay_artifacts_emitted else 'no'}`",
        f"- Reused existing artifacts: `{'yes' if report.get('reused_existing') else 'no'}`",
        f"- Requested families: `{report['requested_family_count']}`",
        f"- Canonical package records: `{report['package_manifest_record_count']}`",
        f"- Runtime-ready package records: `{report['package_manifest_runtime_ready_record_count']}`",
        f"- Runtime-ready record class: `{report.get('package_manifest_runtime_ready_record_class')}`",
        f"- Runtime-ready native-sampled records: `{report['package_manifest_runtime_ready_native_sampled_record_count']}`",
        f"- Runtime-ready compat records: `{report['package_manifest_runtime_ready_compat_record_count']}`",
        f"- Runtime-deferred record class: `{report.get('package_manifest_runtime_deferred_record_class')}`",
        f"- Runtime-deferred native-sampled records: `{report['package_manifest_runtime_deferred_native_sampled_record_count']}`",
        f"- Runtime-deferred compat records: `{report['package_manifest_runtime_deferred_compat_record_count']}`",
        f"- Runtime bindings: `{report['binding_count']}`",
        f"- Transport-unresolved families: `{report['unresolved_count']}`",
        f"- Duplicate review inputs: `{len(report.get('duplicate_review_paths') or [])}` (`{report.get('duplicate_review_change_count', 0)}` change(s), `{report.get('duplicate_review_skip_count', 0)}` skipped, state=`{report.get('duplicate_review_state')}`)",
        f"- Alias-group review inputs: `{len(report.get('alias_group_review_paths') or [])}` (`{report.get('alias_group_review_change_count', 0)}` change(s), `{report.get('alias_group_review_skip_count', 0)}` skipped, state=`{report.get('alias_group_review_state')}`)",
        f"- Review profiles: `{len(report.get('review_profile_paths') or [])}`",
        f"- Minimum outcome gate: `{report.get('minimum_outcome') or 'none'}`",
        f"- Require promotable: `{'yes' if report.get('require_promotable') else 'no'}`",
        "",
        "## Import Summary",
        "",
        f"- Exact authorities: `{report['imported_index_summary']['exact_authority_count']}`",
        f"- Compatibility aliases: `{report['imported_index_summary']['compatibility_alias_count']}`",
        f"- Import-unresolved families: `{report['imported_index_summary']['unresolved_family_count']}`",
        f"- Canonical sampled records: `{report['imported_index_summary']['canonical_sampled_record_count']}`",
        f"- Canonical package records: `{report['package_manifest_record_count']}`",
        "",
        "## Family State Counts",
        "",
    ]

    import_state_counts = report["requested_family_states"].get("import_state_counts") or {}
    runtime_state_counts = report["requested_family_states"].get("runtime_state_counts") or {}
    lines.append(
        "- Import states: "
        + (", ".join(f"`{name}`=`{count}`" for name, count in sorted(import_state_counts.items())) or "none")
    )
    lines.append(
        "- Runtime states: "
        + (", ".join(f"`{name}`=`{count}`" for name, count in sorted(runtime_state_counts.items())) or "none")
    )
    if report.get("family_inventory_markdown_path") or report.get("family_inventory_json_path"):
        inventory_refs = []
        if report.get("family_inventory_markdown_path"):
            inventory_refs.append(f"[family inventory]({report['family_inventory_markdown_path']})")
        if report.get("family_inventory_json_path"):
            inventory_refs.append(f"[family inventory json]({report['family_inventory_json_path']})")
        lines.append("- Family inventory: " + ", ".join(inventory_refs))
    if report.get("unresolved_family_review_markdown_path") or report.get("unresolved_family_review_json_path"):
        review_refs = []
        if report.get("unresolved_family_review_markdown_path"):
            review_refs.append(f"[unresolved family review]({report['unresolved_family_review_markdown_path']})")
        if report.get("unresolved_family_review_json_path"):
            review_refs.append(f"[unresolved family review json]({report['unresolved_family_review_json_path']})")
        lines.append("- Unresolved family review: " + ", ".join(review_refs))
    if report.get("runtime_overlay_review_markdown_path") or report.get("runtime_overlay_review_json_path"):
        overlay_review_refs = []
        if report.get("runtime_overlay_review_markdown_path"):
            overlay_review_refs.append(f"[runtime overlay review]({report['runtime_overlay_review_markdown_path']})")
        if report.get("runtime_overlay_review_json_path"):
            overlay_review_refs.append(f"[runtime overlay review json]({report['runtime_overlay_review_json_path']})")
        lines.append("- Runtime overlay review: " + ", ".join(overlay_review_refs))
    if report.get("runtime_overlay_candidate_set_review_markdown_path") or report.get("runtime_overlay_candidate_set_review_json_path"):
        overlay_candidate_review_refs = []
        if report.get("runtime_overlay_candidate_set_review_markdown_path"):
            overlay_candidate_review_refs.append(
                f"[runtime overlay candidate-set review]({report['runtime_overlay_candidate_set_review_markdown_path']})"
            )
        if report.get("runtime_overlay_candidate_set_review_json_path"):
            overlay_candidate_review_refs.append(
                f"[runtime overlay candidate-set review json]({report['runtime_overlay_candidate_set_review_json_path']})"
            )
        lines.append("- Runtime overlay candidate-set review: " + ", ".join(overlay_candidate_review_refs))
    review_profile_paths = report.get("review_profile_paths") or []
    transport_policy_path = report.get("transport_policy_path")
    duplicate_review_paths = report.get("duplicate_review_paths") or []
    alias_group_review_paths = report.get("alias_group_review_paths") or []
    if review_profile_paths or transport_policy_path or duplicate_review_paths or alias_group_review_paths:
        lines.extend(["", "## Review Inputs", ""])
        if review_profile_paths:
            for path in review_profile_paths:
                lines.append(f"- Review profile: `{path}`")
        if transport_policy_path:
            lines.append(f"- Transport policy: `{transport_policy_path}`")
        if duplicate_review_paths:
            for path in duplicate_review_paths:
                lines.append(f"- Duplicate review: `{path}`")
        if alias_group_review_paths:
            for path in alias_group_review_paths:
                lines.append(f"- Alias-group review: `{path}`")
        lines.append(f"- Duplicate review changes: `{report.get('duplicate_review_change_count', 0)}`")
        lines.append(f"- Duplicate review skipped: `{report.get('duplicate_review_skip_count', 0)}`")
        lines.append(f"- Duplicate review state: `{report.get('duplicate_review_state')}`")
        lines.append(f"- Alias-group review changes: `{report.get('alias_group_review_change_count', 0)}`")
        lines.append(f"- Alias-group review skipped: `{report.get('alias_group_review_skip_count', 0)}`")
        lines.append(f"- Alias-group review state: `{report.get('alias_group_review_state')}`")

    runtime_state_examples = {}
    for item in report["requested_family_states"]["families"]:
        runtime_state_examples.setdefault(item["runtime_state"], [])
        if len(runtime_state_examples[item["runtime_state"]]) < 5:
            runtime_state_examples[item["runtime_state"]].append(item["family_key"])

    if runtime_state_examples:
        lines.extend(["", "## Family State Examples", ""])
        for state_name in sorted(runtime_state_examples):
            examples = runtime_state_examples[state_name]
            lines.append(f"- `{state_name}`: `{', '.join(examples)}`")

    lines.extend(["", "## Promotion Blockers", ""])
    blockers = report.get("promotion_blockers") or []
    if blockers:
        for blocker in blockers:
            lines.append(f"- `{blocker['code']}`: `{blocker['count']}`")
    else:
        lines.append("- None")
    blocker_runtime_state_counts = report.get("promotion_blocker_runtime_state_counts") or {}
    if blocker_runtime_state_counts:
        lines.append(
            "- Blocker runtime states: " + ", ".join(
                f"`{name}`=`{count}`" for name, count in sorted(blocker_runtime_state_counts.items())
            )
        )
    blocker_reason_counts = report.get("promotion_blocker_reason_counts") or {}
    if blocker_reason_counts:
        lines.append(
            "- Blocker reasons (review-backed): " + ", ".join(
                f"`{name}`=`{count}`" for name, count in sorted(blocker_reason_counts.items())
            )
        )
    blocker_reason_unclassified = int(report.get("promotion_blocker_reason_unclassified_family_count") or 0)
    if blocker_reason_unclassified > 0:
        lines.append(f"- Blocker families without unresolved-review reasons: `{blocker_reason_unclassified}`")
    unresolved_reason_runtime_state_counts = report.get("unresolved_family_reason_runtime_state_counts") or {}
    if unresolved_reason_runtime_state_counts:
        lines.append(
            "- Unresolved reasons by runtime state: "
            + format_nested_count_summary(unresolved_reason_runtime_state_counts)
        )
    unresolved_reason_variant_group_count_counts = report.get("unresolved_family_reason_variant_group_count_counts") or {}
    if unresolved_reason_variant_group_count_counts:
        lines.append(
            "- Unresolved reasons by variant-group count: "
            + format_nested_count_summary(unresolved_reason_variant_group_count_counts)
        )

    unresolved_review_summary = report.get("unresolved_family_review_summary") or {}
    if unresolved_review_summary:
        lines.extend(["", "## Unresolved Review Summary", ""])
        lines.append(f"- Unresolved families: `{unresolved_review_summary.get('unresolved_family_count', 0)}`")
        reason_counts = unresolved_review_summary.get("reason_counts") or {}
        if reason_counts:
            lines.append(
                "- Reasons: " + ", ".join(
                    f"`{name}`=`{count}`" for name, count in sorted(reason_counts.items())
                )
            )
        variant_group_counts = unresolved_review_summary.get("variant_group_count_counts") or {}
        if variant_group_counts:
            lines.append(
                "- Variant group counts: " + ", ".join(
                    f"`{name}`=`{count}`" for name, count in sorted(variant_group_counts.items(), key=lambda item: int(item[0]))
                )
            )
        reason_runtime_state_counts = unresolved_review_summary.get("reason_runtime_state_counts") or {}
        if reason_runtime_state_counts:
            lines.append(
                "- Reasons by runtime state: " + format_nested_count_summary(reason_runtime_state_counts)
            )
        reason_variant_group_count_counts = unresolved_review_summary.get("reason_variant_group_count_counts") or {}
        if reason_variant_group_count_counts:
            lines.append(
                "- Reasons by variant-group count: " + format_nested_count_summary(reason_variant_group_count_counts)
            )

    runtime_overlay_review_summary = report.get("runtime_overlay_review_summary") or {}
    if runtime_overlay_review_summary:
        lines.extend(["", "## Runtime Overlay Review Summary", ""])
        lines.append(f"- Unresolved overlay cases: `{runtime_overlay_review_summary.get('unresolved_overlay_count', 0)}`")
        status_counts = runtime_overlay_review_summary.get("status_counts") or {}
        if status_counts:
            lines.append(
                "- Statuses: " + ", ".join(
                    f"`{name}`=`{count}`" for name, count in sorted(status_counts.items())
                )
            )
        reason_counts = runtime_overlay_review_summary.get("reason_counts") or {}
        if reason_counts:
            lines.append(
                "- Reasons: " + ", ".join(
                    f"`{name}`=`{count}`" for name, count in sorted(reason_counts.items())
                )
            )
        hash_review_class_counts = runtime_overlay_review_summary.get("hash_review_class_counts") or {}
        if hash_review_class_counts:
            lines.append(
                "- Hash review classes: " + ", ".join(
                    f"`{name}`=`{count}`" for name, count in sorted(hash_review_class_counts.items())
                )
            )
        candidate_counts = runtime_overlay_review_summary.get("transport_candidate_count_counts") or {}
        if candidate_counts:
            lines.append(
                "- Transport candidate counts: " + ", ".join(
                    f"`{name}`=`{count}`" for name, count in sorted(candidate_counts.items(), key=lambda item: int(item[0]))
                )
            )
        candidate_set_cluster_size_counts = runtime_overlay_review_summary.get("candidate_set_cluster_size_counts") or {}
        if candidate_set_cluster_size_counts:
            lines.append(
                "- Candidate-set cluster sizes: " + ", ".join(
                    f"`{name}`=`{count}`" for name, count in sorted(candidate_set_cluster_size_counts.items(), key=lambda item: int(item[0]))
                )
            )
        blocker_cluster_class_counts = runtime_overlay_review_summary.get("blocker_cluster_class_counts") or {}
        if blocker_cluster_class_counts:
            lines.append(
                "- Blocker clusters: " + ", ".join(
                    f"`{name}`=`{count}`" for name, count in sorted(blocker_cluster_class_counts.items())
                )
            )
        action_hint_counts = runtime_overlay_review_summary.get("action_hint_counts") or {}
        if action_hint_counts:
            lines.append(
                "- Action hints: " + ", ".join(
                    f"`{name}`=`{count}`" for name, count in sorted(action_hint_counts.items())
                )
            )
    runtime_overlay_candidate_set_review_summary = report.get("runtime_overlay_candidate_set_review_summary") or {}
    if runtime_overlay_candidate_set_review_summary:
        lines.extend(["", "## Runtime Overlay Candidate-Set Review Summary", ""])
        lines.append(
            f"- Candidate-set review groups: `{runtime_overlay_candidate_set_review_summary.get('candidate_set_review_group_count', 0)}`"
        )
    runtime_overlay_blockers = report.get("runtime_overlay_blockers") or []
    if runtime_overlay_blockers:
        lines.extend(["", "## Runtime Overlay Blockers", ""])
        for blocker in runtime_overlay_blockers:
            lines.append(f"- `{blocker['code']}`: `{blocker['count']}`")

    unresolved_keys = report["requested_family_states"].get("transport_unresolved_family_keys") or []
    if unresolved_keys:
        lines.extend(["", "## Transport-Unresolved Families", ""])
        for family_key in unresolved_keys:
            lines.append(f"- `{family_key}`")

    warnings = report.get("warnings") or []
    if warnings:
        lines.extend(["", "## Warnings", ""])
        for warning in warnings:
            lines.append(f"- {warning}")

    gate_failures = report.get("gate_failures") or []
    lines.extend(["", "## Gate Status", ""])
    if gate_failures:
        for failure in gate_failures:
            lines.append(f"- `{failure['code']}`: {failure['message']}")
    else:
        lines.append("- All requested conversion gates passed.")

    stage_timings = report.get("stage_timings_ms") or {}
    if stage_timings:
        lines.extend(["", "## Stage Timings (ms)", ""])
        for stage_name, value in stage_timings.items():
            lines.append(f"- `{stage_name}`: `{value}`")

    lines.append("")
    return "\n".join(lines)


def build_stdout_summary(report):
    runtime_overlay_artifacts_emitted = bool(
        report.get("runtime_overlay_artifacts_emitted",
                   bool(report.get("bindings_path") or report.get("runtime_loader_manifest_path")))
    )
    blockers = report.get("promotion_blockers") or []
    blocker_summary = ", ".join(f"{item['code']}={item['count']}" for item in blockers) if blockers else "none"
    unresolved_review_summary = report.get("unresolved_family_review_summary") or {}
    unresolved_reason_summary = ", ".join(
        f"{name}={count}"
        for name, count in sorted((unresolved_review_summary.get("reason_counts") or {}).items())
    ) or "none"
    runtime_overlay_review_summary = report.get("runtime_overlay_review_summary") or {}
    overlay_reason_summary = ", ".join(
        f"{name}={count}"
        for name, count in sorted((report.get("runtime_overlay_reason_counts") or {}).items())
    ) or "none"
    overlay_hash_summary = ", ".join(
        f"{name}={count}"
        for name, count in sorted((report.get("runtime_overlay_hash_review_class_counts") or {}).items())
    ) or "none"
    overlay_blocker_summary = ", ".join(
        f"{item['code']}={item['count']}"
        for item in (report.get("runtime_overlay_blockers") or [])
    ) or "none"
    blocker_runtime_state_summary = ", ".join(
        f"{name}={count}"
        for name, count in sorted((report.get("promotion_blocker_runtime_state_counts") or {}).items())
    ) or "none"
    blocker_reason_summary = ", ".join(
        f"{name}={count}"
        for name, count in sorted((report.get("promotion_blocker_reason_counts") or {}).items())
    ) or "none"
    unresolved_reason_runtime_state_summary = format_nested_count_summary(
        report.get("unresolved_family_reason_runtime_state_counts") or {}
    )
    unresolved_reason_variant_group_summary = format_nested_count_summary(
        report.get("unresolved_family_reason_variant_group_count_counts") or {}
    )
    lines = [
        f"hts2phrb: {report['conversion_outcome']}",
        f"output_dir: {report['output_dir']}",
        f"report: {report['report_path']}",
        f"summary: {report['summary_path']}",
        f"request_mode: {report['request_mode']}",
        f"context_bundle_inputs: {report.get('context_bundle_input_count', len(report.get('context_bundle_paths') or []))}",
        f"context_bundles: {report.get('context_bundle_resolution_count', len(report.get('context_bundle_resolutions') or []))}",
        f"context_bundle_class: {report.get('context_bundle_class')}",
        f"runtime_overlay: {'built' if report['runtime_overlay_built'] else 'skipped'} ({report['runtime_overlay_reason']})",
        f"runtime_overlay_artifacts_emitted: {'yes' if runtime_overlay_artifacts_emitted else 'no'}",
        f"reused_existing: {'yes' if report.get('reused_existing') else 'no'}",
        f"requested_families: {report['requested_family_count']}",
        f"package_records: {report['package_manifest_record_count']}",
        f"runtime_ready_package_records: {report['package_manifest_runtime_ready_record_count']}",
        f"runtime_ready_record_class: {report.get('package_manifest_runtime_ready_record_class')}",
        f"runtime_ready_native_sampled_records: {report['package_manifest_runtime_ready_native_sampled_record_count']}",
        f"runtime_ready_compat_records: {report['package_manifest_runtime_ready_compat_record_count']}",
        f"runtime_deferred_record_class: {report.get('package_manifest_runtime_deferred_record_class')}",
        f"runtime_deferred_native_sampled_records: {report['package_manifest_runtime_deferred_native_sampled_record_count']}",
        f"runtime_deferred_compat_records: {report['package_manifest_runtime_deferred_compat_record_count']}",
        f"runtime_bindings: {report['binding_count']}",
        f"transport_unresolved: {report['unresolved_count']}",
        f"transport_policy: {report.get('transport_policy_path') or 'none'}",
        f"review_profiles: {len(report.get('review_profile_paths') or [])}",
        f"duplicate_review_inputs: {len(report.get('duplicate_review_paths') or [])}",
        f"duplicate_review_changes: {report.get('duplicate_review_change_count', 0)}",
        f"duplicate_review_skipped: {report.get('duplicate_review_skip_count', 0)}",
        f"duplicate_review_state: {report.get('duplicate_review_state')}",
        f"alias_group_review_inputs: {len(report.get('alias_group_review_paths') or [])}",
        f"alias_group_review_changes: {report.get('alias_group_review_change_count', 0)}",
        f"alias_group_review_skipped: {report.get('alias_group_review_skip_count', 0)}",
        f"alias_group_review_state: {report.get('alias_group_review_state')}",
        f"unresolved_family_review: {report.get('unresolved_family_review_json_path') or 'none'}",
        f"unresolved_family_count: {unresolved_review_summary.get('unresolved_family_count', 0)}",
        f"unresolved_family_reasons: {unresolved_reason_summary}",
        f"runtime_overlay_review: {report.get('runtime_overlay_review_json_path') or 'none'}",
        f"runtime_overlay_unresolved_count: {runtime_overlay_review_summary.get('unresolved_overlay_count', 0)}",
        f"runtime_overlay_reasons: {overlay_reason_summary}",
        f"runtime_overlay_hash_classes: {overlay_hash_summary}",
        f"runtime_overlay_candidate_set_review_groups: {int(report.get('runtime_overlay_candidate_set_review_group_count') or 0)}",
        f"runtime_overlay_blockers: {overlay_blocker_summary}",
        f"minimum_outcome: {report.get('minimum_outcome') or 'none'}",
        f"require_promotable: {'yes' if report.get('require_promotable') else 'no'}",
        f"promotion_blockers: {blocker_summary}",
        f"promotion_blocker_runtime_states: {blocker_runtime_state_summary}",
        f"promotion_blocker_reasons: {blocker_reason_summary}",
        f"promotion_blocker_reason_unclassified: {int(report.get('promotion_blocker_reason_unclassified_family_count') or 0)}",
        f"unresolved_family_reason_runtime_states: {unresolved_reason_runtime_state_summary}",
        f"unresolved_family_reason_variant_groups: {unresolved_reason_variant_group_summary}",
    ]
    if report.get("family_inventory_markdown_path"):
        lines.append(f"family_inventory: {report['family_inventory_markdown_path']}")
    return "\n".join(lines) + "\n"


CONVERSION_OUTCOME_ORDER = {
    "diagnostic-only": 0,
    "canonical-package-only": 1,
    "partial-runtime-package": 2,
    "promotable-runtime-package": 3,
}


def evaluate_conversion_gates(args, report):
    failures = []
    required_outcome = None
    if args.minimum_outcome:
        required_outcome = args.minimum_outcome
    if args.require_promotable:
        required_outcome = "promotable-runtime-package"
    if required_outcome:
        actual_outcome = str(report["conversion_outcome"])
        actual_rank = CONVERSION_OUTCOME_ORDER.get(actual_outcome, -1)
        required_rank = CONVERSION_OUTCOME_ORDER[required_outcome]
        if actual_rank < required_rank:
            failures.append(
                {
                    "code": "minimum-outcome",
                    "message": f"expected outcome >= {required_outcome}, got {actual_outcome}",
                }
            )

    total_ms = float((report.get("stage_timings_ms") or {}).get("total", 0.0))
    if args.max_total_ms is not None and total_ms > float(args.max_total_ms):
        failures.append(
            {
                "code": "max-total-ms",
                "message": f"expected total <= {float(args.max_total_ms):.3f} ms, got {total_ms:.3f} ms",
            }
        )

    binary_package_bytes = int(report.get("binary_package_bytes", 0))
    if args.max_binary_package_bytes is not None and binary_package_bytes > int(args.max_binary_package_bytes):
        failures.append(
            {
                "code": "max-binary-package-bytes",
                "message": f"expected binary package <= {int(args.max_binary_package_bytes)} bytes, got {binary_package_bytes} bytes",
            }
        )

    if args.expect_context_class is not None:
        actual_context_class = str(report.get("context_bundle_class") or "unknown")
        if actual_context_class != args.expect_context_class:
            failures.append(
                {
                    "code": "expect-context-class",
                    "message": f"expected context class {args.expect_context_class}, got {actual_context_class}",
                }
            )

    if args.expect_runtime_ready_class is not None:
        actual_runtime_ready_class = str(report.get("package_manifest_runtime_ready_record_class") or "unknown")
        if actual_runtime_ready_class != args.expect_runtime_ready_class:
            failures.append(
                {
                    "code": "expect-runtime-ready-class",
                    "message": f"expected runtime-ready class {args.expect_runtime_ready_class}, got {actual_runtime_ready_class}",
                }
            )
    return failures


def resolve_requested_pairs(args, entries, bundle_resolution=None):
    requested_pairs = []
    bundle_context = {}
    bundle_sampled_context = {}
    request_mode = "bundle-or-low32"
    request_was_defaulted = False

    if args.all_families:
        if args.bundle or args.low32 or args.formatsize:
            raise SystemExit("--all-families cannot be combined with --bundle, --low32, or --formatsize.")
        for entry in entries:
            requested_pairs.append((int(entry["texture_crc"]), int(entry["formatsize"])))
        request_mode = "all-families"

    if args.bundle:
        if bundle_resolution is None:
            bundle_resolution = resolve_bundle_input_path(
                Path(args.bundle),
                step_frames=args.bundle_step,
                mode=args.bundle_mode,
            )
        bundle_path = Path(bundle_resolution["resolved_bundle_path"])
        requested_pairs.extend(parse_bundle_families(bundle_path))
        bundle_context = parse_bundle_ci_context(bundle_path)
        bundle_sampled_context = parse_bundle_sampled_object_context(bundle_path)
    else:
        bundle_resolution = None

    if args.low32:
        formatsizes = args.formatsize or []
        if formatsizes and len(formatsizes) != len(args.low32):
            raise SystemExit("--formatsize must either be omitted or match the number of --low32 arguments.")
        for index, low32 in enumerate(args.low32):
            formatsize = formatsizes[index] if formatsizes else 0
            requested_pairs.append((int(low32, 16), formatsize))

    if not requested_pairs:
        for entry in entries:
            requested_pairs.append((int(entry["texture_crc"]), int(entry["formatsize"])))
        request_mode = "implicit-all-families"
        request_was_defaulted = True

    deduped_pairs = []
    seen = set()
    for pair in requested_pairs:
        if pair in seen:
            continue
        seen.add(pair)
        deduped_pairs.append(pair)

    return deduped_pairs, bundle_context, bundle_sampled_context, request_mode, request_was_defaulted, bundle_resolution


def build_conversion(args):
    cache_input_path = Path(args.cache)
    manifest_review_inputs = resolve_manifest_review_inputs(args)
    args.resolved_review_profile_paths = manifest_review_inputs["review_profile_paths"]
    args.resolved_transport_policy_path = manifest_review_inputs["transport_policy_path"]
    args.resolved_duplicate_review_paths = manifest_review_inputs["duplicate_review_paths"]
    args.resolved_alias_group_review_paths = manifest_review_inputs["alias_group_review_paths"]

    started_at = time.perf_counter()
    stage_timings_ms = {}
    reused_stage_names = []

    stage_started = time.perf_counter()
    cache_resolution = resolve_legacy_cache_path(cache_input_path)
    cache_path = Path(cache_resolution["resolved_path"])
    stage_timings_ms["resolve_cache_input"] = round((time.perf_counter() - stage_started) * 1000.0, 3)
    if args.bundle:
        stage_started = time.perf_counter()
        bundle_resolution = resolve_bundle_input_path(
            Path(args.bundle),
            step_frames=args.bundle_step,
            mode=args.bundle_mode,
        )
        stage_timings_ms["resolve_bundle_input"] = round((time.perf_counter() - stage_started) * 1000.0, 3)
    else:
        bundle_resolution = None
    stage_started = time.perf_counter()
    context_bundle_resolutions = []
    for context_bundle in args.context_bundle or []:
        context_bundle_resolutions.extend(
            resolve_context_bundle_input_paths(
                Path(context_bundle),
                step_frames=args.bundle_step,
                mode=args.bundle_mode,
            )
        )
    context_bundle_resolutions = dedupe_context_bundle_resolutions(context_bundle_resolutions)
    stage_timings_ms["resolve_context_bundles"] = round((time.perf_counter() - stage_started) * 1000.0, 3)
    args.context_bundle_resolutions = context_bundle_resolutions
    output_dir, output_dir_was_default = resolve_output_dir(args, cache_input_path, cache_resolution, bundle_resolution=bundle_resolution)
    output_dir.mkdir(parents=True, exist_ok=True)
    progress_path = output_dir / "hts2phrb-progress.json"
    migration_plan_path = output_dir / "migration-plan.json"
    canonical_loader_manifest_path = output_dir / "loader-manifest.json"
    bindings_path = output_dir / "bindings.json"
    runtime_loader_manifest_path = output_dir / "runtime-loader-manifest.json"
    report_path = output_dir / "hts2phrb-report.json"
    summary_path = output_dir / "hts2phrb-summary.md"
    binary_path = output_dir / args.package_name
    package_dir = output_dir / "package"
    progress = {
        "status": "running",
        "artifact_contract_version": HTS2PHRB_ARTIFACT_VERSION,
        "cache_input_path": str(cache_input_path),
        "output_dir": str(output_dir),
        "progress_path": str(progress_path),
        "stage_timings_ms": stage_timings_ms,
    }

    def write_progress(**updates):
        progress.update(updates)
        progress["stage_timings_ms"] = dict(stage_timings_ms)
        progress_path.write_text(json.dumps(progress, indent=2) + "\n")
    pre_request_signature = make_pre_request_signature(args, cache_resolution, bundle_resolution)
    initial_progress_fields = dict(
        cache_path=str(cache_path),
        cache_resolution=cache_resolution,
        cache_selection_reason=cache_resolution["selection_reason"],
        resolved_cache_storage=cache_resolution["resolved_storage"],
        bundle_resolution=bundle_resolution,
        context_bundle_resolutions=context_bundle_resolutions,
        review_profile_paths=[str(path) for path in args.resolved_review_profile_paths],
        duplicate_review_paths=[str(path) for path in args.resolved_duplicate_review_paths],
        alias_group_review_paths=[str(path) for path in args.resolved_alias_group_review_paths],
        pre_request_signature=pre_request_signature,
    )

    if args.reuse_existing:
        reusable_pre_report = try_load_reusable_report_from_pre_signature(report_path, pre_request_signature)
        if reusable_pre_report is not None:
            reusable_pre_report["reused_existing"] = True
            reusable_pre_report["pre_request_signature"] = pre_request_signature
            synchronize_report_summary_fields(reusable_pre_report)
            reusable_pre_report["gate_failures"] = evaluate_conversion_gates(args, reusable_pre_report)
            reusable_pre_report["gate_success"] = not reusable_pre_report["gate_failures"]
            reusable_pre_report["report_path"] = str(report_path)
            reusable_pre_report["summary_path"] = str(summary_path)
            inventory_json_path, inventory_markdown_path = write_family_inventory_artifacts(output_dir, reusable_pre_report)
            reusable_pre_report["family_inventory_json_path"] = str(inventory_json_path)
            reusable_pre_report["family_inventory_markdown_path"] = str(inventory_markdown_path)
            reusable_migrate_result = load_migration_result_for_report(reusable_pre_report)
            if reusable_migrate_result is not None:
                unresolved_review, unresolved_review_json_path, unresolved_review_markdown_path = write_unresolved_family_review_artifacts(
                    output_dir,
                    reusable_migrate_result,
                    reusable_pre_report,
                )
                reusable_pre_report["unresolved_family_review_summary"] = unresolved_review
                reusable_pre_report["unresolved_family_review_json_path"] = str(unresolved_review_json_path)
                reusable_pre_report["unresolved_family_review_markdown_path"] = str(unresolved_review_markdown_path)
                synchronize_report_summary_fields(reusable_pre_report)
                reusable_bindings = load_bindings_for_report(reusable_pre_report)
                if reusable_bindings is not None and int(reusable_pre_report.get("unresolved_count") or 0) > 0:
                    overlay_review, overlay_review_json_path, overlay_review_markdown_path = write_runtime_overlay_review_artifacts(
                        output_dir,
                        reusable_migrate_result,
                        reusable_bindings,
                        reusable_pre_report,
                    )
                    reusable_pre_report["runtime_overlay_review_summary"] = overlay_review
                    reusable_pre_report["runtime_overlay_review_json_path"] = str(overlay_review_json_path)
                    reusable_pre_report["runtime_overlay_review_markdown_path"] = str(overlay_review_markdown_path)
                    overlay_candidate_set_review, overlay_candidate_set_review_json_path, overlay_candidate_set_review_markdown_path = (
                        write_runtime_overlay_candidate_set_review_artifacts(output_dir, overlay_review)
                    )
                    reusable_pre_report["runtime_overlay_candidate_set_review_summary"] = overlay_candidate_set_review
                    reusable_pre_report["runtime_overlay_candidate_set_review_json_path"] = str(
                        overlay_candidate_set_review_json_path
                    )
                    reusable_pre_report["runtime_overlay_candidate_set_review_markdown_path"] = str(
                        overlay_candidate_set_review_markdown_path
                    )
                    reusable_pre_report["runtime_overlay_blockers"] = summarize_runtime_overlay_blockers(overlay_review)
                else:
                    reusable_pre_report.pop("runtime_overlay_review_summary", None)
                    reusable_pre_report.pop("runtime_overlay_review_json_path", None)
                    reusable_pre_report.pop("runtime_overlay_review_markdown_path", None)
                    reusable_pre_report.pop("runtime_overlay_candidate_set_review_summary", None)
                    reusable_pre_report.pop("runtime_overlay_candidate_set_review_json_path", None)
                    reusable_pre_report.pop("runtime_overlay_candidate_set_review_markdown_path", None)
                    reusable_pre_report["runtime_overlay_blockers"] = []
                synchronize_report_summary_fields(reusable_pre_report)
            summary_path.write_text(build_markdown_summary(reusable_pre_report))
            report_path.write_text(json.dumps(reusable_pre_report, indent=2) + "\n")
            write_progress(
                **initial_progress_fields,
                status="reused",
                conversion_outcome=reusable_pre_report["conversion_outcome"],
                report_path=str(report_path),
                summary_path=str(summary_path),
                reused_existing=True,
            )
            return reusable_pre_report

    reusable_progress = try_load_reusable_progress(progress_path, pre_request_signature) if args.reuse_existing else None
    resume_from_progress = reusable_progress is not None and migration_plan_path.exists()
    write_progress(**initial_progress_fields)

    if resume_from_progress:
        migrate_result = json.loads(migration_plan_path.read_text())
        entries = None
        bundle_context = {}
        bundle_sampled_context = {}
        request_mode = str(reusable_progress.get("request_mode") or migrate_result.get("request_mode") or "bundle-or-low32")
        request_was_defaulted = bool(reusable_progress.get("request_was_defaulted", request_mode == "implicit-all-families"))
        requested_pairs = [
            (int(str(family.get("low32") or "0"), 16), int(family.get("formatsize", 0)))
            for family in (migrate_result.get("plan", {}).get("families") or [])
        ]
        request_signature = reusable_progress.get("request_signature") or make_request_signature(
            args,
            cache_resolution,
            request_mode,
            requested_pairs,
            bundle_resolution,
        )
        stage_timings_ms["parse_cache"] = 0.0
        stage_timings_ms["resolve_requested_pairs"] = 0.0
        stage_timings_ms["build_migration_plan"] = 0.0
        reused_stage_names.append("build_migration_plan")
        write_progress(
            entry_count=int(migrate_result.get("entry_count", 0)),
            request_mode=request_mode,
            request_was_defaulted=request_was_defaulted,
            requested_family_count=len(requested_pairs),
            request_signature=request_signature,
            reused_stage_names=reused_stage_names,
            migration_plan_path=str(migration_plan_path),
            migration_plan_summary=summarize_migration_plan(migrate_result["plan"]),
            imported_index_summary=summarize_imported_index(migrate_result["imported_index"]),
        )
    else:
        stage_started = time.perf_counter()
        entries = parse_cache_entries(cache_path)
        stage_timings_ms["parse_cache"] = round((time.perf_counter() - stage_started) * 1000.0, 3)
        write_progress(entry_count=len(entries))

        stage_started = time.perf_counter()
        requested_pairs, bundle_context, bundle_sampled_context, request_mode, request_was_defaulted, bundle_resolution = resolve_requested_pairs(
            args,
            entries,
            bundle_resolution=bundle_resolution,
        )
        for context_resolution in context_bundle_resolutions:
            context_bundle_path = Path(context_resolution["resolved_bundle_path"])
            bundle_context = merge_bundle_ci_contexts(
                parse_bundle_ci_context(context_bundle_path),
                bundle_context,
            )
            bundle_sampled_context = merge_bundle_sampled_object_contexts(
                bundle_sampled_context,
                parse_bundle_sampled_object_context(context_bundle_path),
            )
        stage_timings_ms["resolve_requested_pairs"] = round((time.perf_counter() - stage_started) * 1000.0, 3)
        write_progress(
            request_mode=request_mode,
            request_was_defaulted=request_was_defaulted,
            requested_family_count=len(requested_pairs),
            bundle_path=args.bundle,
            bundle_resolution=bundle_resolution,
            context_bundle_paths=args.context_bundle,
            context_bundle_resolutions=context_bundle_resolutions,
        )
        request_signature = make_request_signature(
            args,
            cache_resolution,
            request_mode,
            requested_pairs,
            bundle_resolution,
        )
        write_progress(request_signature=request_signature)

    if args.reuse_existing:
        reusable_report = try_load_reusable_report(report_path, request_signature)
        if reusable_report is not None:
            reusable_report["reused_existing"] = True
            reusable_report["request_signature"] = request_signature
            reusable_report["pre_request_signature"] = pre_request_signature
            synchronize_report_summary_fields(reusable_report)
            reusable_report["gate_failures"] = evaluate_conversion_gates(args, reusable_report)
            reusable_report["gate_success"] = not reusable_report["gate_failures"]
            reusable_report["report_path"] = str(report_path)
            reusable_report["summary_path"] = str(summary_path)
            inventory_json_path, inventory_markdown_path = write_family_inventory_artifacts(output_dir, reusable_report)
            reusable_report["family_inventory_json_path"] = str(inventory_json_path)
            reusable_report["family_inventory_markdown_path"] = str(inventory_markdown_path)
            reusable_migrate_result = load_migration_result_for_report(reusable_report)
            if reusable_migrate_result is not None:
                unresolved_review, unresolved_review_json_path, unresolved_review_markdown_path = write_unresolved_family_review_artifacts(
                    output_dir,
                    reusable_migrate_result,
                    reusable_report,
                )
                reusable_report["unresolved_family_review_summary"] = unresolved_review
                reusable_report["unresolved_family_review_json_path"] = str(unresolved_review_json_path)
                reusable_report["unresolved_family_review_markdown_path"] = str(unresolved_review_markdown_path)
                synchronize_report_summary_fields(reusable_report)
                reusable_bindings = load_bindings_for_report(reusable_report)
                if reusable_bindings is not None and int(reusable_report.get("unresolved_count") or 0) > 0:
                    overlay_review, overlay_review_json_path, overlay_review_markdown_path = write_runtime_overlay_review_artifacts(
                        output_dir,
                        reusable_migrate_result,
                        reusable_bindings,
                        reusable_report,
                    )
                    reusable_report["runtime_overlay_review_summary"] = overlay_review
                    reusable_report["runtime_overlay_review_json_path"] = str(overlay_review_json_path)
                    reusable_report["runtime_overlay_review_markdown_path"] = str(overlay_review_markdown_path)
                    overlay_candidate_set_review, overlay_candidate_set_review_json_path, overlay_candidate_set_review_markdown_path = (
                        write_runtime_overlay_candidate_set_review_artifacts(output_dir, overlay_review)
                    )
                    reusable_report["runtime_overlay_candidate_set_review_summary"] = overlay_candidate_set_review
                    reusable_report["runtime_overlay_candidate_set_review_json_path"] = str(
                        overlay_candidate_set_review_json_path
                    )
                    reusable_report["runtime_overlay_candidate_set_review_markdown_path"] = str(
                        overlay_candidate_set_review_markdown_path
                    )
                    reusable_report["runtime_overlay_blockers"] = summarize_runtime_overlay_blockers(overlay_review)
                else:
                    reusable_report.pop("runtime_overlay_review_summary", None)
                    reusable_report.pop("runtime_overlay_review_json_path", None)
                    reusable_report.pop("runtime_overlay_review_markdown_path", None)
                    reusable_report.pop("runtime_overlay_candidate_set_review_summary", None)
                    reusable_report.pop("runtime_overlay_candidate_set_review_json_path", None)
                    reusable_report.pop("runtime_overlay_candidate_set_review_markdown_path", None)
                    reusable_report["runtime_overlay_blockers"] = []
                synchronize_report_summary_fields(reusable_report)
            summary_path.write_text(build_markdown_summary(reusable_report))
            report_path.write_text(json.dumps(reusable_report, indent=2) + "\n")
            write_progress(
                status="reused",
                conversion_outcome=reusable_report["conversion_outcome"],
                report_path=str(report_path),
                summary_path=str(summary_path),
                reused_existing=True,
            )
            return reusable_report

    if not resume_from_progress:
        import_policy = {"families": {}}
        if args.import_policy:
            import_policy = load_import_policy(Path(args.import_policy))

        stage_started = time.perf_counter()
        migrate_result = {
            "cache_input_path": str(cache_input_path),
            "cache_path": str(cache_path),
            "cache_resolution": cache_resolution,
            "request_mode": request_mode,
            "entry_count": len(entries),
            "requested_family_count": len(requested_pairs),
            "plan": build_migration_plan(entries, requested_pairs),
            "imported_index": build_imported_index(
                entries,
                requested_pairs,
                cache_path,
                bundle_context,
                bundle_sampled_context,
                import_policy,
            ),
        }
        stage_timings_ms["build_migration_plan"] = round((time.perf_counter() - stage_started) * 1000.0, 3)
        write_progress(
            migration_plan_path=str(migration_plan_path),
            migration_plan_summary=summarize_migration_plan(migrate_result["plan"]),
            imported_index_summary=summarize_imported_index(migrate_result["imported_index"]),
        )

        migration_plan_path.write_text(json.dumps(migrate_result, indent=2) + "\n")

    if resume_from_progress and canonical_loader_manifest_path.exists():
        canonical_loader_manifest = json.loads(canonical_loader_manifest_path.read_text())
        stage_timings_ms["build_canonical_loader_manifest"] = 0.0
        reused_stage_names.append("build_canonical_loader_manifest")
        duplicate_review_changes = reusable_progress.get("duplicate_review_changes", []) if reusable_progress else []
        duplicate_review_skips = reusable_progress.get("duplicate_review_skips", []) if reusable_progress else []
        alias_group_review_changes = reusable_progress.get("alias_group_review_changes", []) if reusable_progress else []
        alias_group_review_skips = reusable_progress.get("alias_group_review_skips", []) if reusable_progress else []
    else:
        stage_started = time.perf_counter()
        canonical_loader_manifest = build_canonical_loader_manifest(migrate_result["imported_index"], migration_plan_path)
        (
            canonical_loader_manifest,
            duplicate_review_changes,
            duplicate_review_skips,
            alias_group_review_changes,
            alias_group_review_skips,
        ) = apply_loader_manifest_reviews(
            canonical_loader_manifest,
            args.resolved_duplicate_review_paths,
            args.resolved_alias_group_review_paths,
        )
        stage_timings_ms["build_canonical_loader_manifest"] = round((time.perf_counter() - stage_started) * 1000.0, 3)
        canonical_loader_manifest_path.write_text(json.dumps(canonical_loader_manifest, indent=2) + "\n")
    write_progress(
        reused_stage_names=reused_stage_names,
        loader_manifest_path=str(canonical_loader_manifest_path),
        loader_manifest_record_count=canonical_loader_manifest.get("record_count", 0),
        duplicate_review_change_count=len(duplicate_review_changes),
        duplicate_review_changes=duplicate_review_changes,
        duplicate_review_skip_count=len(duplicate_review_skips),
        duplicate_review_skips=duplicate_review_skips,
        alias_group_review_change_count=len(alias_group_review_changes),
        alias_group_review_changes=alias_group_review_changes,
        alias_group_review_skip_count=len(alias_group_review_skips),
        alias_group_review_skips=alias_group_review_skips,
    )

    runtime_overlay_planned, runtime_overlay_reason = resolve_runtime_overlay_plan(args, canonical_loader_manifest)
    runtime_overlay_built = runtime_overlay_planned
    runtime_overlay_artifacts_emitted = False
    if runtime_overlay_planned and resume_from_progress and bindings_path.exists():
        bindings = json.loads(bindings_path.read_text())
        stage_timings_ms["build_bindings"] = 0.0
        reused_stage_names.append("build_bindings")
    elif runtime_overlay_planned:
        stage_started = time.perf_counter()
        bindings = build_proxy_bindings(
            migration_plan_path,
            load_transport_policy(args.resolved_transport_policy_path) if args.resolved_transport_policy_path else {},
            auto_select_deterministic_singletons=True,
        )
        stage_timings_ms["build_bindings"] = round((time.perf_counter() - stage_started) * 1000.0, 3)
    else:
        bindings = make_runtime_overlay_placeholder(migration_plan_path, runtime_overlay_reason)
        stage_timings_ms["build_bindings"] = 0.0
    if runtime_overlay_planned and args.runtime_overlay_mode == "auto" and int(bindings.get("binding_count", 0) or 0) <= 0:
        runtime_overlay_built = False
        runtime_overlay_reason = "no-deterministic-bindings"
    if runtime_overlay_built:
        bindings_path.write_text(json.dumps(bindings, indent=2) + "\n")
        runtime_overlay_artifacts_emitted = True
    else:
        if bindings_path.exists():
            bindings_path.unlink()
    write_progress(
        reused_stage_names=reused_stage_names,
        runtime_overlay_built=runtime_overlay_built,
        runtime_overlay_reason=runtime_overlay_reason,
        runtime_overlay_artifacts_emitted=runtime_overlay_artifacts_emitted,
        bindings_path=str(bindings_path) if runtime_overlay_built else None,
        binding_count=bindings.get("binding_count", 0),
        unresolved_count=bindings.get("unresolved_count", 0),
    )

    if runtime_overlay_built and resume_from_progress and runtime_loader_manifest_path.exists():
        runtime_loader_manifest = json.loads(runtime_loader_manifest_path.read_text())
        stage_timings_ms["build_runtime_loader_manifest"] = 0.0
        reused_stage_names.append("build_runtime_loader_manifest")
    elif runtime_overlay_built:
        stage_started = time.perf_counter()
        runtime_loader_manifest = build_loader_manifest(bindings, bindings_path)
        stage_timings_ms["build_runtime_loader_manifest"] = round((time.perf_counter() - stage_started) * 1000.0, 3)
    else:
        runtime_loader_manifest = None
        stage_timings_ms["build_runtime_loader_manifest"] = 0.0
    if runtime_loader_manifest is not None:
        runtime_loader_manifest_path.write_text(json.dumps(runtime_loader_manifest, indent=2) + "\n")
    elif runtime_loader_manifest_path.exists():
        runtime_loader_manifest_path.unlink()
    write_progress(
        reused_stage_names=reused_stage_names,
        runtime_loader_manifest_path=str(runtime_loader_manifest_path) if runtime_loader_manifest is not None else None,
        runtime_loader_manifest_record_count=runtime_loader_manifest.get("record_count", 0) if runtime_loader_manifest is not None else 0,
    )

    def package_progress_callback(snapshot):
        write_progress(
            reused_stage_names=reused_stage_names,
            package_dir=str(package_dir),
            package_manifest_record_count=snapshot.get("records_complete"),
            package_manifest_record_total=snapshot.get("record_total"),
            package_manifest_runtime_ready_record_count=snapshot.get("runtime_ready_record_count"),
            package_manifest_runtime_deferred_record_count=snapshot.get("runtime_deferred_record_count"),
            package_manifest_runtime_ready_record_kind_counts=snapshot.get("runtime_ready_record_kind_counts"),
            package_manifest_runtime_deferred_record_kind_counts=snapshot.get("runtime_deferred_record_kind_counts"),
            package_manifest_runtime_ready_native_sampled_record_count=snapshot.get("runtime_ready_native_sampled_record_count"),
            package_manifest_runtime_ready_compat_record_count=snapshot.get("runtime_ready_compat_record_count"),
            package_manifest_runtime_deferred_native_sampled_record_count=snapshot.get("runtime_deferred_native_sampled_record_count"),
            package_manifest_runtime_deferred_compat_record_count=snapshot.get("runtime_deferred_compat_record_count"),
            package_manifest_runtime_ready_record_class=snapshot.get("runtime_ready_record_class"),
            package_manifest_runtime_deferred_record_class=snapshot.get("runtime_deferred_record_class"),
            package_asset_candidate_total=snapshot.get("asset_candidate_total"),
        )
    stage_started = time.perf_counter()
    package_manifest, asset_rgba_blobs = materialize_package_in_memory(
        canonical_loader_manifest_path,
        package_dir,
        emit_png_assets=False,
        include_asset_blobs=False,
        compute_review_hashes=False,
        progress_callback=package_progress_callback,
        progress_interval=250,
    )
    stage_timings_ms["materialize_package"] = round((time.perf_counter() - stage_started) * 1000.0, 3)
    write_progress(
        reused_stage_names=reused_stage_names,
        package_dir=str(package_dir),
        package_manifest_record_count=package_manifest.get("record_count", 0),
        package_manifest_runtime_ready_record_count=package_manifest.get("runtime_ready_record_count", 0),
        package_manifest_runtime_deferred_record_count=package_manifest.get("runtime_deferred_record_count", 0),
        package_manifest_runtime_ready_record_kind_counts=package_manifest.get("runtime_ready_record_kind_counts"),
        package_manifest_runtime_deferred_record_kind_counts=package_manifest.get("runtime_deferred_record_kind_counts"),
        package_manifest_runtime_ready_native_sampled_record_count=package_manifest.get("runtime_ready_native_sampled_record_count", 0),
        package_manifest_runtime_ready_compat_record_count=package_manifest.get("runtime_ready_compat_record_count", 0),
        package_manifest_runtime_deferred_native_sampled_record_count=package_manifest.get("runtime_deferred_native_sampled_record_count", 0),
        package_manifest_runtime_deferred_compat_record_count=package_manifest.get("runtime_deferred_compat_record_count", 0),
        package_manifest_runtime_ready_record_class=package_manifest.get("runtime_ready_record_class"),
        package_manifest_runtime_deferred_record_class=package_manifest.get("runtime_deferred_record_class"),
    )
    stage_started = time.perf_counter()
    (package_dir / "package-manifest.json").write_text(json.dumps(package_manifest, indent=2) + "\n")
    streaming_asset_blob_loader = make_streaming_asset_blob_loader(package_manifest, asset_storage_mode="legacy")
    binary_result = emit_binary_package_from_manifest(
        package_manifest,
        binary_path,
        asset_rgba_blobs,
        asset_blob_loader=streaming_asset_blob_loader,
        asset_storage_mode="legacy",
    )
    stage_timings_ms["emit_binary_package"] = round((time.perf_counter() - stage_started) * 1000.0, 3)
    stage_timings_ms["total"] = round((time.perf_counter() - started_at) * 1000.0, 3)
    write_progress(
        reused_stage_names=reused_stage_names,
        binary_package=binary_result,
        binary_package_bytes=binary_path.stat().st_size if binary_path.exists() else 0,
    )

    warnings = []
    unresolved_count = len(bindings.get("unresolved_transport_cases", []))
    package_record_count = int(package_manifest.get("record_count", 0))
    runtime_ready_package_record_count = int(package_manifest.get("runtime_ready_record_count", 0))
    if unresolved_count:
        warnings.append(
            f"{unresolved_count} transport case(s) remain unresolved; they were kept as diagnostics and not promoted into runtime bindings."
        )
    if package_record_count == 0:
        warnings.append(
            "No canonical package records were emitted. The conversion remained diagnostic-only."
        )
    elif not runtime_overlay_built:
        if runtime_overlay_reason == "no-runtime-ready-records":
            warnings.append(
                "Runtime overlay was skipped because canonical packaging produced no runtime-ready records for the requested slice."
            )
        elif runtime_overlay_reason == "no-deterministic-bindings":
            if runtime_ready_package_record_count > 0:
                warnings.append(
                    "Runtime overlay was skipped because binding selection produced no deterministic runtime bindings. The generated package still contains runtime-ready canonical records."
                )
            else:
                warnings.append(
                    "Runtime overlay was skipped because binding selection produced no deterministic runtime bindings."
                )
        elif runtime_ready_package_record_count > 0:
            warnings.append(
                "Runtime overlay was skipped because no bundle or explicit runtime context was supplied. The generated package still contains runtime-ready canonical records, but no runtime overlay artifacts were emitted."
            )
        else:
            warnings.append(
                "Runtime overlay was skipped because no bundle or explicit runtime context was supplied. The generated package contains canonical records only."
            )
    elif bindings.get("binding_count", 0) == 0:
        if runtime_ready_package_record_count > 0:
            warnings.append(
                "No deterministic runtime bindings were emitted. The generated package still contains runtime-ready canonical records, but the runtime overlay remains incomplete."
            )
        else:
            warnings.append(
                "No deterministic runtime bindings were emitted. The generated package contains canonical records but no runtime overlay yet."
            )
    if cache_resolution["candidate_count"] > 1:
        warnings.append(
            f"Resolved legacy cache input from {cache_resolution['candidate_count']} directory candidates using {cache_resolution['selection_reason']}: {cache_resolution['resolved_path']}"
        )
    if request_was_defaulted:
        warnings.append(
            "No bundle or explicit family selection was supplied; defaulted to all-families inventory mode."
        )
    if bundle_resolution and bundle_resolution.get("selection_reason") == "validation-summary-first-step":
        warnings.append(
            f"Resolved bundle input from multi-step validation summary by selecting the first step ({bundle_resolution['selected_step_frames']})."
        )

    binding_policy_keys = [str(binding.get("policy_key") or "") for binding in bindings.get("bindings", []) if str(binding.get("policy_key") or "")]
    unresolved_policy_keys = [
        str(unresolved.get("policy_key") or "")
        for unresolved in bindings.get("unresolved_transport_cases", [])
        if str(unresolved.get("policy_key") or "")
    ]
    binding_sampled_low32s = []
    for binding in bindings.get("bindings", []):
        identity = binding.get("canonical_identity") or {}
        sampled_low32 = identity.get("sampled_low32")
        if sampled_low32:
            binding_sampled_low32s.append(str(sampled_low32).lower())
    unresolved_sampled_low32s = []
    for unresolved in bindings.get("unresolved_transport_cases", []):
        sampled_low32 = unresolved.get("sampled_low32")
        if sampled_low32:
            unresolved_sampled_low32s.append(str(sampled_low32).lower())

    migration_plan_summary = summarize_migration_plan(migrate_result["plan"])
    imported_index_summary = summarize_imported_index(migrate_result["imported_index"])
    package_manifest_summary = summarize_package_manifest(package_manifest)
    requested_family_states = summarize_requested_family_states(migrate_result, bindings, package_manifest)
    promotion_blockers = summarize_promotion_blockers(
        migration_plan_summary,
        requested_family_states,
        package_manifest_summary,
    )
    binding_count = bindings.get("binding_count", 0)
    runtime_gap_codes = {"transport-unresolved-families", "canonical-only-families", "diagnostic-only-families"}
    has_runtime_gap = any(blocker["code"] in runtime_gap_codes for blocker in promotion_blockers)
    if package_record_count == 0:
        conversion_outcome = "diagnostic-only"
    elif runtime_ready_package_record_count == 0:
        conversion_outcome = "canonical-package-only"
    elif has_runtime_gap:
        conversion_outcome = "partial-runtime-package"
    else:
        conversion_outcome = "promotable-runtime-package"
    duplicate_review_state = classify_review_overlay_state(
        len(args.resolved_duplicate_review_paths),
        len(duplicate_review_changes),
        len(duplicate_review_skips),
    )
    alias_group_review_state = classify_review_overlay_state(
        len(args.resolved_alias_group_review_paths),
        len(alias_group_review_changes),
        len(alias_group_review_skips),
    )

    report = {
        "cache_input_path": str(cache_input_path),
        "cache_input_kind": cache_resolution["input_kind"],
        "cache_path": str(cache_path),
        "output_dir": str(output_dir),
        "output_dir_was_default": output_dir_was_default,
        "cache_resolution": cache_resolution,
        "cache_selection_reason": cache_resolution["selection_reason"],
        "resolved_cache_storage": cache_resolution["resolved_storage"],
        "bundle_path": args.bundle,
        "bundle_resolution": bundle_resolution,
        "resolved_bundle_path": bundle_resolution["resolved_bundle_path"] if bundle_resolution else None,
        "context_bundle_paths": args.context_bundle,
        "context_bundle_resolutions": context_bundle_resolutions,
        "review_profile_paths": [str(path) for path in args.resolved_review_profile_paths],
        "duplicate_review_paths": [str(path) for path in args.resolved_duplicate_review_paths],
        "alias_group_review_paths": [str(path) for path in args.resolved_alias_group_review_paths],
        "request_mode": request_mode,
        "runtime_overlay_mode": args.runtime_overlay_mode,
        "runtime_overlay_built": runtime_overlay_built,
        "runtime_overlay_reason": runtime_overlay_reason,
        "runtime_overlay_artifacts_emitted": runtime_overlay_artifacts_emitted,
        "requested_family_count": len(requested_pairs),
        "artifact_contract_version": HTS2PHRB_ARTIFACT_VERSION,
        "input_cache_bytes": cache_path.stat().st_size if cache_path.exists() else 0,
        "migration_plan_path": str(migration_plan_path),
        "migration_plan_bytes": migration_plan_path.stat().st_size if migration_plan_path.exists() else 0,
        "loader_manifest_path": str(canonical_loader_manifest_path),
        "loader_manifest_bytes": canonical_loader_manifest_path.stat().st_size if canonical_loader_manifest_path.exists() else 0,
        "runtime_loader_manifest_path": str(runtime_loader_manifest_path) if runtime_loader_manifest is not None else None,
        "runtime_loader_manifest_bytes": runtime_loader_manifest_path.stat().st_size if runtime_loader_manifest is not None and runtime_loader_manifest_path.exists() else 0,
        "migration_plan_summary": migration_plan_summary,
        "bindings_path": str(bindings_path) if runtime_overlay_built else None,
        "bindings_bytes": bindings_path.stat().st_size if runtime_overlay_built and bindings_path.exists() else 0,
        "package_dir": str(package_dir),
        "package_asset_storage": "legacy-blobs",
        "package_manifest_record_count": package_manifest.get("record_count", 0),
        "package_manifest_runtime_ready_record_count": runtime_ready_package_record_count,
        "package_manifest_runtime_deferred_record_count": package_manifest.get("runtime_deferred_record_count", 0),
        "package_manifest_runtime_ready_native_sampled_record_count": package_manifest_summary.get("runtime_ready_native_sampled_record_count", 0),
        "package_manifest_runtime_ready_compat_record_count": package_manifest_summary.get("runtime_ready_compat_record_count", 0),
        "package_manifest_runtime_deferred_native_sampled_record_count": package_manifest_summary.get("runtime_deferred_native_sampled_record_count", 0),
        "package_manifest_runtime_deferred_compat_record_count": package_manifest_summary.get("runtime_deferred_compat_record_count", 0),
        "package_manifest_bytes": (package_dir / "package-manifest.json").stat().st_size if (package_dir / "package-manifest.json").exists() else 0,
        "package_dir_bytes": sum(path.stat().st_size for path in package_dir.rglob("*") if path.is_file()),
        "binding_count": binding_count,
        "binding_policy_keys": binding_policy_keys,
        "binding_sampled_low32s": binding_sampled_low32s,
        "unresolved_count": unresolved_count,
        "unresolved_policy_keys": unresolved_policy_keys,
        "unresolved_sampled_low32s": unresolved_sampled_low32s,
        "duplicate_review_change_count": len(duplicate_review_changes),
        "duplicate_review_changes": duplicate_review_changes,
        "duplicate_review_skip_count": len(duplicate_review_skips),
        "duplicate_review_skips": duplicate_review_skips,
        "duplicate_review_state": duplicate_review_state,
        "alias_group_review_change_count": len(alias_group_review_changes),
        "alias_group_review_changes": alias_group_review_changes,
        "alias_group_review_skip_count": len(alias_group_review_skips),
        "alias_group_review_skips": alias_group_review_skips,
        "alias_group_review_state": alias_group_review_state,
        "imported_index_summary": imported_index_summary,
        "package_manifest_summary": package_manifest_summary,
        "requested_family_states": requested_family_states,
        "promotion_blockers": promotion_blockers,
        "conversion_outcome": conversion_outcome,
        "binary_package": binary_result,
        "binary_package_bytes": binary_path.stat().st_size if binary_path.exists() else 0,
        "import_policy_path": args.import_policy,
        "transport_policy_path": str(args.resolved_transport_policy_path) if args.resolved_transport_policy_path else None,
        "minimum_outcome": args.minimum_outcome,
        "require_promotable": bool(args.require_promotable),
        "stage_timings_ms": stage_timings_ms,
        "warnings": warnings,
        "progress_path": str(progress_path),
        "pre_request_signature": pre_request_signature,
        "request_signature": request_signature,
        "reused_stage_names": reused_stage_names,
        "reused_existing": False,
    }
    synchronize_report_summary_fields(report)
    report["gate_failures"] = evaluate_conversion_gates(args, report)
    report["gate_success"] = not report["gate_failures"]
    inventory_json_path, inventory_markdown_path = write_family_inventory_artifacts(output_dir, report)
    report["family_inventory_json_path"] = str(inventory_json_path)
    report["family_inventory_markdown_path"] = str(inventory_markdown_path)
    unresolved_review, unresolved_review_json_path, unresolved_review_markdown_path = write_unresolved_family_review_artifacts(
        output_dir,
        migrate_result,
        report,
    )
    report["unresolved_family_review_summary"] = unresolved_review
    report["unresolved_family_review_json_path"] = str(unresolved_review_json_path)
    report["unresolved_family_review_markdown_path"] = str(unresolved_review_markdown_path)
    synchronize_report_summary_fields(report)
    if unresolved_count > 0:
        runtime_overlay_review, runtime_overlay_review_json_path, runtime_overlay_review_markdown_path = write_runtime_overlay_review_artifacts(
            output_dir,
            migrate_result,
            bindings,
            report,
        )
        report["runtime_overlay_review_summary"] = runtime_overlay_review
        report["runtime_overlay_review_json_path"] = str(runtime_overlay_review_json_path)
        report["runtime_overlay_review_markdown_path"] = str(runtime_overlay_review_markdown_path)
        runtime_overlay_candidate_set_review, runtime_overlay_candidate_set_review_json_path, runtime_overlay_candidate_set_review_markdown_path = (
            write_runtime_overlay_candidate_set_review_artifacts(output_dir, runtime_overlay_review)
        )
        report["runtime_overlay_candidate_set_review_summary"] = runtime_overlay_candidate_set_review
        report["runtime_overlay_candidate_set_review_json_path"] = str(
            runtime_overlay_candidate_set_review_json_path
        )
        report["runtime_overlay_candidate_set_review_markdown_path"] = str(
            runtime_overlay_candidate_set_review_markdown_path
        )
        report["runtime_overlay_blockers"] = summarize_runtime_overlay_blockers(runtime_overlay_review)
    else:
        report.pop("runtime_overlay_review_summary", None)
        report.pop("runtime_overlay_review_json_path", None)
        report.pop("runtime_overlay_review_markdown_path", None)
        report.pop("runtime_overlay_candidate_set_review_summary", None)
        report.pop("runtime_overlay_candidate_set_review_json_path", None)
        report.pop("runtime_overlay_candidate_set_review_markdown_path", None)
        report["runtime_overlay_blockers"] = []
    synchronize_report_summary_fields(report)
    summary_path.write_text(build_markdown_summary(report))
    report["summary_path"] = str(summary_path)
    report["report_path"] = str(report_path)
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    write_progress(status="complete", conversion_outcome=conversion_outcome, report_path=str(report_path), summary_path=str(summary_path))
    return report


def main():
    parser = argparse.ArgumentParser(
        description="Convert a legacy .hts/.htc hi-res cache into a structured .phrb package using the current safe import pipeline."
    )
    parser.add_argument("--cache", required=True, help="Path to the legacy .hts/.htc cache file or a directory containing one.")
    parser.add_argument("--bundle", help="Optional evidence input. Accepts a bundle directory, traces/hires-evidence.json, validation-summary.json, or validation-summary.md.")
    parser.add_argument("--context-bundle", action="append", default=[], help="Optional evidence input used only to enrich sampled/CI context. Pass multiple times. Does not change requested families unless --bundle is also supplied.")
    parser.add_argument("--bundle-step", type=int, help="When --bundle points to a validation summary, select this step_frames value.")
    parser.add_argument("--bundle-mode", choices=("on", "off"), default="on", help="When --bundle points to a validation summary, choose which bundle side to resolve. Defaults to on.")
    parser.add_argument("--low32", action="append", default=[], help="Optional low32 texture CRC in hex.")
    parser.add_argument("--formatsize", action="append", type=int, default=[], help="Formatsize values paired with --low32 in order.")
    parser.add_argument("--all-families", action="store_true", help="Import every unique low32/formatsize family present in the resolved legacy cache.")
    parser.add_argument("--import-policy", help="Optional import policy JSON for enriched selector/import hints.")
    parser.add_argument("--transport-policy", help="Optional transport policy JSON for explicit proxy selections.")
    parser.add_argument("--duplicate-review", action="append", default=[], help="Review-only duplicate-review JSON to apply to the canonical loader manifest before package emission. Pass multiple times.")
    parser.add_argument("--alias-group-review", action="append", default=[], help="Review-only alias-group review JSON to apply to the canonical loader manifest before package emission. Pass multiple times.")
    parser.add_argument("--review-profile", action="append", default=[], help="Review-only profile JSON that expands duplicate/alias review inputs. Pass multiple times.")
    parser.add_argument("--output-dir", help="Output directory for migration data, bindings, package assets, and the final .phrb. Defaults to ./artifacts/hts2phrb/<resolved-cache>-<path-tag>-<request-mode>.")
    parser.add_argument("--package-name", default="package.phrb", help="Binary package filename relative to --output-dir.")
    parser.add_argument("--runtime-overlay-mode", choices=("auto", "always", "never"), default="auto", help="Whether to build the runtime overlay artifacts. auto builds them when bundle or explicit runtime context is supplied.")
    parser.add_argument("--reuse-existing", action="store_true", help="If a complete prior conversion in --output-dir matches the same request signature, reuse its report/package instead of rebuilding.")
    parser.add_argument(
        "--minimum-outcome",
        choices=tuple(CONVERSION_OUTCOME_ORDER.keys()),
        help="Fail unless the conversion reaches at least this outcome tier. Useful for canonical-package-first gating without requiring a promotable runtime overlay.",
    )
    parser.add_argument("--require-promotable", action="store_true", help="Fail if the conversion outcome is not promotable-runtime-package.")
    parser.add_argument("--max-total-ms", type=float, help="Fail if total reported conversion time exceeds this bound.")
    parser.add_argument("--max-binary-package-bytes", type=int, help="Fail if the emitted .phrb exceeds this size.")
    parser.add_argument("--expect-context-class", choices=("zero-context", "context-enriched"), help="Fail unless the resolved runtime-context class matches this value.")
    parser.add_argument("--expect-runtime-ready-class", choices=("none", "compat-only", "mixed-native-and-compat", "native-sampled-only"), help="Fail unless the runtime-ready package record class matches this value.")
    parser.add_argument("--stdout-format", choices=("summary", "json"), default="summary", help="Stdout format. Use json for machine consumption; summary is the default front-door view.")
    args = parser.parse_args()

    result = build_conversion(args)
    if args.stdout_format == "json":
        sys.stdout.write(json.dumps(result, indent=2) + "\n")
    else:
        sys.stdout.write(build_stdout_summary(result))
    if result["gate_failures"]:
        raise SystemExit("Conversion gates failed: " + "; ".join(failure["message"] for failure in result["gate_failures"]))


if __name__ == "__main__":
    main()
