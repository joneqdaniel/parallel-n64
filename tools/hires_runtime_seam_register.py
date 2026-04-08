#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text())


def build_alternate_source_index(review: dict):
    index = {}
    for group in review.get("groups", []):
        signature = group.get("signature") or {}
        seeded = group.get("seeded_transport_pool") or {}
        key = (
            str(signature.get("sampled_low32") or "").lower(),
            str(signature.get("draw_class") or "").lower(),
            str(signature.get("cycle") or "").lower(),
            str(signature.get("formatsize") or ""),
        )
        index[key] = {
            "alternate_source_status": group.get("alternate_source_status"),
            "alternate_source_candidate_count": seeded.get("candidate_count"),
            "alternate_source_unique_pixel_count": group.get("unique_transport_pixel_count"),
            "alternate_source_seed_dimensions": seeded.get("seed_dimensions"),
            "alternate_source_candidate_formatsizes": seeded.get("candidate_formatsizes"),
            "alternate_source_cache_path": seeded.get("cache_path"),
        }
    return index


def build_cross_scene_index(review: dict):
    index = {}
    for family in review.get("families", []):
        sampled_low32 = str(family.get("sampled_low32") or "").lower()
        if not sampled_low32:
            continue
        index[sampled_low32] = {
            "cross_scene_promotion_status": family.get("promotion_status"),
            "cross_scene_recommendation": family.get("recommendation"),
            "cross_scene_shared_signature_count": family.get("shared_signature_count"),
            "cross_scene_target_exclusive_signature_count": family.get("target_exclusive_signature_count"),
            "cross_scene_guard_exclusive_signature_count": family.get("guard_exclusive_signature_count"),
            "cross_scene_target_labels": family.get("target_labels") or [],
            "cross_scene_guard_labels": family.get("guard_labels") or [],
            "cross_scene_shared_guard_labels": family.get("shared_guard_labels") or [],
            "cross_scene_guard_labels_without_observation": family.get("guard_labels_without_observation") or [],
        }
    return index


def build_activation_index(review: dict):
    index = {}
    for family in review.get("families", []):
        sampled_low32 = str(family.get("sampled_low32") or "").lower()
        if not sampled_low32:
            continue
        index[sampled_low32] = {
            "activation_status": family.get("activation_status"),
            "activation_recommendation": family.get("activation_recommendation"),
            "activation_candidate_count": family.get("candidate_count"),
            "activation_seed_dimensions": family.get("seed_dimensions"),
        }
    return index


def build_pool_stream_index(evidence: dict):
    index = {}
    probe = evidence.get("sampled_pool_stream_probe") or {}
    for row in probe.get("top_families", []):
        fields = row.get("fields") or {}
        key = (
            str(fields.get("sampled_low32") or "").lower(),
            str(fields.get("palette_crc") or "").lower(),
            str(fields.get("fs") or ""),
        )
        if not key[0]:
            continue
        index[key] = {
            "stream_event_count": row.get("count"),
            "stream_observed_selector": fields.get("observed_selector"),
            "stream_observed_selector_source": fields.get("observed_selector_source"),
            "stream_observed_count": fields.get("observed_count"),
            "stream_unique_observed_selectors": fields.get("unique_observed_selectors"),
            "stream_transition_count": fields.get("transition_count"),
            "stream_repeat_count": fields.get("repeat_count"),
            "stream_current_run": fields.get("current_run"),
            "stream_max_run": fields.get("max_run"),
            "stream_runtime_unique_selectors": fields.get("runtime_unique_selectors"),
            "stream_ordered_selectors": fields.get("ordered_selectors"),
            "stream_active_entries": fields.get("active_entries"),
        }
    return index


def slim_absent_family(row, alternate_source_index=None, cross_scene_index=None, activation_index=None):
    slim = {
        "sampled_low32": row.get("sampled_low32"),
        "draw_class": row.get("draw_class"),
        "cycle": row.get("cycle"),
        "formatsize": row.get("fs"),
        "count": row.get("count"),
        "package_status": row.get("package_status"),
        "transport_status": row.get("transport_status"),
        "matching_transport_candidate_count": row.get("matching_transport_candidate_count"),
        "matching_transport_group_count": row.get("matching_transport_group_count"),
        "sample_detail": row.get("sample_detail"),
    }
    key = (
        str(row.get("sampled_low32") or "").lower(),
        str(row.get("draw_class") or "").lower(),
        str(row.get("cycle") or "").lower(),
        str(row.get("fs") or ""),
    )
    if alternate_source_index and key in alternate_source_index:
        slim.update(alternate_source_index[key])
    sampled_low32 = str(row.get("sampled_low32") or "").lower()
    if cross_scene_index and sampled_low32 in cross_scene_index:
        slim.update(cross_scene_index[sampled_low32])
    if activation_index and sampled_low32 in activation_index:
        slim.update(activation_index[sampled_low32])
    return slim


def slim_pool_family(row, pool_stream_index=None):
    slim = {
        "sampled_low32": row.get("sampled_low32"),
        "draw_class": row.get("draw_class"),
        "cycle": row.get("cycle"),
        "formatsize": row.get("fs"),
        "palette_crcs": row.get("palette_crcs") or [],
        "count": row.get("count"),
        "pool_recommendation": row.get("pool_recommendation"),
        "package_status": row.get("pool_package_status") or row.get("package_status"),
        "runtime_status": row.get("pool_runtime_status") or row.get("runtime_family_status"),
        "runtime_sample_policy": row.get("runtime_sample_policy"),
        "runtime_sample_replacement_id": row.get("runtime_sample_replacement_id"),
        "runtime_sampled_object": row.get("runtime_sampled_object"),
        "runtime_unique_selector_count": row.get("runtime_unique_selector_count"),
        "runtime_matching_selector_count": row.get("runtime_matching_selector_count"),
        "matching_transport_candidate_count": row.get("matching_transport_candidate_count"),
        "transport_status": row.get("transport_status"),
    }
    if pool_stream_index:
        formatsize = str(row.get("fs") or "")
        sampled_low32 = str(row.get("sampled_low32") or "").lower()
        palette_crcs = [str(value or "").lower() for value in (row.get("palette_crcs") or [])]
        candidate_keys = [
            key
            for key in pool_stream_index
            if key[0] == sampled_low32 and key[2] == formatsize
        ]
        if palette_crcs:
            for palette_crc in palette_crcs:
                key = (sampled_low32, palette_crc, formatsize)
                if key in pool_stream_index:
                    slim.update(pool_stream_index[key])
                    break
        elif len(candidate_keys) == 1:
            slim.update(pool_stream_index[candidate_keys[0]])
    return slim


def slim_duplicate_bucket(row):
    fields = row.get("fields") or {}
    return {
        "sampled_low32": fields.get("sampled_low32"),
        "palette_crc": fields.get("palette_crc"),
        "formatsize": fields.get("fs"),
        "selector": fields.get("selector"),
        "total_entries": fields.get("total_entries"),
        "duplicate_entries": fields.get("duplicate_entries"),
        "policy": fields.get("policy"),
        "replacement_id": fields.get("replacement_id"),
        "sampled_object": fields.get("sampled_object"),
        "repl": fields.get("repl"),
        "source": fields.get("source"),
        "count": row.get("count"),
        "sample_detail": row.get("sample_detail"),
    }


def main():
    parser = argparse.ArgumentParser(description="Summarize active hi-res runtime seams for a validation bundle.")
    parser.add_argument("--bundle-dir", required=True, help="On-bundle directory with traces/hires-evidence.json")
    parser.add_argument("--selector-review", required=True, help="Path to hires-sampled-selector-review.json")
    parser.add_argument("--alternate-source-review", help="Optional alternate-source seeded review JSON")
    parser.add_argument("--cross-scene-review", help="Optional sampled cross-scene review JSON")
    parser.add_argument("--alternate-source-activation-review", help="Optional joined alternate-source activation review JSON")
    parser.add_argument("--output", required=True, help="Markdown output path")
    parser.add_argument("--output-json", required=True, help="JSON output path")
    args = parser.parse_args()

    bundle_dir = Path(args.bundle_dir)
    selector_review_path = Path(args.selector_review)
    alternate_source_review_path = Path(args.alternate_source_review) if args.alternate_source_review else None
    cross_scene_review_path = Path(args.cross_scene_review) if args.cross_scene_review else None
    alternate_source_activation_review_path = Path(args.alternate_source_activation_review) if args.alternate_source_activation_review else None
    evidence_path = bundle_dir / "traces" / "hires-evidence.json"
    if not evidence_path.is_file():
        raise SystemExit(f"missing hires evidence at {evidence_path}")
    if not selector_review_path.is_file():
        raise SystemExit(f"missing selector review at {selector_review_path}")
    if alternate_source_review_path and not alternate_source_review_path.is_file():
        raise SystemExit(f"missing alternate-source review at {alternate_source_review_path}")
    if cross_scene_review_path and not cross_scene_review_path.is_file():
        raise SystemExit(f"missing cross-scene review at {cross_scene_review_path}")
    if alternate_source_activation_review_path and not alternate_source_activation_review_path.is_file():
        raise SystemExit(f"missing alternate-source activation review at {alternate_source_activation_review_path}")

    evidence = load_json(evidence_path)
    selector_review = load_json(selector_review_path)
    alternate_source_index = {}
    if alternate_source_review_path:
        alternate_source_index = build_alternate_source_index(load_json(alternate_source_review_path))
    cross_scene_index = {}
    if cross_scene_review_path:
        cross_scene_index = build_cross_scene_index(load_json(cross_scene_review_path))
    activation_index = {}
    if alternate_source_activation_review_path:
        activation_index = build_activation_index(load_json(alternate_source_activation_review_path))
    pool_stream_index = build_pool_stream_index(evidence)

    unresolved = selector_review.get("unresolved") or []
    pool_families = selector_review.get("pool_families") or []
    duplicate_probe = (evidence.get("sampled_duplicate_probe") or {}).get("top_buckets") or []

    candidate_free_absent = []
    candidate_backed_absent = []
    for row in unresolved:
        if row.get("package_status") != "absent-from-package":
            continue
        slim = slim_absent_family(row, alternate_source_index, cross_scene_index, activation_index)
        if row.get("transport_status") == "legacy-transport-candidate-free":
            candidate_free_absent.append(slim)
        else:
            candidate_backed_absent.append(slim)

    pool_conflicts = []
    for row in pool_families:
        if row.get("pool_recommendation"):
            pool_conflicts.append(slim_pool_family(row, pool_stream_index))

    sampled_duplicates = [slim_duplicate_bucket(row) for row in duplicate_probe]

    candidate_free_alt_source_available_count = sum(
        1
        for row in candidate_free_absent
        if int(row.get("alternate_source_candidate_count") or 0) > 0
    )
    candidate_free_alt_source_total_candidates = sum(
        int(row.get("alternate_source_candidate_count") or 0) for row in candidate_free_absent
    )
    candidate_free_no_runtime_discriminator_count = sum(
        1
        for row in candidate_free_absent
        if row.get("cross_scene_promotion_status") == "no-runtime-discriminator-observed"
    )
    candidate_free_review_bounded_probe_count = sum(
        1
        for row in candidate_free_absent
        if row.get("activation_status") == "target-exclusive-source-backed-candidates"
    )

    register = {
        "bundle_dir": str(bundle_dir),
        "selector_review_path": str(selector_review_path),
        "alternate_source_review_path": str(alternate_source_review_path) if alternate_source_review_path else None,
        "cross_scene_review_path": str(cross_scene_review_path) if cross_scene_review_path else None,
        "alternate_source_activation_review_path": str(alternate_source_activation_review_path) if alternate_source_activation_review_path else None,
        "candidate_free_absent_families": candidate_free_absent,
        "candidate_backed_absent_families": candidate_backed_absent,
        "pool_conflict_families": pool_conflicts,
        "sampled_duplicate_families": sampled_duplicates,
        "summary": {
            "candidate_free_absent_family_count": len(candidate_free_absent),
            "candidate_free_alt_source_available_count": candidate_free_alt_source_available_count,
            "candidate_free_alt_source_total_candidates": candidate_free_alt_source_total_candidates,
            "candidate_free_no_runtime_discriminator_count": candidate_free_no_runtime_discriminator_count,
            "candidate_free_review_bounded_probe_count": candidate_free_review_bounded_probe_count,
            "candidate_backed_absent_family_count": len(candidate_backed_absent),
            "pool_conflict_family_count": len(pool_conflicts),
            "sampled_duplicate_family_count": len(sampled_duplicates),
        },
        "recommendations": [],
    }

    if candidate_free_absent:
        if candidate_free_alt_source_available_count:
            register["recommendations"].append("prefer-review-only-alternate-source-lane-for-candidate-free-families")
        if candidate_free_no_runtime_discriminator_count:
            register["recommendations"].append("keep-cross-scene-shared-candidate-free-families-review-only")
        if candidate_free_review_bounded_probe_count:
            register["recommendations"].append("prefer-review-bounded-source-backed-probes-for-target-exclusive-families")
        if candidate_free_alt_source_available_count < len(candidate_free_absent):
            register["recommendations"].append("defer-candidate-free-absent-families-until-new-source-evidence")
    if candidate_backed_absent:
        register["recommendations"].append("keep-candidate-backed-absent-families-separated-from-runtime-pool-work")
    if pool_conflicts:
        register["recommendations"].append("defer-runtime-pool-semantics-until-selector-stream-model-is-bounded")
    if sampled_duplicates:
        register["recommendations"].append("defer-native-duplicate-resolution-policy-until-active-winner-rules-are-designed")

    output_json_path = Path(args.output_json)
    output_json_path.write_text(json.dumps(register, indent=2) + "\n")

    lines = [
        "# Hi-Res Runtime Seam Register",
        "",
        f"- Bundle: `{bundle_dir}`",
        f"- Selector review: `{selector_review_path}`",
        "",
        "## Summary",
        "",
        f"- Candidate-free absent families: `{len(candidate_free_absent)}`",
        f"- Candidate-free families with alternate-source candidates: `{candidate_free_alt_source_available_count}`",
        f"- Candidate-free alternate-source candidates total: `{candidate_free_alt_source_total_candidates}`",
        f"- Candidate-free families with no runtime discriminator: `{candidate_free_no_runtime_discriminator_count}`",
        f"- Candidate-free families with review-bounded source-backed probes: `{candidate_free_review_bounded_probe_count}`",
        f"- Candidate-backed absent families: `{len(candidate_backed_absent)}`",
        f"- Pool-conflict families: `{len(pool_conflicts)}`",
        f"- Sampled duplicate families: `{len(sampled_duplicates)}`",
        "",
    ]
    if alternate_source_review_path:
        lines.insert(4, f"- Alternate-source review: `{alternate_source_review_path}`")
    if cross_scene_review_path:
        lines.insert(5 if alternate_source_review_path else 4, f"- Cross-scene review: `{cross_scene_review_path}`")
    if alternate_source_activation_review_path:
        insert_index = 6 if (alternate_source_review_path and cross_scene_review_path) else (5 if (alternate_source_review_path or cross_scene_review_path) else 4)
        lines.insert(insert_index, f"- Alternate-source activation review: `{alternate_source_activation_review_path}`")

    if register["recommendations"]:
        lines.extend(["## Recommendations", ""])
        for recommendation in register["recommendations"]:
            lines.append(f"- `{recommendation}`")
        lines.append("")

    if candidate_free_absent:
        lines.extend(["## Candidate-Free Absent Families", ""])
        for row in candidate_free_absent:
            detail = (
                f"- `{row['sampled_low32']}` `{row['draw_class']}` / `{row['cycle']}` "
                f"fs `{row['formatsize']}` count `{row['count']}`"
            )
            alt_candidates = int(row.get("alternate_source_candidate_count") or 0)
            if alt_candidates > 0:
                detail += (
                    f", alternate source `{alt_candidates}` candidates "
                    f"at `{row.get('alternate_source_seed_dimensions')}`"
                )
            cross_scene_status = row.get("cross_scene_promotion_status")
            if cross_scene_status:
                detail += f", cross-scene `{cross_scene_status}`"
            activation_status = row.get("activation_status")
            if activation_status:
                detail += f", activation `{activation_status}`"
            shared_guards = row.get("cross_scene_shared_guard_labels") or []
            if shared_guards:
                detail += f", shared guards `{','.join(shared_guards)}`"
            absent_guards = row.get("cross_scene_guard_labels_without_observation") or []
            if absent_guards:
                detail += f", absent guards `{','.join(absent_guards)}`"
            lines.append(detail)
        lines.append("")

    if candidate_backed_absent:
        lines.extend(["## Candidate-Backed Absent Families", ""])
        for row in candidate_backed_absent:
            lines.append(
                f"- `{row['sampled_low32']}` `{row['draw_class']}` / `{row['cycle']}` fs `{row['formatsize']}` "
                f"transport `{row['matching_transport_candidate_count']}`"
            )
        lines.append("")

    if pool_conflicts:
        lines.extend(["## Pool-Conflict Families", ""])
        for row in pool_conflicts:
            detail = (
                f"- `{row['sampled_low32']}` -> `{row['pool_recommendation']}` "
                f"(runtime policy `{row['runtime_sample_policy']}`, replacement `{row.get('runtime_sample_replacement_id')}`, selectors `{row['runtime_unique_selector_count']}`)"
            )
            if row.get("stream_observed_count") is not None:
                detail += (
                    f", stream observed `{row.get('stream_observed_count')}` "
                    f"across `{row.get('stream_unique_observed_selectors')}` selectors"
                    f", transitions `{row.get('stream_transition_count')}`, max run `{row.get('stream_max_run')}`"
                )
                if row.get("stream_observed_selector"):
                    detail += (
                        f", latest selector `{row.get('stream_observed_selector')}` "
                        f"from `{row.get('stream_observed_selector_source')}`"
                    )
            lines.append(detail)
        lines.append("")

    if sampled_duplicates:
        lines.extend(["## Sampled Duplicate Families", ""])
        for row in sampled_duplicates:
            lines.append(
                f"- `{row['sampled_low32']}` palette `{row['palette_crc']}` fs `{row['formatsize']}` "
                f"selector `{row['selector']}` total `{row['total_entries']}` active policy `{row['policy']}` "
                f"replacement `{row.get('replacement_id')}`"
            )
        lines.append("")

    Path(args.output).write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
