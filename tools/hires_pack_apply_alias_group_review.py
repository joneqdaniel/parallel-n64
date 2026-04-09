#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

from hires_pack_emit_binary_package import emit_binary_package
from hires_pack_materialize_package import materialize_package


def load_json(path: Path):
    return json.loads(path.read_text())


def resolve_record_for_review(records: list[dict], record_by_key: dict, sampled_low32: str, policy_key: str):
    record = record_by_key.get((sampled_low32, policy_key))
    if record is not None:
        return record, "policy-key-exact"

    sampled_matches = [
        candidate
        for candidate in records
        if str((candidate.get("canonical_identity") or {}).get("sampled_low32") or "").lower() == sampled_low32
    ]
    if len(sampled_matches) == 1:
        return sampled_matches[0], "sampled-low32-unique"
    if not sampled_matches:
        raise SystemExit(f"record not found for sampled_low32={sampled_low32} policy={policy_key}")

    matched_policy_keys = sorted(str(candidate.get("policy_key") or "") for candidate in sampled_matches)
    raise SystemExit(
        f"multiple records found for sampled_low32={sampled_low32} policy={policy_key}; "
        f"candidates={matched_policy_keys}"
    )


def dedupe_strings(values):
    seen = set()
    rows = []
    for value in values:
        if not value or value in seen:
            continue
        seen.add(value)
        rows.append(value)
    return rows


def resolve_alias_targets(review: dict):
    canonical_replacement_id = str(review.get("suggested_canonical_replacement_id") or "")
    alias_replacement_ids = [
        str(value or "")
        for value in (review.get("suggested_alias_replacement_ids") or [])
        if str(value or "")
    ]
    if canonical_replacement_id and alias_replacement_ids:
        return canonical_replacement_id, dedupe_strings(alias_replacement_ids)

    unique_group_ids = [
        str(value or "")
        for value in (review.get("unique_group_replacement_ids") or [])
        if str(value or "")
    ]
    repeated_counts = {
        str(key or ""): int(value or 0)
        for key, value in (review.get("repeated_replacement_ids") or {}).items()
        if str(key or "")
    }
    if unique_group_ids:
        canonical_replacement_id = sorted(
            unique_group_ids,
            key=lambda replacement_id: (-repeated_counts.get(replacement_id, 0), replacement_id),
        )[0]
        alias_replacement_ids = [
            replacement_id for replacement_id in unique_group_ids if replacement_id != canonical_replacement_id
        ]
        if alias_replacement_ids:
            return canonical_replacement_id, alias_replacement_ids

    raise SystemExit(
        "alias-group review is missing canonical or alias ids and could not derive them from unique_group_replacement_ids"
    )


def apply_alias_group_reviews(loader_manifest: dict, review_docs: list[dict]):
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
        if recommendation != "keep-selectors-distinct-and-consider-asset-level-dedupe":
            raise SystemExit(f"unsupported alias-group review recommendation: {recommendation!r}")

        sampled_low32 = str(review.get("sampled_low32") or "").lower()
        policy_key = str(review.get("policy_key") or "")
        canonical_replacement_id, alias_replacement_ids = resolve_alias_targets(review)
        alias_replacement_ids = set(alias_replacement_ids)

        record, record_resolution = resolve_record_for_review(records, record_by_key, sampled_low32, policy_key)

        canonical_template = None
        for candidate in record.get("asset_candidates") or []:
            if str(candidate.get("replacement_id") or "") == canonical_replacement_id:
                canonical_template = dict(candidate)
                break
        if canonical_template is None:
            raise SystemExit(
                f"canonical replacement_id {canonical_replacement_id} not found for sampled_low32={sampled_low32} policy={policy_key}"
            )

        applied = []
        for candidate in record.get("asset_candidates") or []:
            replacement_id = str(candidate.get("replacement_id") or "")
            if replacement_id not in alias_replacement_ids:
                continue
            original = {
                "replacement_id": replacement_id,
                "legacy_checksum64": candidate.get("legacy_checksum64"),
                "legacy_texture_crc": candidate.get("legacy_texture_crc"),
                "legacy_palette_crc": candidate.get("legacy_palette_crc"),
                "legacy_formatsize": candidate.get("legacy_formatsize"),
                "legacy_storage": candidate.get("legacy_storage"),
                "legacy_source_path": candidate.get("legacy_source_path"),
            }
            for key in (
                "replacement_id",
                "legacy_checksum64",
                "legacy_texture_crc",
                "legacy_palette_crc",
                "legacy_formatsize",
                "legacy_storage",
                "legacy_source_path",
                "width",
                "height",
                "format",
                "texture_format",
                "pixel_type",
                "data_size",
                "is_hires",
            ):
                candidate[key] = canonical_template.get(key)
            applied.append(
                {
                    "selector_checksum64": candidate.get("selector_checksum64"),
                    "original": original,
                    "canonical_replacement_id": canonical_replacement_id,
                }
            )

        if not applied:
            raise SystemExit(
                f"alias-group review for sampled_low32={sampled_low32} policy={policy_key} applied no changes"
            )

        record["asset_candidate_count"] = len(record.get("asset_candidates") or [])
        changes.append(
            {
                "sampled_low32": sampled_low32,
                "policy_key": policy_key,
                "resolved_policy_key": str(record.get("policy_key") or ""),
                "record_resolution": record_resolution,
                "canonical_replacement_id": canonical_replacement_id,
                "applied_aliases": applied,
                "kept_candidate_count": len(record.get("asset_candidates") or []),
            }
        )

    loader_manifest["record_count"] = len(records)
    return loader_manifest, changes


def main():
    parser = argparse.ArgumentParser(description="Apply review-only broader alias-group decisions to a selected package loader manifest.")
    parser.add_argument("--loader-manifest", required=True, help="Source loader-manifest.json")
    parser.add_argument("--alias-group-review", action="append", required=True, help="One or more alias-group review JSON files")
    parser.add_argument("--output-dir", required=True, help="Output directory for candidate loader/package artifacts")
    parser.add_argument("--package-name", default="package.phrb", help="Binary package filename relative to output-dir")
    args = parser.parse_args()

    loader_manifest_path = Path(args.loader_manifest)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    loader_manifest = load_json(loader_manifest_path)
    review_docs = [load_json(Path(path)) for path in args.alias_group_review]
    updated_manifest, changes = apply_alias_group_reviews(loader_manifest, review_docs)

    output_loader_manifest = output_dir / "loader-manifest.json"
    output_loader_manifest.write_text(json.dumps(updated_manifest, indent=2) + "\n")

    package_dir = output_dir / "package"
    package_manifest = materialize_package(output_loader_manifest, package_dir)
    binary_path = output_dir / args.package_name
    binary_result = emit_binary_package(package_dir, binary_path)

    result = {
        "source_loader_manifest_path": str(loader_manifest_path),
        "alias_group_review_paths": args.alias_group_review,
        "output_loader_manifest_path": str(output_loader_manifest),
        "package_dir": str(package_dir),
        "package_manifest_record_count": package_manifest.get("record_count"),
        "applied_changes": changes,
        "binary_package": binary_result,
    }
    sys.stdout.write(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
