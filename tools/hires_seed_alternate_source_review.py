#!/usr/bin/env python3
import argparse
import copy
import json
from collections import Counter
from pathlib import Path

from hires_pack_common import parse_cache_entries
from hires_seed_review_pool import build_candidate


def load_json(path: Path):
    return json.loads(path.read_text())


def parse_wh(raw_value: str | None):
    text = str(raw_value or "").strip().lower()
    if not text or text == "0x0" or "x" not in text:
        raise SystemExit(f"unable to derive sampled dimensions from {raw_value!r}")
    width_text, height_text = text.split("x", 1)
    return int(width_text), int(height_text)


def build_selector_targets(selector_review: dict, requested_low32s):
    def target_key(row: dict):
        return (
            str(row.get("sampled_low32") or "").lower(),
            str(row.get("draw_class") or "").lower(),
            str(row.get("cycle") or "").lower(),
            str(row.get("fs") or ""),
        )

    requested = {str(value).lower() for value in (requested_low32s or []) if str(value).strip()}
    unresolved = selector_review.get("unresolved") or []
    targets = []
    seen = set()
    if requested:
        for row in unresolved:
            if str(row.get("sampled_low32") or "").lower() in requested:
                key = target_key(row)
                if key in seen:
                    continue
                seen.add(key)
                targets.append(row)
        found = {str(row.get("sampled_low32") or "").lower() for row in targets}
        missing = sorted(requested.difference(found))
        if missing:
            raise SystemExit(f"requested sampled_low32 values are missing from selector review: {missing}")
        return targets

    for row in unresolved:
        if row.get("package_status") != "absent-from-package":
            continue
        if row.get("transport_status") != "legacy-transport-candidate-free":
            continue
        key = target_key(row)
        if key in seen:
            continue
        seen.add(key)
        targets.append(row)
    return targets


def find_review_groups(review: dict, target: dict):
    key = (
        str(target.get("sampled_low32") or "").lower(),
        str(target.get("draw_class") or "").lower(),
        str(target.get("cycle") or "").lower(),
        str(target.get("fs") or ""),
    )
    matches = []
    for group in review.get("groups", []):
        signature = group.get("signature") or {}
        group_key = (
            str(signature.get("sampled_low32") or "").lower(),
            str(signature.get("draw_class") or "").lower(),
            str(signature.get("cycle") or "").lower(),
            str(signature.get("formatsize") or ""),
        )
        if group_key == key:
            matches.append(group)
    if not matches:
        raise SystemExit(f"no transport review group matched selector review target {key}")
    return matches


def select_seed_candidates(cache_entries, cache_path: Path, width: int, height: int):
    selected = []
    for entry in cache_entries:
        if int(entry["width"]) != width or int(entry["height"]) != height:
            continue
        selected.append(build_candidate(entry, cache_path))
    selected.sort(key=lambda item: item["replacement_id"])
    return selected


def seed_group(groups: list[dict], cache_entries, cache_path: Path):
    seeded = copy.deepcopy(groups[0])
    deduped_candidates = {}
    dim_counter = Counter()
    pixel_counter = Counter()
    formatsize_counter = Counter()
    matched_review_groups = []
    seed_dimensions = []

    for group in groups:
        canonical_identity = group.get("canonical_identity") or {}
        sampled_width, sampled_height = parse_wh(canonical_identity.get("wh"))
        dims = f"{sampled_width}x{sampled_height}"
        seed_dimensions.append(dims)
        candidates = select_seed_candidates(cache_entries, cache_path, sampled_width, sampled_height)
        matched_review_groups.append(
            {
                "signature": group.get("signature") or {},
                "canonical_identity": canonical_identity,
                "seed_dimensions": dims,
                "candidate_count": len(candidates),
            }
        )
        for candidate in candidates:
            deduped_candidates[candidate["replacement_id"]] = candidate
        dim_counter.update(f"{candidate['width']}x{candidate['height']}" for candidate in candidates)
        pixel_counter.update(candidate["pixel_sha256"] for candidate in candidates)
        formatsize_counter.update(int(candidate["formatsize"]) for candidate in candidates)

    candidates = [deduped_candidates[key] for key in sorted(deduped_candidates)]
    unique_seed_dimensions = sorted(set(seed_dimensions))
    seeded["matched_review_group_count"] = len(groups)
    seeded["matched_review_groups"] = matched_review_groups
    seeded["transport_candidates"] = candidates
    seeded["unique_transport_candidate_count"] = len(candidates)
    seeded["unique_transport_pixel_count"] = len(pixel_counter)
    seeded["transport_candidate_dims"] = [
        {"dims": dims, "count": count} for dims, count in dim_counter.most_common()
    ]
    seeded["alternate_source_status"] = (
        "source-backed-candidates-available" if candidates else "source-backed-candidate-free"
    )
    note = (
        "Review-only source-backed candidate pool seeded from canonical sampled dimensions. "
        "This does not assert selector correctness or runtime promotion."
    )
    if len(groups) > 1:
        note += " Multiple transport review groups matched this selector family; keep this lane review-only until the ambiguity is classified."
    seeded["seeded_transport_pool"] = {
        "source": "alternate-source-dimension-seed",
        "cache_path": str(cache_path),
        "seed_dimensions": unique_seed_dimensions[0] if len(unique_seed_dimensions) == 1 else "multiple",
        "seed_dimension_set": unique_seed_dimensions,
        "candidate_count": len(candidates),
        "candidate_formatsizes": sorted(formatsize_counter),
        "matched_review_group_count": len(groups),
        "note": note,
    }
    return seeded


def render_markdown(review: dict):
    lines = [
        "# Alternate-Source Review",
        "",
        f"- Source review: `{review.get('source_review_path', '')}`",
        f"- Selector review: `{review.get('selector_review_path', '')}`",
        f"- Cache: `{review.get('cache', '')}`",
        f"- Target groups: `{review.get('group_count', 0)}`",
        f"- Groups with candidates: `{review.get('available_group_count', 0)}`",
        f"- Total candidates: `{review.get('total_candidate_count', 0)}`",
        "",
    ]

    for group in review.get("groups", []):
        signature = group.get("signature") or {}
        seeded = group.get("seeded_transport_pool") or {}
        lines.extend([
            f"## `{signature.get('sampled_low32')}` `{signature.get('draw_class')}` / `{signature.get('cycle')}` `fs={signature.get('formatsize')}`",
            "",
            f"- Source status: `{group.get('alternate_source_status')}`",
            f"- Matched review groups: `{group.get('matched_review_group_count', 1)}`",
            f"- Seed dimensions: `{seeded.get('seed_dimensions')}`",
            f"- Seed dimension set: `{seeded.get('seed_dimension_set')}`",
            f"- Candidate count: `{seeded.get('candidate_count')}`",
            f"- Candidate formatsizes: `{seeded.get('candidate_formatsizes')}`",
            f"- Note: {seeded.get('note')}",
            "",
            "| candidate | dims | fs | palette | pixel sha256 |",
            "|---|---|---|---|---|",
        ])
        for candidate in group.get("transport_candidates", []):
            lines.append(
                f"| `{candidate['replacement_id']}` | `{candidate['width']}x{candidate['height']}` | "
                f"`{candidate['formatsize']}` | `{candidate['palette_crc']}` | `{candidate['pixel_sha256'][:16]}` |"
            )
        if not group.get("transport_candidates"):
            lines.append("| _none_ |  |  |  |  |")
        lines.append("")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(
        description="Seed review-only alternate-source candidates for candidate-free sampled families."
    )
    parser.add_argument("--review", required=True, help="Input sampled transport review JSON")
    parser.add_argument("--selector-review", required=True, help="Input sampled selector review JSON")
    parser.add_argument("--cache", required=True, help="Legacy .hts/.htc cache path used as alternate source")
    parser.add_argument("--sampled-low32", action="append", help="Optional sampled_low32 override. Pass multiple times.")
    parser.add_argument("--output-json", required=True, help="Output JSON path")
    parser.add_argument("--output-markdown", required=True, help="Output markdown path")
    args = parser.parse_args()

    review_path = Path(args.review)
    selector_review_path = Path(args.selector_review)
    cache_path = Path(args.cache)

    review = load_json(review_path)
    selector_review = load_json(selector_review_path)
    cache_entries = parse_cache_entries(cache_path)

    targets = build_selector_targets(selector_review, args.sampled_low32)
    seeded_groups = [seed_group(find_review_groups(review, target), cache_entries, cache_path) for target in targets]

    result = {
        "schema_version": 1,
        "source_review_path": str(review_path),
        "selector_review_path": str(selector_review_path),
        "cache": str(cache_path),
        "seed_mode": "alternate-source-dimension-seed",
        "group_count": len(seeded_groups),
        "available_group_count": sum(
            1 for group in seeded_groups if (group.get("seeded_transport_pool") or {}).get("candidate_count")
        ),
        "total_candidate_count": sum(
            int((group.get("seeded_transport_pool") or {}).get("candidate_count") or 0)
            for group in seeded_groups
        ),
        "groups": seeded_groups,
    }

    output_json_path = Path(args.output_json)
    output_json_path.parent.mkdir(parents=True, exist_ok=True)
    output_json_path.write_text(json.dumps(result, indent=2) + "\n")

    output_markdown_path = Path(args.output_markdown)
    output_markdown_path.parent.mkdir(parents=True, exist_ok=True)
    output_markdown_path.write_text(render_markdown(result))


if __name__ == "__main__":
    main()
