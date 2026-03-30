#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

from hires_pack_common import parse_cache_entries


def load_json(path: Path):
    return json.loads(path.read_text())


def make_replacement_id(texture_crc, palette_crc, formatsize, width, height):
    return f"legacy-{texture_crc:08x}-{palette_crc:08x}-fs{formatsize}-{width}x{height}"


def load_cache_index(cache_path: Path):
    index = {}
    for entry in parse_cache_entries(cache_path):
        replacement_id = make_replacement_id(
            entry["texture_crc"],
            entry["palette_crc"],
            entry["formatsize"],
            entry["width"],
            entry["height"],
        )
        index[replacement_id] = entry
    return index


def build_transport_candidate(entry, selector_checksum64, variant_group_suffix):
    return {
        "replacement_id": make_replacement_id(
            entry["texture_crc"],
            entry["palette_crc"],
            entry["formatsize"],
            entry["width"],
            entry["height"],
        ),
        "source": {
            "legacy_checksum64": f"{entry['checksum64']:016x}",
            "legacy_texture_crc": f"{entry['texture_crc']:08x}",
            "legacy_palette_crc": f"{entry['palette_crc']:08x}",
            "legacy_formatsize": entry["formatsize"],
            "legacy_storage": entry["storage"],
            "legacy_source_path": entry["source_path"],
        },
        "match": {
            "exact_legacy_checksum64": f"{entry['checksum64']:016x}",
            "texture_crc": f"{entry['texture_crc']:08x}",
            "palette_crc": f"{entry['palette_crc']:08x}",
            "formatsize": entry["formatsize"],
        },
        "replacement_asset": {
            "width": entry["width"],
            "height": entry["height"],
            "format": entry["format"],
            "texture_format": entry["texture_format"],
            "pixel_type": entry["pixel_type"],
            "data_size": entry["data_size"],
            "is_hires": entry["is_hires"],
        },
        "selector_checksum64": selector_checksum64,
        "variant_group_id": (
            f"transport-bridge-{entry['texture_crc']:08x}-{entry['palette_crc']:08x}-"
            f"fs{entry['formatsize']}-{entry['width']}x{entry['height']}-{variant_group_suffix}"
        ),
    }


def build_bridge_binding(policy_key, record, cache_index):
    selected_replacement_id = record.get("selected_replacement_id")
    if not selected_replacement_id:
        raise SystemExit(f"transport bridge {policy_key} is missing selected_replacement_id")

    entry = cache_index.get(selected_replacement_id)
    if not entry:
        raise SystemExit(
            f"transport bridge {policy_key} selected_replacement_id {selected_replacement_id} "
            "was not found in the supplied cache"
        )

    canonical_identity = dict(record.get("canonical_identity") or {})
    if not canonical_identity:
        raise SystemExit(f"transport bridge {policy_key} is missing canonical_identity")

    selector_checksum64s = list(record.get("selector_checksum64s") or [])
    include_zero_selector = bool(record.get("include_zero_selector", False))
    transport_candidates = []
    if include_zero_selector:
        transport_candidates.append(
            build_transport_candidate(entry, "0000000000000000", "sel-0000000000000000")
        )
    for selector_checksum64 in selector_checksum64s:
        transport_candidates.append(
            build_transport_candidate(entry, selector_checksum64, f"sel-{selector_checksum64}")
        )

    if not transport_candidates:
        raise SystemExit(f"transport bridge {policy_key} emitted no transport candidates")

    return {
        "policy_key": policy_key,
        "family_type": "synthetic-transport-bridge",
        "status": record.get("status") or "selected-provisional",
        "selection_reason": record.get("justification") or "synthetic-transport-bridge",
        "sampled_object_id": record.get("sampled_object_id") or policy_key,
        "canonical_identity": canonical_identity,
        "upload_low32s": [{"value": value} for value in record.get("upload_low32s", [])],
        "upload_pcrcs": [{"value": value} for value in record.get("upload_pcrcs", [])],
        "transport_candidates": transport_candidates,
        "transport_policy": {
            "selected_replacement_id": selected_replacement_id,
            "selector_checksum64s": selector_checksum64s,
            "include_zero_selector": include_zero_selector,
            "bridge_kind": record.get("bridge_kind"),
            "reinterpretation": record.get("reinterpretation"),
            "source_probe_bundle": record.get("source_probe_bundle"),
            "status": record.get("status"),
            "justification": record.get("justification"),
            "supporting_notes": record.get("supporting_notes", []),
            "overturn_conditions": record.get("overturn_conditions", []),
        },
    }


def build_transport_bridge_bindings(policy_data, cache_path: Path, selected_keys=None):
    selected_keys = list(selected_keys or [])
    bridge_policy = policy_data.get("transport_synthetic_bridges", {}) if policy_data else {}
    if selected_keys:
        unknown = [key for key in selected_keys if key not in bridge_policy]
        if unknown:
            raise SystemExit(f"unknown transport bridge policy keys: {unknown}")
        bridge_keys = selected_keys
    else:
        bridge_keys = sorted(
            key for key, record in bridge_policy.items()
            if record.get("status", "").startswith("selected")
        )

    cache_index = load_cache_index(cache_path)
    bindings = [build_bridge_binding(policy_key, bridge_policy[policy_key], cache_index) for policy_key in bridge_keys]
    return {
        "schema_version": 1,
        "source_input_path": str(cache_path),
        "binding_count": len(bindings),
        "unresolved_count": 0,
        "bindings": bindings,
        "unresolved_transport_cases": [],
    }


def main():
    parser = argparse.ArgumentParser(description="Emit policy-backed synthetic transport bridge bindings.")
    parser.add_argument("--policy", required=True, help="Transport policy JSON path.")
    parser.add_argument("--cache", required=True, help="Legacy .hts/.htc cache path used to source replacement candidates.")
    parser.add_argument("--bridge-key", action="append", help="Specific transport_synthetic_bridges policy key to emit. Pass multiple times.")
    parser.add_argument("--output", help="Optional output JSON path.")
    args = parser.parse_args()

    result = build_transport_bridge_bindings(
        load_json(Path(args.policy)),
        Path(args.cache),
        args.bridge_key,
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
