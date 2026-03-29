#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text())


def build_transport_candidate(candidate, cache_path: Path, sampled_low32: str):
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
        "selector_checksum64": candidate["checksum64"],
        "variant_group_id": f"sampled-{sampled_low32}-{candidate['width']}x{candidate['height']}-{candidate['texture_crc']}",
    }


def build_binding(review, sampled_low32: str, max_candidates: int | None = None):
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
    if max_candidates is not None:
        candidate_rows = candidate_rows[:max_candidates]

    transport_candidates = [
        build_transport_candidate(candidate, Path(review["cache"]), sampled_low32)
        for candidate in candidate_rows
    ]

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
    parser.add_argument("--output", help="Optional output path")
    args = parser.parse_args()

    review_path = Path(args.review)
    result = build_binding(load_json(review_path), args.sampled_low32, args.max_candidates)
    serialized = json.dumps(result, indent=2) + "\n"
    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(serialized)
    else:
        sys.stdout.write(serialized)


if __name__ == "__main__":
    main()
