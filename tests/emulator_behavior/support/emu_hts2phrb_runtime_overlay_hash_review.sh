#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-overlay-hash-review-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"

python3 - "$CACHE_PATH" <<'PY'
import gzip
import struct
import sys
from pathlib import Path

cache_path = Path(sys.argv[1])

TXCACHE_FORMAT_VERSION = 0x08000000
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401
GL_RGBA8 = 0x8058


def payload(width, height, seed):
    data = bytearray()
    for i in range(width * height):
        value = (seed + i * 17) & 0xFF
        data.extend(((value + 0) & 0xFF, (value + 1) & 0xFF, (value + 2) & 0xFF, 0xFF))
    return bytes(data)


records = [
    (0x11111111, 0xAAAA0001, 0, 2, 2, payload(2, 2, 0x10)),
    (0x22222222, 0xAAAA0002, 0, 2, 2, payload(2, 2, 0x10)),
    (0x33333333, 0xBBBB0001, 0, 2, 2, payload(2, 2, 0x20)),
    (0x44444444, 0xBBBB0002, 0, 2, 2, payload(2, 2, 0x30)),
    (0x55555555, 0xCCCC0001, 0, 4, 4, payload(4, 4, 0x40)),
]

with gzip.open(cache_path, "wb") as fp:
    fp.write(struct.pack("<i", TXCACHE_FORMAT_VERSION))
    fp.write(struct.pack("<i", 0))
    for texture_crc, palette_crc, formatsize, width, height, raw in records:
        checksum64 = (palette_crc << 32) | texture_crc
        fp.write(struct.pack("<Q", checksum64))
        fp.write(struct.pack("<IIIHHB", width, height, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, 1))
        fp.write(struct.pack("<H", formatsize))
        fp.write(struct.pack("<I", len(raw)))
        fp.write(raw)
PY

python3 - "$ROOT_DIR" "$CACHE_PATH" <<'PY'
import json
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

root_dir = Path(sys.argv[1])
cache_path = Path(sys.argv[2])
sys.path.insert(0, str(root_dir / "tools"))

from hts2phrb import (
    build_runtime_overlay_candidate_set_review_payload,
    build_runtime_overlay_review_payload,
    synchronize_report_summary_fields,
)


def make_candidate(replacement_id, texture_crc, palette_crc, width, height):
    return {
        "replacement_id": replacement_id,
        "source": {
            "legacy_checksum64": f"{palette_crc:08x}{texture_crc:08x}",
            "legacy_texture_crc": f"{texture_crc:08x}",
            "legacy_palette_crc": f"{palette_crc:08x}",
            "legacy_formatsize": 0,
            "legacy_source_path": str(cache_path),
        },
        "replacement_asset": {
            "width": width,
            "height": height,
        },
        "variant_group_id": f"group-{replacement_id}",
    }


bindings = {
    "unresolved_transport_cases": [
        {
            "policy_key": "overlay-case-1",
            "sampled_object_id": "overlay-case-1",
            "family_type": "proxy-transport",
            "status": "manual-review-required",
            "reason": "proxy-transport-selection-required",
            "transport_candidate_count": 2,
            "transport_candidate_palette_count": 2,
            "transport_candidate_dims": [{"dims": "2x2", "count": 2}],
            "transport_candidates": [
                make_candidate("identical-a", 0x11111111, 0xAAAA0001, 2, 2),
                make_candidate("identical-b", 0x22222222, 0xAAAA0002, 2, 2),
            ],
        },
        {
            "policy_key": "overlay-case-2",
            "sampled_object_id": "overlay-case-2",
            "family_type": "proxy-transport",
            "status": "manual-review-required",
            "reason": "proxy-transport-selection-required",
            "transport_candidate_count": 2,
            "transport_candidate_palette_count": 2,
            "transport_candidate_dims": [{"dims": "2x2", "count": 2}],
            "transport_candidates": [
                make_candidate("divergent-a", 0x33333333, 0xBBBB0001, 2, 2),
                make_candidate("divergent-b", 0x44444444, 0xBBBB0002, 2, 2),
            ],
        },
        {
            "policy_key": "overlay-case-3",
            "sampled_object_id": "overlay-case-3",
            "family_type": "proxy-transport",
            "status": "manual-review-required",
            "reason": "proxy-transport-selection-required",
            "transport_candidate_count": 2,
            "transport_candidate_palette_count": 2,
            "transport_candidate_dims": [{"dims": "2x2", "count": 2}],
            "transport_candidates": [
                make_candidate("divergent-a", 0x33333333, 0xBBBB0001, 2, 2),
                make_candidate("divergent-b", 0x44444444, 0xBBBB0002, 2, 2),
            ],
        },
        {
            "policy_key": "overlay-case-4",
            "sampled_object_id": "overlay-case-4",
            "family_type": "proxy-transport",
            "status": "manual-review-required",
            "reason": "proxy-transport-selection-required",
            "transport_candidate_count": 2,
            "transport_candidate_palette_count": 2,
            "transport_candidate_dims": [{"dims": "2x2", "count": 1}, {"dims": "4x4", "count": 1}],
            "transport_candidates": [
                make_candidate("multi-a", 0x33333333, 0xBBBB0001, 2, 2),
                make_candidate("multi-b", 0x55555555, 0xCCCC0001, 4, 4),
            ],
        },
    ]
}

review = build_runtime_overlay_review_payload(
    {"imported_index": {"unresolved_families": []}},
    bindings,
    {"requested_family_states": {"families": []}},
)
candidate_set_review = build_runtime_overlay_candidate_set_review_payload(review)

if review.get("unresolved_overlay_count") != 4:
    raise SystemExit(f"unexpected unresolved overlay count: {review!r}")
if review.get("reason_counts") != {"proxy-transport-selection-required": 4}:
    raise SystemExit(f"unexpected overlay reasons: {review.get('reason_counts')!r}")
if review.get("hash_review_class_counts") != {
    "pixel-divergent-multi-dim": 1,
    "pixel-divergent-single-dim": 2,
    "pixel-identical-single-dim": 1,
}:
    raise SystemExit(f"unexpected hash review class counts: {review.get('hash_review_class_counts')!r}")
if review.get("identical_alpha_hash_case_count_counts") != {"0": 2, "1": 2}:
    raise SystemExit(f"unexpected identical alpha-hash case counts: {review.get('identical_alpha_hash_case_count_counts')!r}")
if review.get("alpha_hash_overlap_case_count_counts") != {"0": 1, "1": 2, "2": 1}:
    raise SystemExit(f"unexpected alpha-hash overlap case counts: {review.get('alpha_hash_overlap_case_count_counts')!r}")
if review.get("candidate_set_cluster_count") != 3:
    raise SystemExit(f"unexpected candidate-set cluster count: {review.get('candidate_set_cluster_count')!r}")
if review.get("candidate_set_cluster_size_counts") != {"1": 2, "2": 2}:
    raise SystemExit(f"unexpected candidate-set cluster sizes: {review.get('candidate_set_cluster_size_counts')!r}")
if review.get("blocker_cluster_class_counts") != {
    "candidate-set-equivalent": 2,
    "small-multi-dim-cluster": 1,
    "small-single-dim-cluster": 1,
}:
    raise SystemExit(f"unexpected blocker cluster classes: {review.get('blocker_cluster_class_counts')!r}")
if review.get("action_hint_counts") != {
    "candidate-set-review": 2,
    "manual-selection-review": 2,
}:
    raise SystemExit(f"unexpected action hints: {review.get('action_hint_counts')!r}")
if candidate_set_review.get("candidate_set_review_group_count") != 1:
    raise SystemExit(f"unexpected candidate-set review group count: {candidate_set_review!r}")
if [group.get("policy_keys") for group in (candidate_set_review.get("groups") or [])] != [["overlay-case-2", "overlay-case-3"]]:
    raise SystemExit(f"unexpected candidate-set review groups: {candidate_set_review!r}")

entries = {entry["policy_key"]: entry for entry in review.get("entries") or []}
if entries["overlay-case-1"]["hash_review_class"] != "pixel-identical-single-dim":
    raise SystemExit(f"unexpected hash review for overlay-case-1: {entries['overlay-case-1']!r}")
if entries["overlay-case-1"]["transport_candidate_alpha_hash_count"] != 1:
    raise SystemExit(f"unexpected alpha-hash count for overlay-case-1: {entries['overlay-case-1']!r}")
if entries["overlay-case-1"]["blocker_cluster_class"] != "small-single-dim-cluster":
    raise SystemExit(f"unexpected blocker cluster for overlay-case-1: {entries['overlay-case-1']!r}")
if entries["overlay-case-1"]["action_hint"] != "manual-selection-review":
    raise SystemExit(f"unexpected action hint for overlay-case-1: {entries['overlay-case-1']!r}")
if entries["overlay-case-2"]["hash_review_class"] != "pixel-divergent-single-dim":
    raise SystemExit(f"unexpected hash review for overlay-case-2: {entries['overlay-case-2']!r}")
if entries["overlay-case-2"]["identical_alpha_hash_policy_keys"] != ["overlay-case-3"]:
    raise SystemExit(f"unexpected identical alpha-hash keys for overlay-case-2: {entries['overlay-case-2']!r}")
if entries["overlay-case-2"]["alpha_hash_overlap_policy_keys"] != ["overlay-case-4"]:
    raise SystemExit(f"unexpected alpha-hash overlaps for overlay-case-2: {entries['overlay-case-2']!r}")
if entries["overlay-case-2"]["candidate_set_equivalent_policy_keys"] != ["overlay-case-3"]:
    raise SystemExit(f"unexpected candidate-set equivalents for overlay-case-2: {entries['overlay-case-2']!r}")
if entries["overlay-case-2"]["blocker_cluster_class"] != "candidate-set-equivalent":
    raise SystemExit(f"unexpected blocker cluster for overlay-case-2: {entries['overlay-case-2']!r}")
if entries["overlay-case-2"]["action_hint"] != "candidate-set-review":
    raise SystemExit(f"unexpected action hint for overlay-case-2: {entries['overlay-case-2']!r}")
if entries["overlay-case-4"]["hash_review_class"] != "pixel-divergent-multi-dim":
    raise SystemExit(f"unexpected hash review for overlay-case-4: {entries['overlay-case-4']!r}")
if entries["overlay-case-4"]["alpha_hash_overlap_policy_keys"] != ["overlay-case-2", "overlay-case-3"]:
    raise SystemExit(f"unexpected alpha-hash overlaps for overlay-case-4: {entries['overlay-case-4']!r}")
if entries["overlay-case-4"]["blocker_cluster_class"] != "small-multi-dim-cluster":
    raise SystemExit(f"unexpected blocker cluster for overlay-case-4: {entries['overlay-case-4']!r}")

with TemporaryDirectory() as tmpdir:
    report = {
        "package_dir": str(Path(tmpdir)),
        "requested_family_states": {},
        "package_manifest_summary": {},
        "imported_index_summary": {},
        "stage_timings_ms": {"total": 1.0},
        "runtime_overlay_review_summary": review,
        "runtime_overlay_candidate_set_review_summary": candidate_set_review,
    }
    synchronize_report_summary_fields(report)
    if report.get("runtime_overlay_unresolved_count") != 4:
        raise SystemExit(
            f"unexpected top-level overlay unresolved count: {report.get('runtime_overlay_unresolved_count')!r}"
        )
    if report.get("runtime_overlay_reason_counts") != {"proxy-transport-selection-required": 4}:
        raise SystemExit(f"unexpected top-level overlay reasons: {report.get('runtime_overlay_reason_counts')!r}")
    if report.get("runtime_overlay_hash_review_class_counts") != {
        "pixel-divergent-multi-dim": 1,
        "pixel-divergent-single-dim": 2,
        "pixel-identical-single-dim": 1,
    }:
        raise SystemExit(
            f"unexpected top-level overlay hash classes: {report.get('runtime_overlay_hash_review_class_counts')!r}"
        )
    if report.get("runtime_overlay_candidate_set_cluster_count") != 3:
        raise SystemExit(
            f"unexpected top-level candidate-set cluster count: {report.get('runtime_overlay_candidate_set_cluster_count')!r}"
        )
    if report.get("runtime_overlay_candidate_set_cluster_size_counts") != {"1": 2, "2": 2}:
        raise SystemExit(
            f"unexpected top-level candidate-set cluster sizes: {report.get('runtime_overlay_candidate_set_cluster_size_counts')!r}"
        )
    if report.get("runtime_overlay_blocker_cluster_class_counts") != {
        "candidate-set-equivalent": 2,
        "small-multi-dim-cluster": 1,
        "small-single-dim-cluster": 1,
    }:
        raise SystemExit(
            f"unexpected top-level blocker cluster classes: {report.get('runtime_overlay_blocker_cluster_class_counts')!r}"
        )
    if report.get("runtime_overlay_action_hint_counts") != {
        "candidate-set-review": 2,
        "manual-selection-review": 2,
    }:
        raise SystemExit(
            f"unexpected top-level action hints: {report.get('runtime_overlay_action_hint_counts')!r}"
        )
    if report.get("runtime_overlay_candidate_set_review_group_count") != 1:
        raise SystemExit(
            f"unexpected top-level candidate-set review group count: {report.get('runtime_overlay_candidate_set_review_group_count')!r}"
        )
PY

echo "emu_hts2phrb_runtime_overlay_hash_review: PASS"
