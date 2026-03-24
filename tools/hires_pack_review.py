#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

from hires_pack_common import parse_cache_entries, parse_bundle_ci_context, parse_bundle_families
from hires_pack_migrate import build_imported_index, load_import_policy


def analyze_variant_groups(variant_groups, observed, applied_policy):
    sample_dims = observed.get("sample_replacement_dims")
    suggested_group_id = (applied_policy or {}).get("suggested_variant_group_id")
    selected_group_id = (applied_policy or {}).get("selected_variant_group_id")

    analyzed = []
    for group in variant_groups:
        notes = []
        score = 0
        if sample_dims and group.get("dims") == sample_dims:
            score += 3
            notes.append("matches observed sample_replacement_dims")
        else:
            notes.append("does not match observed sample_replacement_dims")

        if suggested_group_id and group.get("variant_group_id") == suggested_group_id:
            score += 2
            notes.append("matches current policy suggestion")
        elif suggested_group_id:
            notes.append("does not match current policy suggestion")

        if selected_group_id and group.get("variant_group_id") == selected_group_id:
            score += 4
            notes.append("matches current policy selection")

        if group.get("candidate_count", 0) == 1:
            score += 1
            notes.append("single replacement candidate")
        else:
            notes.append("multiple replacement candidates")

        if group.get("legacy_palette_crc_count", 0) == 1:
            score += 1
            notes.append("single palette CRC in group")
        else:
            notes.append("multiple palette CRCs in group")

        analyzed.append(
            {
                **group,
                "review_score": score,
                "review_notes": notes,
            }
        )

    analyzed.sort(key=lambda item: (-item["review_score"], item["variant_group_id"]))
    return analyzed


def summarize_family(record, family_type):
    selector_policy = record.get("selector_policy") or {}
    observed = record.get("observed_runtime_context") or {}
    variant_groups = record.get("variant_groups") or record.get("diagnostics", {}).get("variant_groups", [])
    applied_policy = selector_policy.get("applied_policy")
    analyzed_variant_groups = analyze_variant_groups(
        [
            {
                "variant_group_id": group.get("variant_group_id"),
                "dims": group.get("dims"),
                "candidate_count": len(group.get("candidate_replacement_ids", [])),
                "legacy_palette_crc_count": len(group.get("legacy_palette_crcs", [])),
            }
            for group in variant_groups
        ],
        observed,
        applied_policy,
    )

    summary = {
        "family_type": family_type,
        "policy_key": record.get("policy_key") or record.get("alias_id"),
        "status": selector_policy.get("status"),
        "selection_reason": selector_policy.get("selection_reason"),
        "selected_variant_group_id": selector_policy.get("selected_variant_group_id"),
        "candidate_variant_group_ids": selector_policy.get("candidate_variant_group_ids", []),
        "applied_policy": selector_policy.get("applied_policy"),
        "runtime_context": {
            "mode": observed.get("mode"),
            "runtime_wh": observed.get("runtime_wh"),
            "observed_runtime_pcrc": observed.get("observed_runtime_pcrc"),
            "sample_replacement_dims": observed.get("sample_replacement_dims"),
            "usage": observed.get("usage"),
            "emulated_tmem": observed.get("emulated_tmem"),
        },
        "variant_groups": analyzed_variant_groups,
    }

    if family_type == "compatibility":
        summary["kind"] = record.get("kind")
    else:
        summary["reason"] = record.get("reason")

    return summary


def build_review_report(cache_path, bundle_path, policy_path=None):
    entries = parse_cache_entries(cache_path)
    requested_pairs = parse_bundle_families(bundle_path)
    bundle_context = parse_bundle_ci_context(bundle_path)
    import_policy = {"families": {}}
    if policy_path:
        import_policy = load_import_policy(policy_path)

    imported_index = build_imported_index(
        entries,
        requested_pairs,
        cache_path,
        bundle_context=bundle_context,
        import_policy=import_policy,
    )

    compatibility = [
        summarize_family(record, "compatibility")
        for record in imported_index.get("compatibility_aliases", [])
    ]
    unresolved = [
        summarize_family(record, "unresolved")
        for record in imported_index.get("unresolved_families", [])
    ]

    return {
        "cache_path": str(cache_path),
        "bundle_path": str(bundle_path),
        "policy_source": imported_index.get("policy_source"),
        "summary": {
            "compatibility_family_count": len(compatibility),
            "unresolved_family_count": len(unresolved),
            "deterministic_count": sum(1 for record in compatibility + unresolved if record.get("status") == "deterministic"),
            "manual_disambiguation_required_count": sum(
                1 for record in compatibility + unresolved if record.get("status") == "manual-disambiguation-required"
            ),
        },
        "compatibility_families": compatibility,
        "unresolved_families": unresolved,
    }


def format_markdown(report):
    lines = []
    lines.append("# Hi-Res Pack Review")
    lines.append("")
    lines.append(f"- Cache: `{report['cache_path']}`")
    lines.append(f"- Bundle: `{report['bundle_path']}`")
    if report.get("policy_source"):
        lines.append(f"- Policy: `{report['policy_source']['path']}`")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    summary = report["summary"]
    lines.append(f"- Compatibility families: `{summary['compatibility_family_count']}`")
    lines.append(f"- Unresolved families: `{summary['unresolved_family_count']}`")
    lines.append(f"- Deterministic selectors: `{summary['deterministic_count']}`")
    lines.append(f"- Manual disambiguation required: `{summary['manual_disambiguation_required_count']}`")

    for section_name, families in (
        ("Compatibility Families", report["compatibility_families"]),
        ("Unresolved Families", report["unresolved_families"]),
    ):
        lines.append("")
        lines.append(f"## {section_name}")
        lines.append("")
        if not families:
            lines.append("- None")
            continue
        for family in families:
            lines.append(f"- `{family['policy_key']}`")
            lines.append(f"  - status: `{family['status']}`")
            if family.get("kind"):
                lines.append(f"  - kind: `{family['kind']}`")
            if family.get("reason"):
                lines.append(f"  - reason: `{family['reason']}`")
            lines.append(f"  - selection_reason: `{family['selection_reason']}`")
            if family.get("selected_variant_group_id"):
                lines.append(f"  - selected_variant_group_id: `{family['selected_variant_group_id']}`")
            runtime = family["runtime_context"]
            lines.append(
                f"  - runtime: mode=`{runtime.get('mode')}` wh=`{runtime.get('runtime_wh')}` pcrc=`{runtime.get('observed_runtime_pcrc')}` sample_repl=`{runtime.get('sample_replacement_dims')}`"
            )
            if family.get("applied_policy"):
                lines.append(f"  - applied_policy: `{json.dumps(family['applied_policy'], sort_keys=True)}`")
                for note in family["applied_policy"].get("selection_notes", []):
                    lines.append(f"    - policy_note: {note}")
                for note in family["applied_policy"].get("supporting_notes", []):
                    lines.append(f"    - policy_note: {note}")
                for weaker in family["applied_policy"].get("weaker_variant_groups", []):
                    lines.append(f"    - weaker_variant_group `{weaker['variant_group_id']}`")
                    for reason in weaker.get("reasons", []):
                        lines.append(f"      - {reason}")
            for group in family["variant_groups"]:
                lines.append(
                    f"  - variant_group `{group['variant_group_id']}` dims=`{group['dims']}` candidates=`{group['candidate_count']}` palette_crcs=`{group['legacy_palette_crc_count']}` review_score=`{group['review_score']}`"
                )
                for note in group["review_notes"]:
                    lines.append(f"    - {note}")

    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Review a bundle-backed hi-res import slice without committing to a final format.")
    parser.add_argument("--cache", required=True, help="Path to .hts or .htc pack.")
    parser.add_argument("--bundle", required=True, help="Strict bundle path.")
    parser.add_argument("--policy", help="Optional import policy JSON.")
    parser.add_argument("--format", choices=("json", "markdown"), default="json")
    parser.add_argument("--output", help="Optional output path.")
    args = parser.parse_args()

    report = build_review_report(Path(args.cache), Path(args.bundle), Path(args.policy) if args.policy else None)
    if args.format == "markdown":
        serialized = format_markdown(report)
    else:
        serialized = json.dumps(report, indent=2) + "\n"

    if args.output:
        Path(args.output).write_text(serialized)
    else:
        sys.stdout.write(serialized)


if __name__ == "__main__":
    main()
