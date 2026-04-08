#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

from hires_sampled_draw_sequence import build_summary as build_draw_sequence_summary
from hires_sampled_draw_sequence import parse_rows as parse_draw_sequence_rows
from hires_sampled_surface_map import build_map as build_surface_map
from hires_sampled_surface_map import load_json as load_surface_json
from hires_sampled_surface_map import review_group as review_transport_group
from hires_surface_edge_review import classify_unresolved_slots


class MissingDrawSequenceError(RuntimeError):
    pass


def load_json(path: Path):
    return json.loads(path.read_text())


def find_pool_family(selector_review: dict, sampled_low32: str) -> dict:
    for row in selector_review.get("pool_families", []):
        if row.get("sampled_low32") == sampled_low32:
            return row
    raise SystemExit(f"pool family {sampled_low32} not found in selector review")


def primary_selector(row: dict) -> str:
    selectors = row.get("selectors") or []
    if not selectors:
        raise SystemExit(f"pool family {row.get('sampled_low32')} is missing selectors")
    best = max(selectors, key=lambda item: int(item.get("count") or 0))
    selector = str(best.get("selector") or "").lower()
    if not selector:
        raise SystemExit(f"pool family {row.get('sampled_low32')} has an empty selector")
    return selector


def build_edge_surface(sampled_low32: str, surface_map: dict) -> dict:
    return {
        "surface_id": f"sampled-low32-{sampled_low32}-ordered-surface-review",
        "sampled_low32": sampled_low32,
        "slot_count": int(surface_map.get("sequence_count") or 0),
        "slots": [
            {
                "sequence_index": int(row.get("sequence_index") or 0),
                "replacement_id": row.get("replacement_id"),
                "upload_key": row.get("upload_key"),
                "addr_hex": row.get("addr_hex"),
            }
            for row in surface_map.get("surface_map", [])
        ],
        "unresolved_sequences": [
            {
                "sequence_index": int(row.get("sequence_index") or 0),
                "upload_key": row.get("upload_key"),
                "addr_hex": row.get("addr_hex"),
            }
            for row in surface_map.get("unresolved_sequences", [])
        ],
    }


def dominant_delta(sequence_summary: dict):
    rows = sequence_summary.get("cyclic_delta_counts") or []
    if not rows:
        return None, 0
    top = rows[0]
    return int(top.get("delta") or 0), int(top.get("count") or 0)


def summarize_tail_dwell(sequence_summary: dict, edge_review: dict) -> dict:
    repeated_runs = sequence_summary.get("repeated_runs") or []
    unresolved_by_index = {
        int(row.get("sequence_index") or 0): row for row in edge_review.get("unresolved_slots", [])
    }
    dominant = repeated_runs[0] if repeated_runs else None
    if dominant is None:
        return {
            "present": False,
            "aligns_with_unresolved_slot": False,
            "aligns_with_edge_slot": False,
        }
    sequence_index = int(dominant.get("sequence_index") or 0)
    unresolved = unresolved_by_index.get(sequence_index)
    return {
        "present": True,
        "sequence_index": sequence_index,
        "key": dominant.get("key"),
        "run_length": int(dominant.get("run_length") or 0),
        "aligns_with_unresolved_slot": unresolved is not None,
        "aligns_with_edge_slot": unresolved is not None and unresolved.get("position_class") != "interior",
        "position_class": unresolved.get("position_class") if unresolved else None,
    }


def build_runtime_shape_recommendation(pool_family: dict, sequence_summary: dict, edge_review: dict, tail_dwell: dict):
    reasons = []
    shape_hint = sequence_summary.get("shape_hint")
    if shape_hint:
        reasons.append(f"shape_hint={shape_hint}")
    if edge_review.get("unresolved_count"):
        unresolved = edge_review.get("unresolved_count")
        reasons.append(f"ordered_surface_unresolved_slots={unresolved}")
    if edge_review.get("edge_only"):
        reasons.append("unresolved_slots=edge_only")
    if tail_dwell.get("present"):
        reasons.append(f"tail_dwell_run_length={tail_dwell.get('run_length')}")
    if tail_dwell.get("aligns_with_unresolved_slot"):
        reasons.append("tail_dwell_aligns_with_unresolved_slot")
    if int(pool_family.get("pool_matching_runtime_selector_count") or 0) == 0:
        reasons.append("runtime_family_selector_is_not_slot_aligned")

    if (
        pool_family.get("pool_recommendation") == "defer-runtime-pool-semantics"
        and shape_hint == "rotating-stream-edge-dwell"
        and edge_review.get("edge_only")
        and tail_dwell.get("aligns_with_unresolved_slot")
    ):
        return "keep-flat-runtime-binding", reasons
    if pool_family.get("pool_recommendation") == "candidate-runtime-pool-alignment":
        return "candidate-runtime-pool-alignment", reasons
    if pool_family.get("pool_recommendation"):
        return str(pool_family.get("pool_recommendation")), reasons
    return "inspect-runtime-pool-semantics", reasons


def build_deferred_review(bundle_dir: Path, selector_review: dict, sampled_low32: str, reason: str):
    pool_family = find_pool_family(selector_review, sampled_low32)
    return {
        "bundle": str(bundle_dir),
        "sampled_low32": sampled_low32,
        "sampled_key": primary_selector(pool_family),
        "draw_class": pool_family.get("draw_class") or "texrect",
        "cycle": pool_family.get("cycle") or "copy",
        "formatsize": int(pool_family.get("fs") or 0),
        "runtime_sample_policy": pool_family.get("runtime_sample_policy"),
        "runtime_sample_replacement_id": pool_family.get("runtime_sample_replacement_id"),
        "runtime_sampled_object": pool_family.get("runtime_sampled_object"),
        "runtime_sample_repl": pool_family.get("runtime_sample_repl"),
        "pool_recommendation": pool_family.get("pool_recommendation"),
        "runtime_shape_recommendation": None,
        "review_status": "deferred-no-live-draw-sequence",
        "recommendation_reasons": [
            reason,
            "defer-to-historical-pool-regression-review",
        ],
        "transport_group_signature": {},
        "sequence_summary": {},
        "surface_map_summary": {},
        "edge_review": {},
        "tail_dwell": {},
        "sequence": {},
        "surface_map": {},
    }


def build_review(bundle_dir: Path, selector_review: dict, transport_review: dict, sampled_low32: str):
    pool_family = find_pool_family(selector_review, sampled_low32)
    selector = primary_selector(pool_family)
    draw_class = pool_family.get("draw_class") or "texrect"
    cycle = pool_family.get("cycle") or "copy"
    formatsize = int(pool_family.get("fs") or 0)
    replacement_dims = pool_family.get("runtime_sample_repl")

    log_path = bundle_dir / "logs" / "retroarch.log"
    rows = parse_draw_sequence_rows(
        log_path,
        selector,
        draw_class,
        cycle,
        sampled_texel=0,
        varying_texel=1,
    )
    if not rows:
        raise MissingDrawSequenceError(f"no matching draw-usage rows for sampled family {sampled_low32} in {bundle_dir}")

    sequence_summary = build_draw_sequence_summary(
        bundle_dir,
        rows,
        selector,
        draw_class,
        cycle,
        sampled_texel=0,
        varying_texel=1,
    )
    transport_group = review_transport_group(
        transport_review,
        sampled_low32,
        formatsize=formatsize if formatsize else None,
        draw_class=draw_class,
        cycle=cycle,
        replacement_dims=replacement_dims,
    )
    surface_map = build_surface_map(sequence_summary, transport_group, sampled_low32)
    edge_review = classify_unresolved_slots(build_edge_surface(sampled_low32, surface_map))
    tail_dwell = summarize_tail_dwell(sequence_summary, edge_review)
    runtime_shape_recommendation, reasons = build_runtime_shape_recommendation(
        pool_family,
        sequence_summary,
        edge_review,
        tail_dwell,
    )
    delta_value, delta_count = dominant_delta(sequence_summary)

    return {
        "bundle": str(bundle_dir),
        "sampled_low32": sampled_low32,
        "sampled_key": selector,
        "draw_class": draw_class,
        "cycle": cycle,
        "formatsize": formatsize,
        "runtime_sample_policy": pool_family.get("runtime_sample_policy"),
        "runtime_sample_replacement_id": pool_family.get("runtime_sample_replacement_id"),
        "runtime_sampled_object": pool_family.get("runtime_sampled_object"),
        "runtime_sample_repl": replacement_dims,
        "pool_recommendation": pool_family.get("pool_recommendation"),
        "runtime_shape_recommendation": runtime_shape_recommendation,
        "recommendation_reasons": reasons,
        "transport_group_signature": transport_group.get("signature", {}),
        "sequence_summary": {
            "row_count": int(sequence_summary.get("row_count") or 0),
            "unique_key_count": int(sequence_summary.get("unique_key_count") or 0),
            "shape_hint": sequence_summary.get("shape_hint"),
            "dominant_delta": delta_value,
            "dominant_delta_count": delta_count,
            "repeated_run_count": len(sequence_summary.get("repeated_runs") or []),
        },
        "surface_map_summary": {
            "slot_count": int(surface_map.get("sequence_count") or 0),
            "mapped_candidate_count": int(surface_map.get("mapped_candidate_count") or 0),
            "unresolved_count": int(surface_map.get("unresolved_count") or 0),
            "candidate_count": len(transport_group.get("transport_candidates", [])),
            "resolved_ratio": (
                float(surface_map.get("mapped_candidate_count") or 0) / float(surface_map.get("sequence_count") or 1)
            ),
        },
        "edge_review": edge_review,
        "tail_dwell": tail_dwell,
        "sequence": sequence_summary,
        "surface_map": surface_map,
    }


def render_markdown(review: dict) -> str:
    review_status = review.get("review_status") or "complete"
    lines = [
        "# Sampled Pool Review",
        "",
        f"- Bundle: `{review['bundle']}`",
        f"- sampled_low32: `{review['sampled_low32']}`",
        f"- sampled_key: `{review['sampled_key']}`",
        f"- draw_class: `{review['draw_class']}`",
        f"- cycle: `{review['cycle']}`",
        f"- runtime_sample_policy: `{review.get('runtime_sample_policy')}`",
        f"- runtime_sample_replacement_id: `{review.get('runtime_sample_replacement_id')}`",
        f"- runtime_sampled_object: `{review.get('runtime_sampled_object')}`",
        f"- runtime_sample_repl: `{review.get('runtime_sample_repl')}`",
        f"- pool_recommendation: `{review.get('pool_recommendation')}`",
        f"- runtime_shape_recommendation: `{review.get('runtime_shape_recommendation')}`",
        f"- review_status: `{review_status}`",
        "",
        "## Why",
        "",
    ]
    reasons = review.get("recommendation_reasons") or []
    if reasons:
        for reason in reasons:
            lines.append(f"- `{reason}`")
    else:
        lines.append("- none")

    if review_status != "complete":
        lines.extend(
            [
                "",
                "## Deferred",
                "",
                "- live draw-sequence rows were not present for this family in the current bundle",
                "- use the historical pool-regression review as the controlling runtime-shape evidence for now",
                "",
            ]
        )
        return "\n".join(lines)

    sequence = review.get("sequence_summary") or {}
    surface_map = review.get("surface_map_summary") or {}
    tail_dwell = review.get("tail_dwell") or {}
    edge_review = review.get("edge_review") or {}
    lines.extend([
        "",
        "## Sequence",
        "",
        f"- shape_hint: `{sequence.get('shape_hint')}`",
        f"- row_count: `{sequence.get('row_count')}`",
        f"- unique_key_count: `{sequence.get('unique_key_count')}`",
        f"- dominant_delta: `{sequence.get('dominant_delta')}` x`{sequence.get('dominant_delta_count')}`",
        f"- repeated_run_count: `{sequence.get('repeated_run_count')}`",
        "",
        "## Surface Map",
        "",
        f"- slot_count: `{surface_map.get('slot_count')}`",
        f"- mapped_candidate_count: `{surface_map.get('mapped_candidate_count')}`",
        f"- unresolved_count: `{surface_map.get('unresolved_count')}`",
        f"- candidate_count: `{surface_map.get('candidate_count')}`",
        f"- resolved_ratio: `{surface_map.get('resolved_ratio')}`",
        "",
        "## Edge Review",
        "",
        f"- edge_only: `{1 if edge_review.get('edge_only') else 0}`",
        f"- unresolved_count: `{edge_review.get('unresolved_count')}`",
    ])
    if edge_review.get("unresolved_slots"):
        lines.extend([
            "",
            "| seq | class | upload key | prev replacement | next replacement |",
            "|---:|---|---|---|---|",
        ])
        for row in edge_review.get("unresolved_slots", []):
            lines.append(
                f"| `{row.get('sequence_index')}` | `{row.get('position_class')}` | `{row.get('upload_key')}` | "
                f"`{row.get('prev_replacement_id') or '-'}` | `{row.get('next_replacement_id') or '-'}` |"
            )
    lines.extend([
        "",
        "## Tail Dwell",
        "",
        f"- present: `{1 if tail_dwell.get('present') else 0}`",
        f"- aligns_with_unresolved_slot: `{1 if tail_dwell.get('aligns_with_unresolved_slot') else 0}`",
        f"- aligns_with_edge_slot: `{1 if tail_dwell.get('aligns_with_edge_slot') else 0}`",
        f"- sequence_index: `{tail_dwell.get('sequence_index')}`",
        f"- run_length: `{tail_dwell.get('run_length')}`",
        "",
    ])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Review a sampled pool family against live draw sequence, transport candidates, and edge dwell."
    )
    parser.add_argument("--bundle-dir", required=True)
    parser.add_argument("--selector-review", required=True)
    parser.add_argument("--transport-review", required=True)
    parser.add_argument("--sampled-low32", required=True)
    parser.add_argument("--output")
    parser.add_argument("--output-json")
    parser.add_argument("--allow-missing-draw-sequence", action="store_true")
    args = parser.parse_args()

    bundle_dir = Path(args.bundle_dir)
    selector_review = load_json(Path(args.selector_review))
    transport_review = load_surface_json(Path(args.transport_review))
    try:
        review = build_review(bundle_dir, selector_review, transport_review, args.sampled_low32.lower())
    except MissingDrawSequenceError as exc:
        if not args.allow_missing_draw_sequence:
            raise SystemExit(str(exc))
        review = build_deferred_review(bundle_dir, selector_review, args.sampled_low32.lower(), str(exc))
    serialized = json.dumps(review, indent=2) + "\n"

    if args.output_json:
        output_json = Path(args.output_json)
        output_json.parent.mkdir(parents=True, exist_ok=True)
        output_json.write_text(serialized)
    else:
        print(serialized, end="")
    if args.output:
        output_markdown = Path(args.output)
        output_markdown.parent.mkdir(parents=True, exist_ok=True)
        output_markdown.write_text(render_markdown(review) + "\n")


if __name__ == "__main__":
    main()
