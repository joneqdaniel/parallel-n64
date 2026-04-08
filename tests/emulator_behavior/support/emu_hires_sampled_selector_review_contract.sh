#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"

python3 - "$REPO_ROOT/tools/hires_sampled_selector_review.py" <<'PY'
import importlib.util
import sys
import tempfile
from pathlib import Path

module_path = Path(sys.argv[1])
sys.path.insert(0, str(module_path.parent))
spec = importlib.util.spec_from_file_location("hires_sampled_selector_review", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def check(condition, message):
    if not condition:
        raise SystemExit(message)


base_record = {
    "policy_key": "sampled-low32-28916d63-fs258",
    "canonical_identity": {
        "draw_class": "texrect",
        "cycle": "copy",
        "wh": "296x6",
        "formatsize": 258,
        "sampled_low32": "28916d63",
        "sampled_entry_pcrc": "8be3a754",
        "sampled_sparse_pcrc": "0574791d",
    },
    "asset_candidates": [
        {"selector_checksum64": "5c66840b2eb5c22e"},
    ],
}

pool_record = {
    "policy_key": "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb-pool",
    "sampled_object_id": "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb",
    "canonical_identity": {
        "draw_class": "texrect",
        "cycle": "copy",
        "wh": "296x6",
        "formatsize": 258,
        "sampled_low32": "1b8530fb",
        "sampled_entry_pcrc": "98bb9d8e",
        "sampled_sparse_pcrc": "52e0d253",
    },
    "asset_candidates": [
        {"selector_checksum64": "9afc43ab038a968c"},
        {"selector_checksum64": "9ae3ba300ea068fb"},
        {"selector_checksum64": "19dd4a230f9b01d4"},
    ],
}

transport_group = {
    "signature": {
        "draw_class": "texrect",
        "cycle": "copy",
        "sampled_low32": "28916d63",
        "formatsize": 258,
    },
    "probe_event_count": 29,
    "unique_transport_candidate_count": 29,
}

probe = {
    "top_exact_family_buckets": [
        {
            "fields": {
                "available": "1",
                "sampled_low32": "28916d63",
                "palette_crc": "0574791d",
                "fs": "258",
                "selector": "0574791d28916d63",
                "active_is_pool": "0",
                "matching_selectors": "0",
                "sample_policy": "sampled-low32-28916d63-fs258",
                "sample_replacement_id": "legacy-28916d63-a",
                "sampled_object": "sampled-low3228916d63-fs258",
            }
        },
        {
            "fields": {
                "available": "1",
                "sampled_low32": "1b8530fb",
                "palette_crc": "52e0d253",
                "fs": "258",
                "selector": "52e0d2531b8530fb",
                "active_is_pool": "1",
                "matching_selectors": "0",
                "sample_policy": "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb-pool",
                "sample_replacement_id": "legacy-1b8530fb-a",
                "sampled_object": "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb",
            }
        },
    ]
}

row = {
    "draw_class": "texrect",
    "cycle": "copy",
    "sampled_low32": "28916d63",
    "fs": "258",
    "wh": "296x6",
    "count": 33,
    "palette_crcs": ["0574791d", "8be3a754"],
    "selectors": [{"selector": "0574791d28916d63", "count": 33}],
}

absent = module.annotate_rows([row], {})[0]
check(absent["package_status"] == "absent-from-package", f"unexpected absent classification: {absent}")
check(absent["transport_status"] == "legacy-transport-review-missing", f"unexpected missing transport classification: {absent}")

transport_index = module.build_transport_index([transport_group])
runtime_family_index = module.build_runtime_family_index(probe)
transport_absent = module.annotate_rows([row], {}, transport_index, runtime_family_index)[0]
check(transport_absent["transport_status"] == "legacy-transport-candidates-available", f"unexpected transport classification: {transport_absent}")
check(transport_absent["matching_transport_candidate_count"] == 29, f"unexpected transport candidate count: {transport_absent}")
check(transport_absent["runtime_family_status"] == "runtime-selector-conflict", f"unexpected runtime family classification: {transport_absent}")
check(transport_absent["runtime_sample_policy"] == "sampled-low32-28916d63-fs258", f"unexpected runtime family policy: {transport_absent}")

loader_index = module.build_loader_index([base_record])
conflict = module.annotate_rows([row], loader_index, transport_index, runtime_family_index)[0]
check(conflict["package_status"] == "present-selector-conflict", f"unexpected conflict classification: {conflict}")
check(conflict["matching_policy_keys"] == ["sampled-low32-28916d63-fs258"], f"unexpected policy keys: {conflict}")
check(conflict["matching_asset_candidate_count"] == 1, f"unexpected conflict candidate count: {conflict}")
check(conflict["transport_status"] == "legacy-transport-candidates-available", f"unexpected conflict transport classification: {conflict}")

aligned_row = dict(row)
aligned_row["selectors"] = [{"selector": "5c66840b2eb5c22e", "count": 33}]
aligned = module.annotate_rows([aligned_row], loader_index, transport_index, runtime_family_index)[0]
check(aligned["package_status"] == "present-selector-aligned", f"unexpected aligned classification: {aligned}")

shape_row = dict(row)
shape_row["wh"] = "296x2"
different_shape = module.annotate_rows([shape_row], loader_index, transport_index, runtime_family_index)[0]
check(different_shape["package_status"] == "present-different-shape", f"unexpected shape classification: {different_shape}")

candidate_free_index = module.build_transport_index([
    {
        "signature": {
            "draw_class": "triangle",
            "cycle": "2cycle",
            "sampled_low32": "91887078",
            "formatsize": 4,
        },
        "probe_event_count": 1,
        "unique_transport_candidate_count": 0,
    }
])
candidate_free_row = {
    "draw_class": "triangle",
    "cycle": "2cycle",
    "sampled_low32": "91887078",
    "fs": "4",
    "wh": None,
    "count": 1,
    "palette_crcs": ["00000000"],
    "selectors": [{"selector": "00000000de3dac2a", "count": 1}],
}
pool_probe = {
    "top_exact_family_buckets": [
        {
            "fields": {
                "available": "1",
                "sampled_low32": "1b8530fb",
                "palette_crc": "52e0d253",
                "fs": "258",
                "selector": "52e0d2531b8530fb",
                "active_is_pool": "1",
                "matching_selectors": "0",
                "sample_policy": "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb-pool",
                "sample_replacement_id": "legacy-1b8530fb-a",
                "sampled_object": "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb",
            }
        }
    ]
}
pool_runtime_index = module.build_runtime_family_index(pool_probe)
candidate_free = module.annotate_rows([candidate_free_row], {}, candidate_free_index, pool_runtime_index)[0]
check(candidate_free["transport_status"] == "legacy-transport-candidate-free", f"unexpected candidate-free classification: {candidate_free}")

pool_row = {
    "draw_class": "texrect",
    "cycle": "copy",
    "sampled_low32": "1b8530fb",
    "fs": "258",
    "wh": "296x6",
    "count": 2112,
    "palette_crcs": ["52e0d253", "98bb9d8e"],
    "selectors": [{"selector": "52e0d2531b8530fb", "count": 2112}],
}
pool_transport_index = module.build_transport_index([
    {
        "signature": {
            "draw_class": "texrect",
            "cycle": "copy",
            "sampled_low32": "1b8530fb",
            "formatsize": 258,
        },
        "probe_event_count": 1,
        "unique_transport_candidate_count": 33,
    }
])
pool_loader_index = module.build_loader_index([pool_record])
pool = module.annotate_rows([pool_row], loader_index=pool_loader_index, transport_index=pool_transport_index, runtime_family_index=pool_runtime_index)[0]
check(pool["package_status"] == "present-pool-selector-conflict", f"unexpected pool package classification: {pool}")
check(pool["runtime_family_status"] == "runtime-pool-family", f"unexpected runtime pool classification: {pool}")
check(pool["transport_status"] == "legacy-transport-candidates-available", f"unexpected pool transport classification: {pool}")
check(pool["matching_asset_candidate_count"] == 3, f"unexpected pool candidate count: {pool}")
check(pool["pool_recommendation"] == "defer-runtime-pool-semantics", f"unexpected pool recommendation: {pool}")
check(pool["matching_sampled_object_ids"] == ["sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb"], f"unexpected pool object ids: {pool}")
check(pool["runtime_sample_replacement_id"] == "legacy-1b8530fb-a", f"unexpected pool runtime replacement id: {pool}")

with tempfile.TemporaryDirectory() as tmpdir:
    bundle = Path(tmpdir)
    logs_dir = bundle / "logs"
    logs_dir.mkdir(parents=True)
    (logs_dir / "retroarch.log").write_text(
        "Hi-res sampled-object family: available=1 draw_class=texrect cycle=copy tile=0 sampled_low32=1b8530fb palette_crc=52e0d253 fs=258 selector=52e0d2531b8530fb prefer_exact_fs=1 exact_entries=33 generic_entries=0 active_entries=33 unique_checksums=1 unique_selectors=33 zero_selectors=0 matching_selectors=0 ordered_selectors=0 repl_dims=1 uniform_repl_dims=1 sample_repl=1184x24 active_is_pool=1 sample_policy=sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb-pool sample_replacement_id=legacy-1b8530fb-a sampled_object=sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb.\n"
        "Hi-res sampled-object family: available=0 draw_class=triangle cycle=2cycle tile=0 sampled_low32=91887078 palette_crc=00000000 fs=4 selector=00000000de3dac2a.\n"
    )
    family_items = module.load_runtime_family_items(bundle, {"top_exact_family_buckets": []})
    check(len(family_items) == 2, f"unexpected runtime family item count: {family_items}")
    family_index = module.build_runtime_family_index(family_items)
    runtime_pool = module.build_runtime_family_annotation(pool_row, family_index)
    check(runtime_pool["runtime_family_status"] == "runtime-pool-family", f"unexpected parsed runtime pool: {runtime_pool}")
    check(runtime_pool["runtime_sample_replacement_id"] == "legacy-1b8530fb-a", f"unexpected parsed runtime replacement id: {runtime_pool}")
    missing_family = module.build_runtime_family_annotation(candidate_free_row, family_index)
    check(missing_family["runtime_family_status"] == "runtime-family-missing", f"unexpected parsed missing runtime family: {missing_family}")

print("emu_hires_sampled_selector_review_contract: PASS")
PY
