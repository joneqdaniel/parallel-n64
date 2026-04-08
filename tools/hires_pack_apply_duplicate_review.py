#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

from hires_pack_emit_binary_package import emit_binary_package
from hires_pack_materialize_package import materialize_package


def load_json(path: Path):
    return json.loads(path.read_text())


def dedupe_loader_manifest(loader_manifest: dict, review_docs: list[dict]):
    records = loader_manifest.get("records") or []
    record_by_key = {
        (
            str((record.get("canonical_identity") or {}).get("sampled_low32") or "").lower(),
            str(record.get("policy_key") or ""),
        ): record
        for record in records
    }
    changes = []

    for review in review_docs:
        recommendation = review.get("recommendation")
        if recommendation != "keep-runtime-winner-rule-and-defer-offline-dedupe":
            raise SystemExit(f"unsupported duplicate review recommendation: {recommendation!r}")

        bucket = review.get("duplicate_bucket") or {}
        sampled_low32 = str(review.get("sampled_low32") or "").lower()
        policy_key = str(bucket.get("policy") or "")
        selector = str(review.get("selector") or "").lower()
        active_replacement_id = str(bucket.get("replacement_id") or "")
        allowed_ids = set(review.get("unique_selector_replacement_ids") or [])

        key = (sampled_low32, policy_key)
        record = record_by_key.get(key)
        if record is None:
            raise SystemExit(f"record not found for sampled_low32={sampled_low32} policy={policy_key}")

        kept_candidates = []
        removed_candidates = []
        for candidate in record.get("asset_candidates") or []:
            candidate_selector = str(candidate.get("selector_checksum64") or "").lower()
            replacement_id = str(candidate.get("replacement_id") or "")
            if candidate_selector == selector and replacement_id in allowed_ids and replacement_id != active_replacement_id:
                removed_candidates.append(
                    {
                        "replacement_id": replacement_id,
                        "selector_checksum64": candidate_selector,
                        "legacy_texture_crc": candidate.get("legacy_texture_crc"),
                        "variant_group_id": candidate.get("variant_group_id"),
                    }
                )
                continue
            kept_candidates.append(candidate)

        if not removed_candidates:
            raise SystemExit(
                f"duplicate review for sampled_low32={sampled_low32} selector={selector} removed no candidates"
            )

        record["asset_candidates"] = kept_candidates
        record["asset_candidate_count"] = len(kept_candidates)
        changes.append(
            {
                "sampled_low32": sampled_low32,
                "policy_key": policy_key,
                "selector": selector,
                "active_replacement_id": active_replacement_id,
                "removed_candidates": removed_candidates,
                "kept_candidate_count": len(kept_candidates),
            }
        )

    loader_manifest["record_count"] = len(records)
    return loader_manifest, changes


def main():
    parser = argparse.ArgumentParser(description="Apply review-only duplicate dedupe decisions to a selected package loader manifest.")
    parser.add_argument("--loader-manifest", required=True, help="Source loader-manifest.json")
    parser.add_argument("--duplicate-review", action="append", required=True, help="One or more duplicate review JSON files")
    parser.add_argument("--output-dir", required=True, help="Output directory for candidate loader/package artifacts")
    parser.add_argument("--package-name", default="package.phrb", help="Binary package filename relative to output-dir")
    args = parser.parse_args()

    loader_manifest_path = Path(args.loader_manifest)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    loader_manifest = load_json(loader_manifest_path)
    review_docs = [load_json(Path(path)) for path in args.duplicate_review]
    updated_manifest, changes = dedupe_loader_manifest(loader_manifest, review_docs)

    output_loader_manifest = output_dir / "loader-manifest.json"
    output_loader_manifest.write_text(json.dumps(updated_manifest, indent=2) + "\n")

    package_dir = output_dir / "package"
    package_manifest = materialize_package(output_loader_manifest, package_dir)
    binary_path = output_dir / args.package_name
    binary_result = emit_binary_package(package_dir, binary_path)

    result = {
        "source_loader_manifest_path": str(loader_manifest_path),
        "duplicate_review_paths": args.duplicate_review,
        "output_loader_manifest_path": str(output_loader_manifest),
        "package_dir": str(package_dir),
        "package_manifest_record_count": package_manifest.get("record_count"),
        "applied_changes": changes,
        "binary_package": binary_result,
    }
    sys.stdout.write(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
