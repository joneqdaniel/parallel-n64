#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path


SIGNATURE_FIELDS = (
    "draw_class",
    "cycle",
    "tile",
    "fmt",
    "siz",
    "pal",
    "off",
    "stride",
    "wh",
    "upload_low32",
    "upload_pcrc",
    "sampled_low32",
    "sampled_entry_pcrc",
    "sampled_sparse_pcrc",
    "fs",
)


def load_json(path: Path):
    return json.loads(path.read_text())


def parse_labeled_path(value: str):
    if "=" not in value:
        raise SystemExit(f"expected LABEL=PATH, got {value!r}")
    label, raw_path = value.split("=", 1)
    label = label.strip()
    raw_path = raw_path.strip()
    if not label or not raw_path:
        raise SystemExit(f"expected LABEL=PATH, got {value!r}")
    return label, Path(raw_path)


def signature_payload(group: dict):
    return {field: str(group.get(field) or "") for field in SIGNATURE_FIELDS}


def signature_key(group: dict):
    return tuple((field, str(group.get(field) or "")) for field in SIGNATURE_FIELDS)


def parse_fields(detail: str):
    fields = {}
    for key, value in re.findall(r"([A-Za-z0-9_]+)=([^ ]+)", detail):
        fields[key] = value.rstrip(".")
    return fields


def infer_log_path(evidence_path: Path):
    candidates = [
        evidence_path.parent.parent / "logs" / "retroarch.log",
        evidence_path.parent / "retroarch.log",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None


def collect_signatures_from_rows(rows: list[dict], sampled_low32: str):
    signatures = []
    for row in rows:
        fields = row.get("fields") or {}
        if str(fields.get("sampled_low32") or "").lower() != sampled_low32:
            continue
        detail = row.get("sample_detail")
        if detail:
            fields = parse_fields(detail)
        signatures.append(signature_payload(fields))
    return signatures


def collect_signatures_from_log(log_path: Path, sampled_low32: str):
    signatures = []
    marker = f"sampled_low32={sampled_low32}"
    for line in log_path.read_text().splitlines():
        if "Hi-res sampled-object probe:" not in line or marker not in line.lower():
            continue
        _, detail = line.split("Hi-res sampled-object probe:", 1)
        signatures.append(signature_payload(parse_fields(detail.strip())))
    return signatures


def dedupe_signatures(signatures: list[dict]):
    unique = {}
    for signature in signatures:
        unique[signature_key(signature)] = signature
    return list(unique.values())


def collect_label_family(label: str, evidence_path: Path, sampled_low32: str):
    evidence = load_json(evidence_path)
    probe = evidence.get("sampled_object_probe") or {}
    group_signatures = [
        signature_payload(group)
        for group in (probe.get("groups") or [])
        if str(group.get("sampled_low32") or "").lower() == sampled_low32
    ]
    bucket_signatures = collect_signatures_from_rows(probe.get("top_groups") or [], sampled_low32)
    log_signatures = []
    log_path = infer_log_path(evidence_path)
    if log_path is not None:
        log_signatures = collect_signatures_from_log(log_path, sampled_low32)
    signatures = dedupe_signatures(group_signatures + bucket_signatures + log_signatures)

    def bucket_sum(bucket_name: str):
        total = 0
        for row in probe.get(bucket_name, []) or []:
            fields = row.get("fields") or {}
            if str(fields.get("sampled_low32") or "").lower() != sampled_low32:
                continue
            total += int(row.get("count") or 0)
        return total

    available_states = []
    selectors = []
    for row in probe.get("top_exact_family_buckets", []) or []:
        fields = row.get("fields") or {}
        if str(fields.get("sampled_low32") or "").lower() != sampled_low32:
            continue
        available = str(fields.get("available") or "")
        selector = str(fields.get("selector") or "")
        if available and available not in available_states:
            available_states.append(available)
        if selector and selector not in selectors:
            selectors.append(selector)

    return {
        "label": label,
        "evidence_path": str(evidence_path),
        "log_path": str(log_path) if log_path is not None else None,
        "signature_count": len(signatures),
        "signatures": signatures,
        "group_signature_count": len(dedupe_signatures(group_signatures)),
        "bucket_signature_count": len(dedupe_signatures(bucket_signatures)),
        "log_signature_count": len(dedupe_signatures(log_signatures)),
        "family_bucket_count_observed": bucket_sum("top_exact_family_buckets"),
        "exact_hit_bucket_count_observed": bucket_sum("top_exact_hit_buckets"),
        "exact_miss_bucket_count_observed": bucket_sum("top_exact_miss_buckets"),
        "exact_conflict_bucket_count_observed": bucket_sum("top_exact_conflict_miss_buckets"),
        "exact_unresolved_bucket_count_observed": bucket_sum("top_exact_unresolved_miss_buckets"),
        "family_available_states": available_states,
        "selectors": selectors,
    }


def classify_family(sampled_low32: str, label_records: list[dict], target_labels: list[str], guard_labels: list[str]):
    record_by_label = {record["label"]: record for record in label_records}
    missing_targets = [label for label in target_labels if label not in record_by_label]
    missing_guards = [label for label in guard_labels if label not in record_by_label]
    if missing_targets:
        raise SystemExit(f"sampled_low32 {sampled_low32} is missing target labels: {missing_targets}")
    if missing_guards:
        raise SystemExit(f"sampled_low32 {sampled_low32} is missing guard labels: {missing_guards}")

    def label_signature_map(labels: list[str]):
        result = {}
        for label in labels:
            signatures = {}
            for signature in record_by_label[label]["signatures"]:
                key = tuple((field, signature[field]) for field in SIGNATURE_FIELDS)
                signatures[key] = signature
            result[label] = signatures
        return result

    target_signature_map = label_signature_map(target_labels)
    guard_signature_map = label_signature_map(guard_labels)

    target_union = {}
    for signatures in target_signature_map.values():
        target_union.update(signatures)
    guard_union = {}
    for signatures in guard_signature_map.values():
        guard_union.update(signatures)

    shared_keys = sorted(set(target_union).intersection(guard_union))
    target_exclusive_keys = sorted(set(target_union).difference(guard_union))
    guard_exclusive_keys = sorted(set(guard_union).difference(target_union))
    shared_guard_labels = sorted(
        label
        for label in guard_labels
        if any(key in label_signature_map([label])[label] for key in shared_keys)
    )
    guard_labels_without_observation = sorted(
        label for label in guard_labels if not record_by_label[label]["signatures"]
    )
    target_labels_without_observation = sorted(
        label for label in target_labels if not record_by_label[label]["signatures"]
    )

    if not target_union:
        promotion_status = "target-not-observed"
        recommendation = "defer-family-until-target-scene-observes-it"
    elif not guard_union:
        promotion_status = "target-exclusive-runtime-signatures-observed"
        recommendation = "candidate-bounded-target-exclusive-probe-is-allowed"
    elif target_exclusive_keys and shared_keys:
        promotion_status = "partial-overlap-runtime-signatures"
        recommendation = "keep-family-review-only-until-shared-signatures-are-explained"
    elif target_exclusive_keys:
        promotion_status = "target-exclusive-runtime-signatures-observed"
        recommendation = "candidate-bounded-target-exclusive-probe-is-allowed"
    else:
        promotion_status = "no-runtime-discriminator-observed"
        recommendation = "keep-family-review-only-until-new-runtime-discriminator-or-source-evidence"

    return {
        "sampled_low32": sampled_low32,
        "target_labels": target_labels,
        "guard_labels": guard_labels,
        "labels": label_records,
        "target_signature_count": len(target_union),
        "guard_signature_count": len(guard_union),
        "shared_signature_count": len(shared_keys),
        "target_exclusive_signature_count": len(target_exclusive_keys),
        "guard_exclusive_signature_count": len(guard_exclusive_keys),
        "shared_guard_labels": shared_guard_labels,
        "guard_labels_without_observation": guard_labels_without_observation,
        "target_labels_without_observation": target_labels_without_observation,
        "shared_signatures": [target_union[key] for key in shared_keys],
        "target_exclusive_signatures": [target_union[key] for key in target_exclusive_keys],
        "guard_exclusive_signatures": [guard_union[key] for key in guard_exclusive_keys],
        "promotion_status": promotion_status,
        "recommendation": recommendation,
    }


def render_markdown(review: dict):
    lines = [
        "# Sampled Cross-Scene Review",
        "",
        f"- Target labels: `{', '.join(review.get('target_labels') or []) or 'none'}`",
        f"- Guard labels: `{', '.join(review.get('guard_labels') or []) or 'none'}`",
        f"- Family count: `{len(review.get('families') or [])}`",
        "",
    ]
    for family in review.get("families") or []:
        lines.extend(
            [
                f"## `{family['sampled_low32']}`",
                "",
                f"- promotion_status: `{family['promotion_status']}`",
                f"- recommendation: `{family['recommendation']}`",
                f"- target signatures: `{family['target_signature_count']}`",
                f"- guard signatures: `{family['guard_signature_count']}`",
                f"- shared signatures: `{family['shared_signature_count']}`",
                f"- target-exclusive signatures: `{family['target_exclusive_signature_count']}`",
                f"- shared guard labels: `{', '.join(family.get('shared_guard_labels') or []) or 'none'}`",
                f"- guard labels without observation: `{', '.join(family.get('guard_labels_without_observation') or []) or 'none'}`",
                "",
                "### Labels",
                "",
            ]
        )
        for label in family.get("labels") or []:
            lines.append(
                f"- `{label['label']}` signatures `{label['signature_count']}` "
                f"(groups `{label['group_signature_count']}`, buckets `{label['bucket_signature_count']}`, logs `{label['log_signature_count']}`) "
                f"family-buckets `{label['family_bucket_count_observed']}` "
                f"exact-hits `{label['exact_hit_bucket_count_observed']}` "
                f"exact-unresolved `{label['exact_unresolved_bucket_count_observed']}`"
            )
        if family.get("shared_signatures"):
            lines.extend(["", "### Shared Signatures", ""])
            for signature in family["shared_signatures"]:
                lines.append(
                    f"- draw `{signature['draw_class']}` cycle `{signature['cycle']}` tile `{signature['tile']}` "
                    f"fmt/siz `{signature['fmt']}/{signature['siz']}` off `{signature['off']}` stride `{signature['stride']}` "
                    f"wh `{signature['wh']}` upload `{signature['upload_low32']}` fs `{signature['fs']}`"
                )
        if family.get("target_exclusive_signatures"):
            lines.extend(["", "### Target-Exclusive Signatures", ""])
            for signature in family["target_exclusive_signatures"]:
                lines.append(
                    f"- draw `{signature['draw_class']}` cycle `{signature['cycle']}` tile `{signature['tile']}` "
                    f"fmt/siz `{signature['fmt']}/{signature['siz']}` off `{signature['off']}` stride `{signature['stride']}` "
                    f"wh `{signature['wh']}` upload `{signature['upload_low32']}` fs `{signature['fs']}`"
                )
        lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Compare sampled-object family signatures across scenes before promotion.")
    parser.add_argument("--evidence", action="append", required=True, help="LABEL=path/to/hires-evidence.json. Pass multiple times.")
    parser.add_argument("--sampled-low32", action="append", required=True, help="Family sampled_low32 to review. Pass multiple times.")
    parser.add_argument("--target-label", action="append", required=True, help="Target scene label. Pass multiple times.")
    parser.add_argument("--guard-label", action="append", required=True, help="Guard scene label. Pass multiple times.")
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--output-markdown", required=True)
    args = parser.parse_args()

    labeled_paths = [parse_labeled_path(value) for value in args.evidence]
    label_seen = set()
    for label, _ in labeled_paths:
        if label in label_seen:
            raise SystemExit(f"duplicate --evidence label {label!r}")
        label_seen.add(label)

    families = []
    for sampled_low32 in args.sampled_low32:
        normalized = sampled_low32.lower()
        records = [
            collect_label_family(label, path, normalized)
            for label, path in labeled_paths
        ]
        families.append(
            classify_family(normalized, records, list(args.target_label), list(args.guard_label))
        )

    review = {
        "target_labels": list(args.target_label),
        "guard_labels": list(args.guard_label),
        "families": families,
    }

    output_json = Path(args.output_json)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(review, indent=2) + "\n")

    output_markdown = Path(args.output_markdown)
    output_markdown.parent.mkdir(parents=True, exist_ok=True)
    output_markdown.write_text(render_markdown(review))


if __name__ == "__main__":
    main()
