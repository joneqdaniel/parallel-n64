#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text())


def dedupe_strings(values):
    seen = set()
    rows = []
    for value in values:
        if not value or value in seen:
            continue
        seen.add(value)
        rows.append(value)
    return rows


def find_record(package_manifest: dict, sampled_low32: str):
    for record in package_manifest.get("records") or []:
        canonical_identity = record.get("canonical_identity") or {}
        if str(canonical_identity.get("sampled_low32") or "").lower() == sampled_low32:
            return record
    raise SystemExit(f"package-manifest record for sampled_low32={sampled_low32} not found")


def find_group(record: dict, alpha_hash: str | None):
    groups = record.get("duplicate_pixel_groups") or []
    if alpha_hash:
        for group in groups:
            if str(group.get("alpha_normalized_pixel_sha256") or "").lower() == alpha_hash:
                return group
        raise SystemExit(f"duplicate_pixel_group {alpha_hash} not found")
    if len(groups) != 1:
        raise SystemExit(
            f"expected exactly one duplicate_pixel_group when --alpha-hash is omitted, found {len(groups)}"
        )
    return groups[0]


def build_review(package_manifest_path: Path, sampled_low32: str, alpha_hash: str | None):
    package_manifest = load_json(package_manifest_path)
    record = find_record(package_manifest, sampled_low32)
    group = find_group(record, alpha_hash.lower() if alpha_hash else None)

    group_ids = list(group.get("replacement_ids") or [])
    unique_group_ids = dedupe_strings(group_ids)
    selector_rows = []
    selector_to_ids = {}
    repeated_replacement_ids = {}
    for replacement_id in unique_group_ids:
        repeated_replacement_ids[replacement_id] = group_ids.count(replacement_id)
    suggested_canonical_replacement_id = None
    if unique_group_ids:
        suggested_canonical_replacement_id = sorted(
            unique_group_ids,
            key=lambda replacement_id: (-repeated_replacement_ids[replacement_id], replacement_id),
        )[0]
    for candidate in record.get("asset_candidates") or []:
        replacement_id = candidate.get("replacement_id")
        if replacement_id not in unique_group_ids:
            continue
        selector = str(candidate.get("selector_checksum64") or "").lower()
        selector_to_ids.setdefault(selector, []).append(replacement_id)
        selector_rows.append(
            {
                "selector": selector,
                "replacement_id": replacement_id,
                "legacy_texture_crc": candidate.get("legacy_texture_crc"),
                "variant_group_id": candidate.get("variant_group_id"),
                "materialized_path": candidate.get("materialized_path"),
            }
        )
    selector_rows.sort(key=lambda row: (row["selector"], row["replacement_id"]))
    duplicate_selectors = [
        {
            "selector": selector,
            "replacement_ids": dedupe_strings(replacement_ids),
        }
        for selector, replacement_ids in sorted(selector_to_ids.items())
        if len(dedupe_strings(replacement_ids)) > 1
    ]

    reasons = []
    if duplicate_selectors:
        recommendation = "keep-selector-review-first"
        reasons.append("group-still-contains-selector-local-duplicate-conflicts")
    else:
        recommendation = "keep-selectors-distinct-and-consider-asset-level-dedupe"
        reasons.append("group-spans-distinct-selectors-only")
        reasons.append("no-selector-local-duplicate-conflicts-remain")
    if any(count > 1 for count in repeated_replacement_ids.values()):
        reasons.append("group-still-contains-repeated-replacement-id-members")
    if len(unique_group_ids) > 1:
        reasons.append("group-still-spans-multiple-replacement-ids")

    return {
        "package_manifest_path": str(package_manifest_path),
        "sampled_low32": sampled_low32,
        "policy_key": record.get("policy_key"),
        "recommendation": recommendation,
        "reasons": reasons,
        "group_alpha_normalized_pixel_sha256": group.get("alpha_normalized_pixel_sha256"),
        "group_replacement_ids": group_ids,
        "unique_group_replacement_ids": unique_group_ids,
        "repeated_replacement_ids": repeated_replacement_ids,
        "suggested_canonical_replacement_id": suggested_canonical_replacement_id,
        "suggested_alias_replacement_ids": [
            replacement_id for replacement_id in unique_group_ids if replacement_id != suggested_canonical_replacement_id
        ],
        "selector_row_count": len(selector_rows),
        "selector_rows": selector_rows,
        "duplicate_selectors": duplicate_selectors,
        "deferred_work": [
            "do-not-turn-broader-identical-pixel-groups-into-runtime-merge-rules",
            "treat-selector-distinct-groups-as-offline-asset-dedupe-or-alias-candidates-only",
            "keep-selector-local-dedupe-review-separate-from-broader-asset-alias-review",
        ],
    }


def render_markdown(review: dict):
    lines = [
        "# Sampled Alias Group Review",
        "",
        f"- sampled_low32: `{review['sampled_low32']}`",
        f"- policy_key: `{review['policy_key']}`",
        f"- recommendation: `{review['recommendation']}`",
        f"- alpha hash: `{review['group_alpha_normalized_pixel_sha256']}`",
        "",
        "## Why",
        "",
    ]
    for reason in review.get("reasons") or []:
        lines.append(f"- `{reason}`")
    lines.extend(
        [
            "",
            "## Group",
            "",
            f"- replacement ids: `{', '.join(review.get('group_replacement_ids') or [])}`",
            f"- unique replacement ids: `{', '.join(review.get('unique_group_replacement_ids') or [])}`",
            f"- suggested canonical replacement id: `{review.get('suggested_canonical_replacement_id')}`",
            f"- selector_row_count: `{review.get('selector_row_count')}`",
            "",
            "## Selectors",
            "",
        ]
    )
    for row in review.get("selector_rows") or []:
        lines.append(
            f"- selector `{row.get('selector')}` -> `{row.get('replacement_id')}` "
            f"texcrc `{row.get('legacy_texture_crc')}`"
        )
    lines.extend(["", "## Deferred Work", ""])
    for item in review.get("deferred_work") or []:
        lines.append(f"- `{item}`")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Review a broader identical-pixel alias group for one sampled record.")
    parser.add_argument("--package-manifest", required=True, help="Selected package package-manifest.json")
    parser.add_argument("--sampled-low32", required=True, help="Target sampled_low32")
    parser.add_argument("--alpha-hash", help="Optional alpha-normalized duplicate group hash")
    parser.add_argument("--output", required=True, help="Markdown output path")
    parser.add_argument("--output-json", required=True, help="JSON output path")
    args = parser.parse_args()

    review = build_review(
        Path(args.package_manifest),
        str(args.sampled_low32).lower(),
        str(args.alpha_hash).lower() if args.alpha_hash else None,
    )
    output_json_path = Path(args.output_json)
    output_md_path = Path(args.output)
    output_json_path.parent.mkdir(parents=True, exist_ok=True)
    output_md_path.parent.mkdir(parents=True, exist_ok=True)
    output_json_path.write_text(json.dumps(review, indent=2) + "\n")
    output_md_path.write_text(render_markdown(review))


if __name__ == "__main__":
    main()
