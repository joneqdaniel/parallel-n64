#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text())


def find_cross_scene_family(review, sampled_low32: str):
    for family in review.get("families", []):
        if str(family.get("sampled_low32") or "").lower() == sampled_low32.lower():
            return family
    return None


def build_transport_candidate(candidate, cache_path: Path, sampled_low32: str, selector_mode: str):
    selector_checksum64 = candidate["checksum64"] if selector_mode == "legacy" else "0000000000000000"
    return {
        "replacement_id": candidate["replacement_id"],
        "source": {
            "legacy_checksum64": candidate["checksum64"],
            "legacy_texture_crc": candidate["texture_crc"],
            "legacy_palette_crc": candidate["palette_crc"],
            "legacy_formatsize": candidate["formatsize"],
            "legacy_storage": "hts",
            "legacy_source_path": str(cache_path),
        },
        "match": {
            "exact_legacy_checksum64": candidate["checksum64"],
            "texture_crc": candidate["texture_crc"],
            "palette_crc": candidate["palette_crc"],
            "formatsize": candidate["formatsize"],
        },
        "replacement_asset": {
            "width": candidate["width"],
            "height": candidate["height"],
            "format": 2147516504,
            "texture_format": 6408,
            "pixel_type": 5121,
            "data_size": candidate["data_size"],
            "is_hires": True,
        },
        "selector_checksum64": selector_checksum64,
        "variant_group_id": f"sampled-{sampled_low32}-{candidate['width']}x{candidate['height']}-{candidate['texture_crc']}",
    }


def build_binding(
    review,
    sampled_low32: str,
    max_candidates: int | None = None,
    selected_replacement_id: str | None = None,
    selector_mode: str = "legacy",
    cross_scene_family_review: dict | None = None,
    allow_shared_scene_family: bool = False,
):
    target_group = None
    for group in review.get("groups", []):
        signature = group.get("signature", {})
        if signature.get("sampled_low32") == sampled_low32:
            target_group = group
            break

    if target_group is None:
        raise SystemExit(f"sampled_low32 {sampled_low32} not found in {review.get('bundle')}")

    canonical_identity = dict(target_group.get("canonical_identity", {}))
    if not canonical_identity:
        raise SystemExit(f"review group for {sampled_low32} is missing canonical_identity")

    wh = canonical_identity.get("wh") or "0x0"
    sampled_object_id = (
        f"sampled-fmt{canonical_identity.get('fmt')}"
        f"-siz{canonical_identity.get('siz')}"
        f"-off{canonical_identity.get('off')}"
        f"-stride{canonical_identity.get('stride')}"
        f"-wh{wh}"
        f"-fs{canonical_identity.get('formatsize')}"
        f"-low32{canonical_identity.get('sampled_low32')}"
    )

    candidate_rows = list(target_group.get("transport_candidates", []))
    if selected_replacement_id is not None:
        candidate_rows = [
            candidate for candidate in candidate_rows
            if candidate.get("replacement_id") == selected_replacement_id
        ]
        if not candidate_rows:
            raise SystemExit(
                f"selected_replacement_id {selected_replacement_id} not found for sampled_low32 {sampled_low32}"
            )
    if max_candidates is not None:
        candidate_rows = candidate_rows[:max_candidates]

    transport_candidates = [
        build_transport_candidate(candidate, Path(review["cache"]), sampled_low32, selector_mode)
        for candidate in candidate_rows
    ]

    if selector_mode == "zero" and cross_scene_family_review is not None:
        promotion_status = cross_scene_family_review.get("promotion_status")
        if promotion_status in {
            "no-runtime-discriminator-observed",
            "partial-overlap-runtime-signatures",
            "target-not-observed",
        } and not allow_shared_scene_family:
            raise SystemExit(
                f"sampled_low32 {sampled_low32} has cross-scene promotion_status={promotion_status!r}; "
                "refuse selector_mode='zero' without --allow-shared-scene-family"
            )

    binding = {
        "policy_key": f"{sampled_object_id}-pool",
        "family_type": "review-only-transport-pool",
        "status": "transport-pool",
        "selection_reason": "sampled-transport-review-pool",
        "sampled_object_id": sampled_object_id,
        "canonical_identity": canonical_identity,
        "transport_candidates": transport_candidates,
        "upload_low32s": [
            {
                "value": row["upload_checksum64"][-8:],
                "count": row["event_count"],
            }
            for row in target_group.get("top_upload_families", [])
        ],
        "upload_pcrcs": [
            {
                "value": row["upload_checksum64"][:8],
                "count": row["event_count"],
            }
            for row in target_group.get("top_upload_families", [])
        ],
        "probe_event_count": target_group.get("probe_event_count", 0),
        "exact_hit_count": target_group.get("exact_hit_count", 0),
        "transport_candidate_dims": target_group.get("transport_candidate_dims", []),
        "selector_mode": selector_mode,
    }
    if cross_scene_family_review is not None:
        binding["cross_scene_review"] = {
            "promotion_status": cross_scene_family_review.get("promotion_status"),
            "recommendation": cross_scene_family_review.get("recommendation"),
            "target_labels": cross_scene_family_review.get("target_labels") or [],
            "guard_labels": cross_scene_family_review.get("guard_labels") or [],
            "shared_signature_count": cross_scene_family_review.get("shared_signature_count"),
            "target_exclusive_signature_count": cross_scene_family_review.get("target_exclusive_signature_count"),
        }

    return {
        "schema_version": 1,
        "source_input_path": review.get("bundle"),
        "binding_count": 1,
        "unresolved_count": 0,
        "bindings": [binding],
        "unresolved_transport_cases": [],
    }


def main():
    parser = argparse.ArgumentParser(description="Emit a binding set from one sampled-object transport review group.")
    parser.add_argument("--review", required=True, help="Path to sampled transport review.json")
    parser.add_argument("--sampled-low32", required=True, help="Target sampled_low32")
    parser.add_argument("--max-candidates", type=int, help="Optional cap on emitted transport candidates")
    parser.add_argument("--selected-replacement-id", help="Optional exact replacement_id to emit from the review pool")
    parser.add_argument("--selector-mode", choices=("legacy", "zero"), default="legacy", help="Selector mode for emitted transport candidates")
    parser.add_argument("--cross-scene-review", help="Optional sampled cross-scene review JSON used to guard selector_mode=zero promotion.")
    parser.add_argument("--allow-shared-scene-family", action="store_true", help="Override the cross-scene guard and allow selector_mode=zero even when the family is shared across target and guard scenes.")
    parser.add_argument("--output", help="Optional output path")
    args = parser.parse_args()

    review_path = Path(args.review)
    cross_scene_family_review = None
    if args.cross_scene_review:
        cross_scene_review = load_json(Path(args.cross_scene_review))
        cross_scene_family_review = find_cross_scene_family(cross_scene_review, args.sampled_low32)
        if cross_scene_family_review is None:
            raise SystemExit(
                f"sampled_low32 {args.sampled_low32} not found in cross-scene review {args.cross_scene_review}"
            )
    result = build_binding(
        load_json(review_path),
        args.sampled_low32,
        args.max_candidates,
        args.selected_replacement_id,
        args.selector_mode,
        cross_scene_family_review=cross_scene_family_review,
        allow_shared_scene_family=args.allow_shared_scene_family,
    )
    serialized = json.dumps(result, indent=2) + "\n"
    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(serialized)
    else:
        sys.stdout.write(serialized)


if __name__ == "__main__":
    main()
