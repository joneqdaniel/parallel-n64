#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path

RUNTIME_FAMILY_PREFIX = "Hi-res sampled-object family: "
RUNTIME_FIELD_RE = re.compile(r"([a-z_][a-z0-9_]*)=([^ ]+)")


def load_probe(bundle: Path):
    data = json.loads((bundle / "traces" / "hires-evidence.json").read_text())
    return data.get("sampled_object_probe", {})


def load_loader_records(loader_manifest: Path):
    data = json.loads(loader_manifest.read_text())
    if isinstance(data, dict):
        return data.get("records", [])
    if isinstance(data, list):
        return data
    raise SystemExit(f"unsupported loader manifest format: {loader_manifest}")


def load_transport_groups(transport_review: Path):
    data = json.loads(transport_review.read_text())
    if isinstance(data, dict):
        return data.get("groups", [])
    if isinstance(data, list):
        return data
    raise SystemExit(f"unsupported transport review format: {transport_review}")


def bucket_fields(item):
    return item.get("fields", {})


def parse_runtime_family_items(log_path: Path):
    grouped = {}
    for line in log_path.read_text(errors="replace").splitlines():
        marker = line.find(RUNTIME_FAMILY_PREFIX)
        if marker < 0:
            continue
        body = line[marker + len(RUNTIME_FAMILY_PREFIX):].strip()
        if body.endswith("."):
            body = body[:-1]
        fields = dict(RUNTIME_FIELD_RE.findall(body))
        if not fields:
            continue
        signature = tuple((key, fields[key]) for key in sorted(fields))
        item = grouped.setdefault(signature, {
            "count": 0,
            "fields": fields,
            "sample_detail": body,
        })
        item["count"] += 1
    items = list(grouped.values())
    items.sort(key=lambda item: (-item["count"], item.get("fields", {}).get("sampled_low32", ""), item.get("fields", {}).get("fs", "")))
    return items


def load_runtime_family_items(bundle: Path, probe: dict):
    log_path = bundle / "logs" / "retroarch.log"
    if log_path.is_file():
        items = parse_runtime_family_items(log_path)
        if items:
            return items
    return probe.get("top_exact_family_buckets", [])


def group_unresolved(buckets):
    grouped = {}
    for item in buckets:
        fields = bucket_fields(item)
        key = (
            fields.get("draw_class"),
            fields.get("cycle"),
            fields.get("sampled_low32"),
            fields.get("fs"),
            fields.get("wh"),
        )
        group = grouped.setdefault(key, {
            "count": 0,
            "selectors": [],
            "palette_crcs": set(),
            "sample_detail": item.get("sample_detail"),
        })
        group["count"] += item.get("count", 0)
        selector = fields.get("selector")
        if selector is not None:
            group["selectors"].append({"selector": selector, "count": item.get("count", 0)})
        palette_crc = fields.get("palette_crc")
        if palette_crc is not None:
            group["palette_crcs"].add(palette_crc)
    rows = []
    for key, group in grouped.items():
        selectors = {}
        for sel in group["selectors"]:
            selectors[sel["selector"]] = selectors.get(sel["selector"], 0) + sel["count"]
        rows.append({
            "draw_class": key[0],
            "cycle": key[1],
            "sampled_low32": key[2],
            "fs": key[3],
            "wh": key[4],
            "count": group["count"],
            "palette_crcs": sorted(group["palette_crcs"]),
            "selectors": [
                {"selector": selector, "count": count}
                for selector, count in sorted(selectors.items(), key=lambda item: (-item[1], item[0]))
            ],
            "sample_detail": group["sample_detail"],
        })
    rows.sort(key=lambda row: (-row["count"], row["sampled_low32"] or "", row["cycle"] or ""))
    return rows


def build_loader_index(records):
    index = {}
    for record in records:
        canonical_identity = record.get("canonical_identity") or {}
        key = (
            canonical_identity.get("sampled_low32"),
            str(canonical_identity.get("formatsize")),
        )
        index.setdefault(key, []).append(record)
    return index


def build_transport_index(groups):
    index = {}
    for group in groups:
        signature = group.get("signature") or {}
        key = (
            signature.get("draw_class"),
            signature.get("cycle"),
            signature.get("sampled_low32"),
            str(signature.get("formatsize")),
        )
        index.setdefault(key, []).append(group)
    return index


def build_runtime_family_index(source):
    if isinstance(source, dict):
        items = source.get("top_exact_family_buckets", [])
    else:
        items = source or []
    index = {}
    for item in items:
        fields = item.get("fields", {})
        key = (
            fields.get("sampled_low32"),
            fields.get("fs"),
        )
        index.setdefault(key, []).append(item)
    return index


def build_package_annotation(row, loader_index):
    key = (row.get("sampled_low32"), row.get("fs"))
    records = loader_index.get(key, [])
    if not records:
        return {
            "package_status": "absent-from-package",
            "matching_record_count": 0,
            "matching_policy_keys": [],
            "matching_asset_candidate_count": 0,
            "matching_asset_selector_count": 0,
            "matching_candidate_selectors": [],
            "matching_sampled_object_ids": [],
        }

    matching_shape = []
    matching_palette = []
    matching_selector = []
    row_palettes = set(row.get("palette_crcs") or [])
    row_selectors = {item.get("selector") for item in row.get("selectors", []) if item.get("selector")}

    for record in records:
        canonical_identity = record.get("canonical_identity") or {}
        row_draw_class = row.get("draw_class")
        row_cycle = row.get("cycle")
        row_wh = row.get("wh")
        if row_draw_class and canonical_identity.get("draw_class") != row_draw_class:
            continue
        if row_cycle and canonical_identity.get("cycle") != row_cycle:
            continue
        if row_wh and canonical_identity.get("wh") != row_wh:
            continue
        matching_shape.append(record)

        entry_pcrc = canonical_identity.get("sampled_entry_pcrc")
        sparse_pcrc = canonical_identity.get("sampled_sparse_pcrc")
        if not row_palettes or entry_pcrc in row_palettes or sparse_pcrc in row_palettes:
            matching_palette.append(record)

            selectors = {
                candidate.get("selector_checksum64")
                for candidate in (record.get("asset_candidates") or [])
                if candidate.get("selector_checksum64")
            }
            if row_selectors & selectors:
                matching_selector.append(record)

    if not matching_shape:
        status = "present-different-shape"
        matching = records
    elif not matching_palette:
        status = "present-different-palette"
        matching = matching_shape
    elif not matching_selector:
        candidate_count = sum(len(record.get("asset_candidates") or []) for record in matching_palette)
        status = "present-pool-selector-conflict" if candidate_count > 1 else "present-selector-conflict"
        matching = matching_palette
    else:
        status = "present-selector-aligned"
        matching = matching_selector

    policy_keys = []
    sampled_object_ids = []
    candidate_selectors = []
    asset_candidate_count = 0
    for record in matching:
        policy_key = record.get("policy_key")
        if policy_key and policy_key not in policy_keys:
            policy_keys.append(policy_key)
        sampled_object_id = record.get("sampled_object_id")
        if sampled_object_id and sampled_object_id not in sampled_object_ids:
            sampled_object_ids.append(sampled_object_id)
        for candidate in record.get("asset_candidates") or []:
            asset_candidate_count += 1
            selector = candidate.get("selector_checksum64")
            if selector and selector not in candidate_selectors:
                candidate_selectors.append(selector)

    return {
        "package_status": status,
        "matching_record_count": len(matching),
        "matching_policy_keys": policy_keys[:8],
        "matching_asset_candidate_count": asset_candidate_count,
        "matching_asset_selector_count": len(candidate_selectors),
        "matching_candidate_selectors": candidate_selectors[:8],
        "matching_sampled_object_ids": sampled_object_ids[:4],
    }


def build_transport_annotation(row, transport_index):
    key = (
        row.get("draw_class"),
        row.get("cycle"),
        row.get("sampled_low32"),
        row.get("fs"),
    )
    groups = transport_index.get(key, [])
    if not groups:
        return {
            "transport_status": "legacy-transport-review-missing",
            "matching_transport_group_count": 0,
            "matching_transport_candidate_count": 0,
            "matching_transport_probe_event_count": 0,
        }

    candidate_count = sum(int(group.get("unique_transport_candidate_count") or 0) for group in groups)
    probe_event_count = sum(int(group.get("probe_event_count") or 0) for group in groups)
    status = "legacy-transport-candidates-available" if candidate_count > 0 else "legacy-transport-candidate-free"
    return {
        "transport_status": status,
        "matching_transport_group_count": len(groups),
        "matching_transport_candidate_count": candidate_count,
        "matching_transport_probe_event_count": probe_event_count,
    }


def build_runtime_family_annotation(row, runtime_family_index):
    key = (row.get("sampled_low32"), row.get("fs"))
    families = runtime_family_index.get(key, [])
    if not families:
        return {
            "runtime_family_status": "runtime-family-unreported",
            "matching_runtime_family_count": 0,
        }

    row_palettes = set(row.get("palette_crcs") or [])
    row_selectors = {item.get("selector") for item in row.get("selectors", []) if item.get("selector")}
    matching = []
    for item in families:
        fields = item.get("fields", {})
        palette_crc = fields.get("palette_crc")
        selector = fields.get("selector")
        if row_palettes and palette_crc is not None and palette_crc not in row_palettes:
            continue
        if row_selectors and selector is not None and selector not in row_selectors:
            continue
        matching.append(item)

    if not matching:
        return {
            "runtime_family_status": "runtime-family-unmatched",
            "matching_runtime_family_count": 0,
        }

    def classify(fields):
        if fields.get("available") != "1":
            return "runtime-family-missing"
        if fields.get("active_is_pool") == "1":
            return "runtime-pool-family"
        if int(fields.get("matching_selectors") or 0) > 0:
            return "runtime-selector-aligned"
        return "runtime-selector-conflict"

    statuses = []
    sample_policy = None
    sample_replacement_id = None
    sample_object = None
    sample_fields = None
    for item in matching:
        fields = item.get("fields", {})
        status = classify(fields)
        if status not in statuses:
            statuses.append(status)
        if sample_policy is None and fields.get("sample_policy"):
            sample_policy = fields.get("sample_policy")
        if sample_replacement_id is None and fields.get("sample_replacement_id"):
            sample_replacement_id = fields.get("sample_replacement_id")
        if sample_object is None and fields.get("sampled_object"):
            sample_object = fields.get("sampled_object")
        if sample_fields is None:
            sample_fields = fields

    result = {
        "runtime_family_status": statuses[0],
        "runtime_family_statuses": statuses,
        "matching_runtime_family_count": len(matching),
        "runtime_sample_policy": sample_policy,
        "runtime_sample_replacement_id": sample_replacement_id,
        "runtime_sampled_object": sample_object,
    }
    if sample_fields is not None:
        result.update({
            "runtime_active_entry_count": int(sample_fields.get("active_entries") or 0),
            "runtime_unique_selector_count": int(sample_fields.get("unique_selectors") or 0),
            "runtime_matching_selector_count": int(sample_fields.get("matching_selectors") or 0),
            "runtime_ordered_selector_count": int(sample_fields.get("ordered_selectors") or 0),
            "runtime_active_is_pool": sample_fields.get("active_is_pool") == "1",
            "runtime_sample_repl": sample_fields.get("sample_repl"),
        })
    return result


def build_pool_annotation(row, package_annotation, runtime_annotation):
    package_status = package_annotation.get("package_status")
    runtime_status = runtime_annotation.get("runtime_family_status")
    is_package_pool = package_status == "present-pool-selector-conflict"
    is_runtime_pool = runtime_status == "runtime-pool-family"
    if not is_package_pool and not is_runtime_pool:
        return {}

    runtime_selector_count = len(row.get("selectors") or [])
    matching_runtime_selector_count = int(runtime_annotation.get("runtime_matching_selector_count") or 0)
    candidate_count = int(package_annotation.get("matching_asset_candidate_count") or 0)

    if is_package_pool and is_runtime_pool and candidate_count > 1 and matching_runtime_selector_count == 0:
        recommendation = "defer-runtime-pool-semantics"
    elif matching_runtime_selector_count > 0:
        recommendation = "candidate-runtime-pool-alignment"
    elif is_runtime_pool:
        recommendation = "inspect-runtime-pool-semantics"
    else:
        recommendation = "inspect-package-pool-conflict"

    return {
        "pool_recommendation": recommendation,
        "pool_package_status": package_status,
        "pool_runtime_status": runtime_status,
        "pool_runtime_selector_count": runtime_selector_count,
        "pool_matching_runtime_selector_count": matching_runtime_selector_count,
        "pool_manifest_candidate_count": candidate_count,
    }


def annotate_rows(rows, loader_index, transport_index=None, runtime_family_index=None):
    annotated = []
    for row in rows:
        annotated_row = dict(row)
        package_annotation = build_package_annotation(row, loader_index or {})
        transport_annotation = build_transport_annotation(row, transport_index or {})
        runtime_annotation = build_runtime_family_annotation(row, runtime_family_index or {})
        annotated_row.update(package_annotation)
        annotated_row.update(transport_annotation)
        annotated_row.update(runtime_annotation)
        annotated_row.update(build_pool_annotation(row, package_annotation, runtime_annotation))
        annotated.append(annotated_row)
    return annotated


def build_review(bundle: Path, probe: dict, loader_index=None, transport_index=None, runtime_family_index=None):
    unresolved = annotate_rows(group_unresolved(probe.get('top_exact_unresolved_miss_buckets', [])), loader_index or {}, transport_index or {}, runtime_family_index or {})
    conflicts = annotate_rows(group_unresolved(probe.get('top_exact_conflict_miss_buckets', [])), loader_index or {}, transport_index or {}, runtime_family_index or {})
    pool_families = [row for row in unresolved + conflicts if row.get("pool_recommendation")]
    pool_families.sort(key=lambda row: (-row.get("count", 0), row.get("sampled_low32") or "", row.get("cycle") or ""))
    return {
        "bundle": str(bundle),
        "exact_hit_count": probe.get('exact_hit_count', 0),
        "exact_miss_count": probe.get('exact_miss_count', 0),
        "exact_conflict_miss_count": probe.get('exact_conflict_miss_count', 0),
        "exact_unresolved_miss_count": probe.get('exact_unresolved_miss_count', 0),
        "unresolved": unresolved,
        "conflicts": conflicts,
        "pool_families": pool_families,
    }


def render_markdown(review: dict) -> str:
    lines = []
    lines.append(f"# Sampled Selector Review\n")
    lines.append(f"- Bundle: `{review['bundle']}`")
    lines.append(f"- Exact hits: `{review['exact_hit_count']}`")
    lines.append(f"- Exact misses: `{review['exact_miss_count']}`")
    lines.append(f"- Conflict misses: `{review['exact_conflict_miss_count']}`")
    lines.append(f"- Unresolved misses: `{review['exact_unresolved_miss_count']}`\n")

    lines.append('## Unresolved')
    if not review["unresolved"]:
        lines.append('- None')
    else:
        for row in review["unresolved"]:
            lines.append(f"- `{row['sampled_low32']}` `{row['draw_class']}` `{row['cycle']}` `fs={row['fs']}` count `{row['count']}` palettes `{', '.join(row['palette_crcs']) or 'none'}`")
            if row.get("package_status"):
                lines.append(f"  package `{row['package_status']}` matches `{row.get('matching_record_count', 0)}`")
            if row.get("transport_status"):
                lines.append(
                    f"  transport `{row['transport_status']}` groups `{row.get('matching_transport_group_count', 0)}` "
                    f"candidates `{row.get('matching_transport_candidate_count', 0)}` probe_events `{row.get('matching_transport_probe_event_count', 0)}`"
                )
            if row.get("runtime_family_status"):
                lines.append(
                    f"  runtime `{row['runtime_family_status']}` families `{row.get('matching_runtime_family_count', 0)}`"
                )
            if row.get("runtime_sample_policy"):
                lines.append(f"  runtime-policy `{row['runtime_sample_policy']}`")
            if row.get("runtime_sample_replacement_id"):
                lines.append(f"  runtime-replacement `{row['runtime_sample_replacement_id']}`")
            for policy_key in row.get("matching_policy_keys", [])[:4]:
                lines.append(f"  policy `{policy_key}`")
            for selector in row['selectors'][:8]:
                lines.append(f"  selector `{selector['selector']}` count `{selector['count']}`")

    lines.append('\n## Conflicts')
    if not review["conflicts"]:
        lines.append('- None')
    else:
        for row in review["conflicts"]:
            lines.append(f"- `{row['sampled_low32']}` `{row['draw_class']}` `{row['cycle']}` `fs={row['fs']}` count `{row['count']}` palettes `{', '.join(row['palette_crcs']) or 'none'}`")
            if row.get("package_status"):
                lines.append(f"  package `{row['package_status']}` matches `{row.get('matching_record_count', 0)}`")
            if row.get("transport_status"):
                lines.append(
                    f"  transport `{row['transport_status']}` groups `{row.get('matching_transport_group_count', 0)}` "
                    f"candidates `{row.get('matching_transport_candidate_count', 0)}` probe_events `{row.get('matching_transport_probe_event_count', 0)}`"
                )
            if row.get("runtime_family_status"):
                lines.append(
                    f"  runtime `{row['runtime_family_status']}` families `{row.get('matching_runtime_family_count', 0)}`"
                )
            if row.get("runtime_sample_policy"):
                lines.append(f"  runtime-policy `{row['runtime_sample_policy']}`")
            if row.get("runtime_sample_replacement_id"):
                lines.append(f"  runtime-replacement `{row['runtime_sample_replacement_id']}`")
            for policy_key in row.get("matching_policy_keys", [])[:4]:
                lines.append(f"  policy `{policy_key}`")
            for selector in row['selectors'][:8]:
                lines.append(f"  selector `{selector['selector']}` count `{selector['count']}`")

    lines.append('\n## Pool Families')
    if not review["pool_families"]:
        lines.append('- None')
    else:
        for row in review["pool_families"]:
            lines.append(
                f"- `{row['sampled_low32']}` `{row['draw_class']}` `{row['cycle']}` `fs={row['fs']}` "
                f"count `{row['count']}` recommendation `{row['pool_recommendation']}`"
            )
            lines.append(
                f"  package `{row.get('pool_package_status', 'none')}` candidates `{row.get('pool_manifest_candidate_count', 0)}` "
                f"selectors `{row.get('matching_asset_selector_count', 0)}`"
            )
            lines.append(
                f"  runtime `{row.get('pool_runtime_status', 'none')}` families `{row.get('matching_runtime_family_count', 0)}` "
                f"active_entries `{row.get('runtime_active_entry_count', 0)}` unique_selectors `{row.get('runtime_unique_selector_count', 0)}` "
                f"matching_selectors `{row.get('pool_matching_runtime_selector_count', 0)}`"
            )
            if row.get("runtime_sample_policy"):
                lines.append(f"  runtime-policy `{row['runtime_sample_policy']}`")
            if row.get("runtime_sample_replacement_id"):
                lines.append(f"  runtime-replacement `{row['runtime_sample_replacement_id']}`")
            if row.get("runtime_sampled_object"):
                lines.append(f"  runtime-object `{row['runtime_sampled_object']}`")
            for sampled_object_id in row.get("matching_sampled_object_ids", [])[:4]:
                lines.append(f"  sampled-object `{sampled_object_id}`")
            for selector in row.get("selectors", [])[:8]:
                lines.append(f"  runtime selector `{selector['selector']}` count `{selector['count']}`")
            for selector in row.get("matching_candidate_selectors", [])[:8]:
                lines.append(f"  candidate selector `{selector}`")

    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle-dir', required=True)
    parser.add_argument('--loader-manifest', help='Optional loader-manifest.json to classify families against the active PHRB package.')
    parser.add_argument('--transport-review', help='Optional sampled transport review JSON to classify whether legacy candidates exist for each family.')
    parser.add_argument('--output', required=True)
    parser.add_argument('--output-json', help='Optional structured review JSON output.')
    args = parser.parse_args()

    bundle = Path(args.bundle_dir)
    probe = load_probe(bundle)
    loader_index = {}
    transport_index = {}
    runtime_family_index = build_runtime_family_index(load_runtime_family_items(bundle, probe))
    if args.loader_manifest:
        loader_index = build_loader_index(load_loader_records(Path(args.loader_manifest)))
    if args.transport_review:
        transport_index = build_transport_index(load_transport_groups(Path(args.transport_review)))
    review = build_review(bundle, probe, loader_index, transport_index, runtime_family_index)
    Path(args.output).write_text(render_markdown(review))
    if args.output_json:
        Path(args.output_json).write_text(json.dumps(review, indent=2, sort_keys=True) + "\n")


if __name__ == '__main__':
    main()
