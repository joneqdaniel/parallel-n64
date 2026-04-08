#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text())


def find_duplicate_bucket(seam_register: dict, sampled_low32: str, selector: str | None):
    for row in seam_register.get("sampled_duplicate_families") or []:
        if str(row.get("sampled_low32") or "").lower() != sampled_low32:
            continue
        if selector and str(row.get("selector") or "").lower() != selector:
            continue
        return row
    raise SystemExit(f"duplicate bucket for sampled_low32={sampled_low32} selector={selector or '*'} not found")


def find_records(package_manifest: dict, sampled_low32: str):
    rows = []
    for record in package_manifest.get("records") or []:
        canonical_identity = record.get("canonical_identity") or {}
        if str(canonical_identity.get("sampled_low32") or "").lower() == sampled_low32:
            rows.append(record)
    if not rows:
        raise SystemExit(f"package-manifest record for sampled_low32={sampled_low32} not found")
    return rows


def dedupe_strings(values):
    seen = set()
    rows = []
    for value in values:
        if not value or value in seen:
            continue
        seen.add(value)
        rows.append(value)
    return rows


def build_review(seam_register_path: Path, package_manifest_path: Path, sampled_low32: str, selector: str | None):
    seam_register = load_json(seam_register_path)
    duplicate_bucket = find_duplicate_bucket(seam_register, sampled_low32, selector)
    package_manifest = load_json(package_manifest_path)
    records = find_records(package_manifest, sampled_low32)

    target_selector = str(duplicate_bucket.get("selector") or selector or "").lower()
    selector_candidates = []
    for record in records:
        policy_key = record.get("policy_key")
        for candidate in (record.get("asset_candidates") or []):
            if str(candidate.get("selector_checksum64") or "").lower() != target_selector:
                continue
            row = dict(candidate)
            row["policy_key"] = policy_key
            selector_candidates.append(row)
    if len(selector_candidates) < 2:
        raise SystemExit(
            f"expected at least two selector candidates for sampled_low32={sampled_low32} selector={target_selector}, "
            f"found {len(selector_candidates)}"
        )

    pixel_hashes = dedupe_strings(candidate.get("pixel_sha256") for candidate in selector_candidates)
    alpha_hashes = dedupe_strings(candidate.get("alpha_normalized_pixel_sha256") for candidate in selector_candidates)
    replacement_ids = dedupe_strings(candidate.get("replacement_id") for candidate in selector_candidates)

    matching_groups = []
    broader_alias_ids = []
    seen_group_signatures = set()
    for record in records:
        for group in record.get("duplicate_pixel_groups") or []:
            group_ids = dedupe_strings(group.get("replacement_ids") or [])
            if not (set(replacement_ids) & set(group_ids)):
                continue
            signature = (
                str(group.get("alpha_normalized_pixel_sha256") or ""),
                tuple(group_ids),
            )
            if signature in seen_group_signatures:
                continue
            seen_group_signatures.add(signature)
            matching_groups.append(
                {
                    "policy_key": record.get("policy_key"),
                    "alpha_normalized_pixel_sha256": group.get("alpha_normalized_pixel_sha256"),
                    "replacement_ids": group_ids,
                }
            )
            for replacement_id in group_ids:
                if replacement_id not in broader_alias_ids:
                    broader_alias_ids.append(replacement_id)

    if len(pixel_hashes) == 1 and len(alpha_hashes) == 1:
        recommendation = "keep-runtime-winner-rule-and-defer-offline-dedupe"
        reasons = [
            "selector-duplicate-candidates-share-identical-pixel-hash",
            "selector-duplicate-candidates-share-identical-alpha-normalized-hash",
        ]
        if len(broader_alias_ids) > len(replacement_ids):
            reasons.append("duplicate-pixel-group-spans-broader-surface-assets")
    else:
        recommendation = "keep-runtime-winner-rule-and-investigate-pixel-divergence"
        reasons = ["selector-duplicate-candidates-do-not-share-identical-pixels"]

    reasons.extend(
        [
            f"active-replacement-id={duplicate_bucket.get('replacement_id')}",
            f"active-policy={duplicate_bucket.get('policy')}",
        ]
    )

    return {
        "sampled_low32": sampled_low32,
        "selector": target_selector,
        "recommendation": recommendation,
        "reasons": reasons,
        "seam_register_path": str(seam_register_path),
        "package_manifest_path": str(package_manifest_path),
        "duplicate_bucket": duplicate_bucket,
        "record_count": len(records),
        "record_policy_keys": dedupe_strings(record.get("policy_key") for record in records),
        "selector_candidate_count": len(selector_candidates),
        "selector_candidates": [
            {
                "policy_key": candidate.get("policy_key"),
                "replacement_id": candidate.get("replacement_id"),
                "legacy_texture_crc": candidate.get("legacy_texture_crc"),
                "variant_group_id": candidate.get("variant_group_id"),
                "materialized_path": candidate.get("materialized_path"),
                "pixel_sha256": candidate.get("pixel_sha256"),
                "alpha_normalized_pixel_sha256": candidate.get("alpha_normalized_pixel_sha256"),
            }
            for candidate in selector_candidates
        ],
        "unique_selector_replacement_ids": replacement_ids,
        "unique_selector_pixel_hashes": pixel_hashes,
        "unique_selector_alpha_hashes": alpha_hashes,
        "matching_duplicate_pixel_groups": matching_groups,
        "broader_alias_replacement_ids": broader_alias_ids,
        "deferred_work": [
            "do-not-promote-runtime-merge-policy-from-this-one-duplicate-bucket",
            "treat-pixel-identical-duplicate-families-as-offline-dedupe-candidates-first",
            "keep-pool-semantics-and-source-activation-work-separate-from-duplicate-aliasing",
        ],
    }


def render_markdown(review: dict):
    bucket = review["duplicate_bucket"]
    lines = [
        "# Sampled Duplicate Review",
        "",
        f"- sampled_low32: `{review['sampled_low32']}`",
        f"- selector: `{review['selector']}`",
        f"- recommendation: `{review['recommendation']}`",
        f"- active replacement: `{bucket.get('replacement_id')}`",
        f"- active policy: `{bucket.get('policy')}`",
        "",
        "## Why",
        "",
    ]
    for reason in review.get("reasons") or []:
        lines.append(f"- `{reason}`")
    lines.extend(
        [
            "",
            "## Selector Candidates",
            "",
            f"- record_count: `{review.get('record_count')}`",
            f"- record policy keys: `{', '.join(review.get('record_policy_keys') or [])}`",
            f"- candidate_count: `{review['selector_candidate_count']}`",
            f"- unique replacement ids: `{', '.join(review.get('unique_selector_replacement_ids') or [])}`",
            f"- unique pixel hashes: `{len(review.get('unique_selector_pixel_hashes') or [])}`",
            f"- unique alpha-normalized pixel hashes: `{len(review.get('unique_selector_alpha_hashes') or [])}`",
            "",
        ]
    )
    for candidate in review.get("selector_candidates") or []:
        lines.append(
            f"- `{candidate.get('replacement_id')}` from `{candidate.get('policy_key')}` texcrc `{candidate.get('legacy_texture_crc')}` "
            f"variant `{candidate.get('variant_group_id')}` pixel `{candidate.get('pixel_sha256')}`"
        )

    lines.extend(
        [
            "",
            "## Duplicate Pixel Groups",
            "",
            f"- matching groups: `{len(review.get('matching_duplicate_pixel_groups') or [])}`",
            f"- broader alias ids: `{', '.join(review.get('broader_alias_replacement_ids') or [])}`",
            "",
            "## Deferred Work",
            "",
        ]
    )
    for item in review.get("deferred_work") or []:
        lines.append(f"- `{item}`")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Review one sampled duplicate family against package-manifest pixel groups.")
    parser.add_argument("--runtime-seam-register", required=True, help="Runtime seam register JSON")
    parser.add_argument("--package-manifest", required=True, help="Selected package-manifest JSON")
    parser.add_argument("--sampled-low32", required=True, help="Duplicate family sampled_low32")
    parser.add_argument("--selector", help="Optional duplicate selector to target")
    parser.add_argument("--output", required=True, help="Markdown output path")
    parser.add_argument("--output-json", required=True, help="JSON output path")
    args = parser.parse_args()

    review = build_review(
        Path(args.runtime_seam_register),
        Path(args.package_manifest),
        str(args.sampled_low32).lower(),
        str(args.selector).lower() if args.selector else None,
    )
    Path(args.output_json).write_text(json.dumps(review, indent=2) + "\n")
    Path(args.output).write_text(render_markdown(review))


if __name__ == "__main__":
    main()
