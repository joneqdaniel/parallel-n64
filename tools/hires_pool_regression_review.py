#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text())


def load_step(summary_path: Path, step_frames: int):
    data = load_json(summary_path)
    steps = data.get("steps")
    if isinstance(steps, list):
        for step in steps:
            if int(step.get("step_frames") or -1) == step_frames:
                return step
    elif isinstance(steps, dict):
        for key in (str(step_frames), step_frames):
            if key in steps:
                return steps[key]
    raise SystemExit(f"step {step_frames} not found in {summary_path}")


def collect_family_hits(probe: dict, sampled_low32: str):
    rows = []
    reason_counts = {}
    total = 0
    for bucket in probe.get("top_exact_hit_buckets") or []:
        fields = bucket.get("fields") or {}
        if str(fields.get("sampled_low32") or "").lower() != sampled_low32:
            continue
        count = int(bucket.get("count") or 0)
        reason = str(fields.get("reason") or "")
        total += count
        reason_counts[reason] = reason_counts.get(reason, 0) + count
        rows.append(
            {
                "count": count,
                "reason": reason,
                "selector": fields.get("key"),
                "replacement_dims": fields.get("repl"),
                "sample_detail": bucket.get("sample_detail"),
            }
        )
    rows.sort(key=lambda row: (-row["count"], row["reason"]))
    reason_rows = [
        {"reason": reason, "count": count}
        for reason, count in sorted(reason_counts.items(), key=lambda item: (-item[1], item[0]))
    ]
    return total, reason_rows, rows


def build_case(label: str, summary_path: Path, sampled_low32: str, step_frames: int):
    step = load_step(summary_path, step_frames)
    probe = step.get("sampled_object_probe") or {}
    family_total_hits, family_reason_counts, family_hit_rows = collect_family_hits(probe, sampled_low32)
    return {
        "label": label,
        "summary_path": str(summary_path),
        "cache_path": load_json(summary_path).get("cache_path"),
        "cache_sha256": load_json(summary_path).get("cache_sha256"),
        "step_frames": int(step.get("step_frames") or step_frames),
        "selected_hash": step.get("selected_hash") or step.get("on_hash"),
        "baseline_hash": step.get("legacy_hash") or step.get("off_hash"),
        "matches_baseline": step.get("matches_legacy") if "matches_legacy" in step else step.get("matches_off"),
        "ae": int(step.get("ae") or 0),
        "rmse": float(step.get("rmse") or 0.0),
        "exact_hit_count": int(probe.get("exact_hit_count") or 0),
        "exact_conflict_miss_count": int(probe.get("exact_conflict_miss_count") or 0),
        "exact_unresolved_miss_count": int(probe.get("exact_unresolved_miss_count") or 0),
        "family_total_hits": family_total_hits,
        "family_reason_counts": family_reason_counts,
        "family_hit_rows": family_hit_rows,
        "semantic": step.get("semantic") or {},
        "selected_bundle": step.get("selected_bundle") or step.get("on_bundle"),
    }


def load_surface_case(surface_package_path: Path, sampled_low32: str):
    package = load_json(surface_package_path)
    for surface_entry in package.get("surfaces") or []:
        canonical_identity = surface_entry.get("canonical_identity") or {}
        surface = surface_entry.get("surface") or {}
        family = str(surface.get("sampled_low32") or canonical_identity.get("sampled_low32") or "").lower()
        if family != sampled_low32:
            continue
        unresolved_sequences = surface.get("unresolved_sequences") or []
        return {
            "surface_package_path": str(surface_package_path),
            "shape_hint": surface.get("shape_hint") or surface_entry.get("shape_hint"),
            "sampled_low32": family,
            "sampled_object_id": surface.get("sampled_object_id"),
            "slot_count": int(surface.get("slot_count") or 0),
            "replacement_id_count": len(surface.get("replacement_ids") or []),
            "unresolved_sequence_count": len(unresolved_sequences),
            "first_unresolved_sequence": unresolved_sequences[0] if unresolved_sequences else None,
            "surface_tile_dims": surface.get("surface_tile_dims"),
            "canonical_identity": canonical_identity,
        }
    raise SystemExit(f"surface for sampled_low32={sampled_low32} not found in {surface_package_path}")


def summarize_live_pool_review(pool_review_path: Path):
    review = load_json(pool_review_path)
    edge_review = review.get("edge_review") or {}
    tail_dwell = review.get("tail_dwell") or {}
    sequence_summary = review.get("sequence_summary") or {}
    surface_map_summary = review.get("surface_map_summary") or {}
    return {
        "pool_review_path": str(pool_review_path),
        "runtime_sample_policy": review.get("runtime_sample_policy"),
        "runtime_sample_replacement_id": review.get("runtime_sample_replacement_id"),
        "runtime_sampled_object": review.get("runtime_sampled_object"),
        "pool_recommendation": review.get("pool_recommendation"),
        "runtime_shape_recommendation": review.get("runtime_shape_recommendation"),
        "recommendation_reasons": review.get("recommendation_reasons") or [],
        "shape_hint": sequence_summary.get("shape_hint"),
        "slot_count": int(surface_map_summary.get("slot_count") or 0),
        "mapped_candidate_count": int(surface_map_summary.get("mapped_candidate_count") or 0),
        "unresolved_count": int(surface_map_summary.get("unresolved_count") or 0),
        "candidate_count": int(surface_map_summary.get("candidate_count") or 0),
        "resolved_ratio": surface_map_summary.get("resolved_ratio"),
        "dominant_delta": sequence_summary.get("dominant_delta"),
        "dominant_delta_count": sequence_summary.get("dominant_delta_count"),
        "tail_dwell_present": bool(tail_dwell.get("present")),
        "tail_dwell_run_length": tail_dwell.get("run_length"),
        "tail_dwell_aligns_with_unresolved_slot": bool(tail_dwell.get("aligns_with_unresolved_slot")),
        "edge_only": bool(edge_review.get("edge_only")),
        "edge_unresolved_count": int(edge_review.get("unresolved_count") or 0),
    }


def build_recommendation(flat_case: dict, dual_case: dict, ordered_case: dict, surface_case: dict, live_pool_case: dict):
    reasons = []
    if flat_case["ae"] < dual_case["ae"]:
        reasons.append(f"flat-ae-beats-dual-by-{dual_case['ae'] - flat_case['ae']}")
    if flat_case["ae"] < ordered_case["ae"]:
        reasons.append(f"flat-ae-beats-ordered-by-{ordered_case['ae'] - flat_case['ae']}")
    if flat_case["rmse"] < dual_case["rmse"]:
        reasons.append("flat-rmse-beats-dual")
    if flat_case["rmse"] < ordered_case["rmse"]:
        reasons.append("flat-rmse-beats-ordered")
    if dual_case["family_total_hits"] > flat_case["family_total_hits"] and dual_case["ae"] > flat_case["ae"]:
        reasons.append("surface-adds-1b85-hit-modes-with-worse-frame-error")
    if ordered_case["family_total_hits"] >= dual_case["family_total_hits"] and ordered_case["ae"] > dual_case["ae"]:
        reasons.append("ordered-only-increases-1b85-coverage-while-regressing-further")
    if surface_case["unresolved_sequence_count"] > 0:
        reasons.append(f"surface-package-keeps-{surface_case['unresolved_sequence_count']}-unresolved-tail-slot")
    if live_pool_case.get("shape_hint") == "rotating-stream-edge-dwell":
        reasons.append("live-stream-shape-is-rotating-stream-edge-dwell")
    if live_pool_case.get("tail_dwell_aligns_with_unresolved_slot"):
        reasons.append("live-tail-dwell-still-aligns-with-unresolved-slot")
    if live_pool_case.get("runtime_shape_recommendation"):
        reasons.append(f"live-review={live_pool_case['runtime_shape_recommendation']}")

    return {
        "recommendation": "keep-flat-runtime-binding",
        "pool_follow_up": "defer-runtime-pool-semantics",
        "reasons": reasons,
        "deferred_work": [
            "do-not-promote-ordered-surface-runtime-for-1b8530fb-yet",
            "do-not-collapse-1b8530fb-into-a-single-selector-alias",
            "keep-triangle-source-work-separated-from-1b8530fb-pool-semantics",
            "keep-native-duplicate-policy-separated-from-1b8530fb-pool-semantics",
        ],
    }


def render_markdown(review: dict):
    recommendation = review["recommendation"]
    live = review["live_pool_review"]
    surface = review["surface_package"]
    lines = [
        "# Sampled Pool Regression Review",
        "",
        f"- sampled_low32: `{review['sampled_low32']}`",
        f"- recommendation: `{recommendation['recommendation']}`",
        f"- pool follow-up: `{recommendation['pool_follow_up']}`",
        f"- live runtime replacement: `{live.get('runtime_sample_replacement_id')}`",
        "",
        "## Why",
        "",
    ]
    for reason in recommendation["reasons"]:
        lines.append(f"- `{reason}`")

    lines.extend(["", "## Historical Comparison", ""])
    for case in review["cases"]:
        reason_summary = ", ".join(
            f"{row['reason']} x`{row['count']}`" for row in case.get("family_reason_counts") or []
        ) or "none"
        lines.extend(
            [
                f"### {case['label']}",
                "",
                f"- Summary: `{case['summary_path']}`",
                f"- AE / RMSE: `{case['ae']}` / `{case['rmse']}`",
                f"- Exact hits / conflict / unresolved: `{case['exact_hit_count']}` / `{case['exact_conflict_miss_count']}` / `{case['exact_unresolved_miss_count']}`",
                f"- `1b8530fb` hit total: `{case['family_total_hits']}`",
                f"- `1b8530fb` reasons: {reason_summary}",
                "",
            ]
        )

    lines.extend(
        [
            "## Surface Package",
            "",
            f"- Source: `{surface['surface_package_path']}`",
            f"- shape_hint: `{surface.get('shape_hint')}`",
            f"- slot_count: `{surface.get('slot_count')}`",
            f"- replacement_id_count: `{surface.get('replacement_id_count')}`",
            f"- unresolved_sequence_count: `{surface.get('unresolved_sequence_count')}`",
        ]
    )
    first_unresolved = surface.get("first_unresolved_sequence")
    if first_unresolved:
        lines.append(
            "- first_unresolved_sequence: "
            f"`index={first_unresolved.get('sequence_index')}` "
            f"`upload_key={first_unresolved.get('upload_key')}`"
        )

    lines.extend(
        [
            "",
            "## Live Pool Review",
            "",
            f"- Review: `{live['pool_review_path']}`",
            f"- runtime_shape_recommendation: `{live.get('runtime_shape_recommendation')}`",
            f"- pool_recommendation: `{live.get('pool_recommendation')}`",
            f"- runtime_sample_policy: `{live.get('runtime_sample_policy')}`",
            f"- runtime_sample_replacement_id: `{live.get('runtime_sample_replacement_id')}`",
            f"- shape_hint: `{live.get('shape_hint')}`",
            f"- slot_count / mapped / unresolved / candidates: `{live.get('slot_count')}` / `{live.get('mapped_candidate_count')}` / `{live.get('unresolved_count')}` / `{live.get('candidate_count')}`",
            f"- tail_dwell_aligns_with_unresolved_slot: `{str(live.get('tail_dwell_aligns_with_unresolved_slot')).lower()}`",
            "",
            "## Deferred Work",
            "",
        ]
    )
    for item in recommendation["deferred_work"]:
        lines.append(f"- `{item}`")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Compare flat vs surface-shaped runtime evidence for one sampled pool family.")
    parser.add_argument("--sampled-low32", required=True, help="Family to review, for example 1b8530fb")
    parser.add_argument("--step-frames", type=int, default=960, help="Validation step to compare (default: 960)")
    parser.add_argument("--flat-summary", required=True, help="Historical flat validation summary JSON")
    parser.add_argument("--dual-summary", required=True, help="Historical dual flat+surface validation summary JSON")
    parser.add_argument("--ordered-summary", required=True, help="Historical ordered-only validation summary JSON")
    parser.add_argument("--surface-package", required=True, help="Historical surface-package JSON")
    parser.add_argument("--live-pool-review", required=True, help="Current live pool review JSON")
    parser.add_argument("--output", required=True, help="Markdown output path")
    parser.add_argument("--output-json", required=True, help="JSON output path")
    args = parser.parse_args()

    sampled_low32 = str(args.sampled_low32).lower()
    flat_case = build_case("flat", Path(args.flat_summary), sampled_low32, args.step_frames)
    dual_case = build_case("dual", Path(args.dual_summary), sampled_low32, args.step_frames)
    ordered_case = build_case("ordered-only", Path(args.ordered_summary), sampled_low32, args.step_frames)
    surface_case = load_surface_case(Path(args.surface_package), sampled_low32)
    live_pool_case = summarize_live_pool_review(Path(args.live_pool_review))
    recommendation = build_recommendation(flat_case, dual_case, ordered_case, surface_case, live_pool_case)

    review = {
        "sampled_low32": sampled_low32,
        "step_frames": args.step_frames,
        "recommendation": recommendation,
        "cases": [flat_case, dual_case, ordered_case],
        "surface_package": surface_case,
        "live_pool_review": live_pool_case,
    }

    output_json_path = Path(args.output_json)
    output_json_path.write_text(json.dumps(review, indent=2) + "\n")
    Path(args.output).write_text(render_markdown(review))


if __name__ == "__main__":
    main()
