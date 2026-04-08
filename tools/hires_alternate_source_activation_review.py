#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text())


def build_cross_scene_index(review: dict):
    index = {}
    for family in review.get("families", []):
        sampled_low32 = str(family.get("sampled_low32") or "").lower()
        if not sampled_low32:
            continue
        index[sampled_low32] = family
    return index


def classify_group(group: dict, cross_scene_family: dict | None):
    signature = group.get("signature") or {}
    seeded = group.get("seeded_transport_pool") or {}
    sampled_low32 = str(signature.get("sampled_low32") or "").lower()
    candidate_count = int(seeded.get("candidate_count") or 0)
    alternate_source_status = str(group.get("alternate_source_status") or "")

    result = {
        "sampled_low32": sampled_low32,
        "draw_class": signature.get("draw_class"),
        "cycle": signature.get("cycle"),
        "formatsize": signature.get("formatsize"),
        "alternate_source_status": alternate_source_status,
        "candidate_count": candidate_count,
        "seed_dimensions": seeded.get("seed_dimensions"),
        "seed_dimension_set": seeded.get("seed_dimension_set") or [],
        "candidate_formatsizes": seeded.get("candidate_formatsizes") or [],
        "cross_scene_promotion_status": None,
        "cross_scene_recommendation": None,
        "activation_status": None,
        "activation_recommendation": None,
    }

    if cross_scene_family is not None:
        result["cross_scene_promotion_status"] = cross_scene_family.get("promotion_status")
        result["cross_scene_recommendation"] = cross_scene_family.get("recommendation")
        result["cross_scene_shared_signature_count"] = cross_scene_family.get("shared_signature_count")
        result["cross_scene_target_exclusive_signature_count"] = cross_scene_family.get("target_exclusive_signature_count")
        result["cross_scene_shared_guard_labels"] = cross_scene_family.get("shared_guard_labels") or []
        result["cross_scene_guard_labels_without_observation"] = cross_scene_family.get("guard_labels_without_observation") or []

    if candidate_count <= 0 or alternate_source_status != "source-backed-candidates-available":
        result["activation_status"] = "no-source-backed-candidates"
        result["activation_recommendation"] = "defer-until-new-source-evidence"
        return result

    if cross_scene_family is None:
        result["activation_status"] = "source-backed-without-cross-scene-classification"
        result["activation_recommendation"] = "add-cross-scene-review-before-probe"
        return result

    promotion_status = str(cross_scene_family.get("promotion_status") or "")
    if promotion_status == "target-exclusive-runtime-signatures-observed":
        result["activation_status"] = "target-exclusive-source-backed-candidates"
        result["activation_recommendation"] = "review-bounded-probe-allowed"
    elif promotion_status == "partial-overlap-runtime-signatures":
        result["activation_status"] = "partial-overlap-source-backed-candidates"
        result["activation_recommendation"] = "keep-review-only-until-shared-signatures-explained"
    elif promotion_status == "no-runtime-discriminator-observed":
        result["activation_status"] = "shared-scene-source-backed-candidates"
        result["activation_recommendation"] = "keep-review-only-until-new-runtime-discriminator"
    elif promotion_status == "target-not-observed":
        result["activation_status"] = "target-not-observed-source-backed-candidates"
        result["activation_recommendation"] = "defer-until-target-observation"
    else:
        result["activation_status"] = "source-backed-with-unknown-cross-scene-status"
        result["activation_recommendation"] = "classify-cross-scene-status-before-probe"
    return result


def render_markdown(review: dict):
    lines = [
        "# Alternate-Source Activation Review",
        "",
        f"- Alternate-source review: `{review.get('alternate_source_review_path', '')}`",
        f"- Cross-scene review: `{review.get('cross_scene_review_path', '')}`",
        f"- Family count: `{len(review.get('families') or [])}`",
        f"- Review-bounded probe candidates: `{review.get('summary', {}).get('review_bounded_probe_count', 0)}`",
        f"- Shared-scene blocked candidates: `{review.get('summary', {}).get('shared_scene_blocked_count', 0)}`",
        f"- Partial-overlap blocked candidates: `{review.get('summary', {}).get('partial_overlap_blocked_count', 0)}`",
        f"- Missing cross-scene classification: `{review.get('summary', {}).get('missing_cross_scene_count', 0)}`",
        f"- No-source families: `{review.get('summary', {}).get('no_source_count', 0)}`",
        "",
    ]

    for family in review.get("families") or []:
        lines.extend([
            f"## `{family.get('sampled_low32')}`",
            "",
            f"- activation_status: `{family.get('activation_status')}`",
            f"- activation_recommendation: `{family.get('activation_recommendation')}`",
            f"- alternate_source_status: `{family.get('alternate_source_status')}`",
            f"- candidate_count: `{family.get('candidate_count')}`",
            f"- seed_dimensions: `{family.get('seed_dimensions')}`",
            f"- cross_scene_promotion_status: `{family.get('cross_scene_promotion_status')}`",
            f"- cross_scene_shared_guard_labels: `{', '.join(family.get('cross_scene_shared_guard_labels') or []) or 'none'}`",
            "",
        ])
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Join alternate-source and cross-scene reviews into one bounded activation review.")
    parser.add_argument("--alternate-source-review", required=True, help="Path to hires-alternate-source-review.json")
    parser.add_argument("--cross-scene-review", required=True, help="Path to hires-sampled-cross-scene-review.json")
    parser.add_argument("--output-json", required=True, help="Output JSON path")
    parser.add_argument("--output-markdown", required=True, help="Output markdown path")
    args = parser.parse_args()

    alternate_source_review_path = Path(args.alternate_source_review)
    cross_scene_review_path = Path(args.cross_scene_review)
    alternate_source_review = load_json(alternate_source_review_path)
    cross_scene_review = load_json(cross_scene_review_path)
    cross_scene_index = build_cross_scene_index(cross_scene_review)

    families = []
    for group in alternate_source_review.get("groups", []):
        signature = group.get("signature") or {}
        sampled_low32 = str(signature.get("sampled_low32") or "").lower()
        families.append(classify_group(group, cross_scene_index.get(sampled_low32)))

    summary = {
        "review_bounded_probe_count": sum(1 for family in families if family.get("activation_status") == "target-exclusive-source-backed-candidates"),
        "shared_scene_blocked_count": sum(1 for family in families if family.get("activation_status") == "shared-scene-source-backed-candidates"),
        "partial_overlap_blocked_count": sum(1 for family in families if family.get("activation_status") == "partial-overlap-source-backed-candidates"),
        "missing_cross_scene_count": sum(1 for family in families if family.get("activation_status") == "source-backed-without-cross-scene-classification"),
        "no_source_count": sum(1 for family in families if family.get("activation_status") == "no-source-backed-candidates"),
    }

    result = {
        "schema_version": 1,
        "alternate_source_review_path": str(alternate_source_review_path),
        "cross_scene_review_path": str(cross_scene_review_path),
        "families": families,
        "summary": summary,
    }

    output_json_path = Path(args.output_json)
    output_json_path.parent.mkdir(parents=True, exist_ok=True)
    output_json_path.write_text(json.dumps(result, indent=2) + "\n")

    output_markdown_path = Path(args.output_markdown)
    output_markdown_path.parent.mkdir(parents=True, exist_ok=True)
    output_markdown_path.write_text(render_markdown(result))


if __name__ == "__main__":
    main()
