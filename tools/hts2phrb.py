#!/usr/bin/env python3
import argparse
import hashlib
import json
import sys
import time
from collections import Counter
from pathlib import Path

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

HTS2PHRB_ARTIFACT_VERSION = 5


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
    if args.bundle or args.low32 or args.transport_policy:
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
        "transport_policy_path": normalize_optional_path(args.transport_policy),
        "transport_policy_fingerprint": fingerprint_path(args.transport_policy),
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
        "transport_policy_path": normalize_optional_path(args.transport_policy),
        "transport_policy_fingerprint": fingerprint_path(args.transport_policy),
        "package_name": args.package_name,
        "runtime_overlay_mode": args.runtime_overlay_mode,
    }


def try_load_reusable_report_from_pre_signature(report_path: Path, pre_request_signature: dict):
    if not report_path.exists():
        return None
    report = json.loads(report_path.read_text())
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


def _count_runtime_ready_records(manifest_path: Path):
    manifest = json.loads(manifest_path.read_text())
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
    return {
        "record_count": int(manifest.get("record_count", len(records))),
        "runtime_ready_record_count": int(manifest.get("runtime_ready_record_count", runtime_ready_count)),
        "runtime_deferred_record_count": int(
            manifest.get(
                "runtime_deferred_record_count",
                runtime_deferred_count,
            )
        ),
        "runtime_ready_records_from_entries": runtime_ready_count,
        "runtime_deferred_records_from_entries": runtime_deferred_count,
        "runtime_ready_record_kind_counts": dict(
            manifest.get("runtime_ready_record_kind_counts") or dict(sorted(runtime_ready_record_kind_counts.items()))
        ),
        "runtime_ready_record_kind_counts_from_entries": dict(sorted(runtime_ready_record_kind_counts.items())),
        "runtime_deferred_record_kind_counts": dict(
            manifest.get("runtime_deferred_record_kind_counts") or dict(sorted(runtime_deferred_record_kind_counts.items()))
        ),
        "runtime_deferred_record_kind_counts_from_entries": dict(sorted(runtime_deferred_record_kind_counts.items())),
        "runtime_ready_native_sampled_record_count": int(
            manifest.get("runtime_ready_native_sampled_record_count", runtime_ready_native_sampled_record_count)
        ),
        "runtime_ready_compat_record_count": int(
            manifest.get("runtime_ready_compat_record_count", max(runtime_ready_count - runtime_ready_native_sampled_record_count, 0))
        ),
        "runtime_deferred_native_sampled_record_count": int(
            manifest.get("runtime_deferred_native_sampled_record_count", runtime_deferred_native_sampled_record_count)
        ),
        "runtime_deferred_compat_record_count": int(
            manifest.get("runtime_deferred_compat_record_count", max(runtime_deferred_count - runtime_deferred_native_sampled_record_count, 0))
        ),
        "runtime_ready_record_class": str(
            manifest.get(
                "runtime_ready_record_class",
                classify_runtime_record_class(
                    runtime_ready_native_sampled_record_count,
                    max(runtime_ready_count - runtime_ready_native_sampled_record_count, 0),
                ),
            )
        ),
        "runtime_deferred_record_class": str(
            manifest.get(
                "runtime_deferred_record_class",
                classify_runtime_record_class(
                    runtime_deferred_native_sampled_record_count,
                    max(runtime_deferred_count - runtime_deferred_native_sampled_record_count, 0),
                ),
            )
        ),
    }


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
        "record_count": int(package_manifest.get("record_count", 0)),
        "runtime_ready_record_count": int(package_manifest.get("runtime_ready_record_count", 0)),
        "runtime_deferred_record_count": int(package_manifest.get("runtime_deferred_record_count", 0)),
        "asset_candidate_total": int(package_manifest.get("asset_candidate_total", 0)),
        "family_key_count": len(family_key_counts),
        "family_key_counts": dict(sorted(family_key_counts.items())),
        "runtime_ready_family_keys": sorted(runtime_ready_family_keys),
        "runtime_ready_record_kind_counts": dict(
            package_manifest.get("runtime_ready_record_kind_counts") or dict(sorted(runtime_ready_record_kind_counts.items()))
        ),
        "runtime_deferred_record_kind_counts": dict(
            package_manifest.get("runtime_deferred_record_kind_counts") or dict(sorted(runtime_deferred_record_kind_counts.items()))
        ),
        "runtime_ready_native_sampled_record_count": int(
            package_manifest.get("runtime_ready_native_sampled_record_count", runtime_ready_record_kind_counts.get("canonical-sampled", 0))
        ),
        "runtime_ready_compat_record_count": int(
            package_manifest.get(
                "runtime_ready_compat_record_count",
                sum(count for kind, count in runtime_ready_record_kind_counts.items() if kind != "canonical-sampled"),
            )
        ),
        "runtime_deferred_native_sampled_record_count": int(
            package_manifest.get("runtime_deferred_native_sampled_record_count", runtime_deferred_record_kind_counts.get("canonical-sampled", 0))
        ),
        "runtime_deferred_compat_record_count": int(
            package_manifest.get(
                "runtime_deferred_compat_record_count",
                sum(count for kind, count in runtime_deferred_record_kind_counts.items() if kind != "canonical-sampled"),
            )
        ),
        "runtime_ready_record_class": str(
            package_manifest.get(
                "runtime_ready_record_class",
                classify_runtime_record_class(
                    package_manifest.get("runtime_ready_native_sampled_record_count", runtime_ready_record_kind_counts.get("canonical-sampled", 0)),
                    package_manifest.get(
                        "runtime_ready_compat_record_count",
                        sum(count for kind, count in runtime_ready_record_kind_counts.items() if kind != "canonical-sampled"),
                    ),
                ),
            )
        ),
        "runtime_deferred_record_class": str(
            package_manifest.get(
                "runtime_deferred_record_class",
                classify_runtime_record_class(
                    package_manifest.get("runtime_deferred_native_sampled_record_count", runtime_deferred_record_kind_counts.get("canonical-sampled", 0)),
                    package_manifest.get(
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


def build_family_inventory_payload(report):
    requested_family_states = report.get("requested_family_states") or {}
    return {
        "requested_family_count": int(report.get("requested_family_count") or 0),
        "conversion_outcome": report.get("conversion_outcome"),
        "import_state_counts": requested_family_states.get("import_state_counts") or {},
        "runtime_state_counts": requested_family_states.get("runtime_state_counts") or {},
        "promotion_blockers": report.get("promotion_blockers") or [],
        "families": requested_family_states.get("families") or [],
    }


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
    requested_family_states = report.get("requested_family_states") or {}
    package_manifest_summary = report.get("package_manifest_summary") or {}
    imported_index_summary = report.get("imported_index_summary") or {}
    report["import_state_counts"] = requested_family_states.get("import_state_counts") or {}
    report["runtime_state_counts"] = requested_family_states.get("runtime_state_counts") or {}
    report["total_runtime_ms"] = float((report.get("stage_timings_ms") or {}).get("total", 0.0))
    report["context_bundle_input_count"] = len(report.get("context_bundle_paths") or [])
    report["context_bundle_resolution_count"] = len(report.get("context_bundle_resolutions") or [])
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
        f"minimum_outcome: {report.get('minimum_outcome') or 'none'}",
        f"require_promotable: {'yes' if report.get('require_promotable') else 'no'}",
        f"promotion_blockers: {blocker_summary}",
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
    else:
        stage_started = time.perf_counter()
        canonical_loader_manifest = build_canonical_loader_manifest(migrate_result["imported_index"], migration_plan_path)
        stage_timings_ms["build_canonical_loader_manifest"] = round((time.perf_counter() - stage_started) * 1000.0, 3)
        canonical_loader_manifest_path.write_text(json.dumps(canonical_loader_manifest, indent=2) + "\n")
    write_progress(
        reused_stage_names=reused_stage_names,
        loader_manifest_path=str(canonical_loader_manifest_path),
        loader_manifest_record_count=canonical_loader_manifest.get("record_count", 0),
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
            load_transport_policy(Path(args.transport_policy)) if args.transport_policy else {},
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
        "imported_index_summary": imported_index_summary,
        "package_manifest_summary": package_manifest_summary,
        "requested_family_states": requested_family_states,
        "promotion_blockers": promotion_blockers,
        "conversion_outcome": conversion_outcome,
        "binary_package": binary_result,
        "binary_package_bytes": binary_path.stat().st_size if binary_path.exists() else 0,
        "import_policy_path": args.import_policy,
        "transport_policy_path": args.transport_policy,
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
