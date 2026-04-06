#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

from hires_pack_common import (
    parse_bundle_ci_context,
    parse_bundle_families,
    parse_bundle_sampled_object_context,
    parse_cache_entries,
)
from hires_pack_emit_binary_package import emit_binary_package
from hires_pack_emit_loader_manifest import build_loader_manifest
from hires_pack_emit_proxy_bindings import build_proxy_bindings, load_policy as load_transport_policy
from hires_pack_materialize_package import materialize_package
from hires_pack_migrate import build_imported_index, build_migration_plan, load_import_policy


def resolve_requested_pairs(args):
    requested_pairs = []
    bundle_context = {}
    bundle_sampled_context = {}

    if args.bundle:
        bundle_path = Path(args.bundle)
        requested_pairs.extend(parse_bundle_families(bundle_path))
        bundle_context = parse_bundle_ci_context(bundle_path)
        bundle_sampled_context = parse_bundle_sampled_object_context(bundle_path)

    if args.low32:
        formatsizes = args.formatsize or []
        if formatsizes and len(formatsizes) != len(args.low32):
            raise SystemExit("--formatsize must either be omitted or match the number of --low32 arguments.")
        for index, low32 in enumerate(args.low32):
            formatsize = formatsizes[index] if formatsizes else 0
            requested_pairs.append((int(low32, 16), formatsize))

    if not requested_pairs:
        raise SystemExit("No families requested. Use --bundle and/or --low32.")

    deduped_pairs = []
    seen = set()
    for pair in requested_pairs:
        if pair in seen:
            continue
        seen.add(pair)
        deduped_pairs.append(pair)

    return deduped_pairs, bundle_context, bundle_sampled_context


def build_conversion(args):
    cache_path = Path(args.cache)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    entries = parse_cache_entries(cache_path)
    requested_pairs, bundle_context, bundle_sampled_context = resolve_requested_pairs(args)

    import_policy = {"families": {}}
    if args.import_policy:
        import_policy = load_import_policy(Path(args.import_policy))

    migrate_result = {
        "cache_path": str(cache_path),
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

    migration_plan_path = output_dir / "migration-plan.json"
    migration_plan_path.write_text(json.dumps(migrate_result, indent=2) + "\n")

    bindings = build_proxy_bindings(
        migration_plan_path,
        load_transport_policy(Path(args.transport_policy)) if args.transport_policy else {},
        auto_select_deterministic_singletons=True,
    )
    bindings_path = output_dir / "bindings.json"
    bindings_path.write_text(json.dumps(bindings, indent=2) + "\n")

    loader_manifest = build_loader_manifest(bindings, bindings_path)
    loader_manifest_path = output_dir / "loader-manifest.json"
    loader_manifest_path.write_text(json.dumps(loader_manifest, indent=2) + "\n")

    package_dir = output_dir / "package"
    package_manifest = materialize_package(loader_manifest_path, package_dir)
    binary_path = output_dir / args.package_name
    binary_result = emit_binary_package(package_dir, binary_path)

    warnings = []
    unresolved_count = len(bindings.get("unresolved_transport_cases", []))
    if unresolved_count:
        warnings.append(
            f"{unresolved_count} transport case(s) remain unresolved; they were kept as diagnostics and not promoted into runtime bindings."
        )
    if bindings.get("binding_count", 0) == 0:
        warnings.append(
            "No deterministic runtime bindings were emitted. The generated package is structurally valid but contains no promotable runtime records yet."
        )

    report = {
        "cache_path": str(cache_path),
        "bundle_path": args.bundle,
        "requested_family_count": len(requested_pairs),
        "migration_plan_path": str(migration_plan_path),
        "bindings_path": str(bindings_path),
        "loader_manifest_path": str(loader_manifest_path),
        "package_dir": str(package_dir),
        "package_manifest_record_count": package_manifest.get("record_count", 0),
        "binding_count": bindings.get("binding_count", 0),
        "unresolved_count": unresolved_count,
        "binary_package": binary_result,
        "import_policy_path": args.import_policy,
        "transport_policy_path": args.transport_policy,
        "warnings": warnings,
    }
    report_path = output_dir / "hts2phrb-report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    report["report_path"] = str(report_path)
    return report


def main():
    parser = argparse.ArgumentParser(
        description="Convert a legacy .hts/.htc hi-res cache into a structured .phrb package using the current safe import pipeline."
    )
    parser.add_argument("--cache", required=True, help="Path to the legacy .hts or .htc cache.")
    parser.add_argument("--bundle", help="Optional strict bundle path; imports requested low32/fs families from traces/hires-evidence.json.")
    parser.add_argument("--low32", action="append", default=[], help="Optional low32 texture CRC in hex.")
    parser.add_argument("--formatsize", action="append", type=int, default=[], help="Formatsize values paired with --low32 in order.")
    parser.add_argument("--import-policy", help="Optional import policy JSON for enriched selector/import hints.")
    parser.add_argument("--transport-policy", help="Optional transport policy JSON for explicit proxy selections.")
    parser.add_argument("--output-dir", required=True, help="Output directory for migration data, bindings, package assets, and the final .phrb.")
    parser.add_argument("--package-name", default="package.phrb", help="Binary package filename relative to --output-dir.")
    args = parser.parse_args()

    result = build_conversion(args)
    sys.stdout.write(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
