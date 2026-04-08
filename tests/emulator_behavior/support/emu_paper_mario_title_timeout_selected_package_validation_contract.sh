#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/package.phrb"
printf 'phrb' > "$CACHE_PATH"
ALT_SOURCE_CACHE_PATH="$REPO_ROOT/assets/PAPER MARIO_HIRESTEXTURES.hts"
if [[ ! -f "$ALT_SOURCE_CACHE_PATH" ]]; then
  echo "SKIP: alternate-source cache not found at $ALT_SOURCE_CACHE_PATH"
  exit 77
fi

mkdir -p "$TMP_DIR/bundles/on/timeout-960/captures" "$TMP_DIR/bundles/on/timeout-960/traces"
mkdir -p "$TMP_DIR/bundles/off/timeout-960/captures" "$TMP_DIR/bundles/off/timeout-960/traces"
mkdir -p "$TMP_DIR/guards/title/traces" "$TMP_DIR/guards/file/traces"
mkdir -p "$TMP_DIR/history"

python3 - "$TMP_DIR" <<'PY'
import json
import sys
from pathlib import Path
from PIL import Image

tmp_dir = Path(sys.argv[1])

for mode in ("on", "off"):
    capture_dir = tmp_dir / "bundles" / mode / "timeout-960" / "captures"
    Image.new("RGBA", (1, 1), (255, 255, 255, 255)).save(capture_dir / f"{mode}.png")

semantic = {
    "paper_mario_us": {
        "game_status": {
            "map_name_candidate": "kmr_03",
            "entry_id": 5,
        },
        "cur_game_mode": {
            "init_symbol": "state_init_world",
            "step_symbol": "state_step_world",
        },
    },
}
(tmp_dir / "bundles" / "on" / "timeout-960" / "traces" / "paper-mario-game-status.json").write_text(
    json.dumps(semantic, indent=2) + "\n"
)

hires = {
    "summary": {
        "provider": "on",
        "source_mode": "phrb-only",
        "source_policy": "phrb-only",
        "entry_count": 195,
        "native_sampled_entry_count": 195,
        "compat_entry_count": 0,
        "sampled_index_count": 194,
        "sampled_duplicate_key_count": 1,
        "sampled_duplicate_entry_count": 1,
        "sampled_family_count": 10,
        "source_counts": {
            "phrb": 195,
            "hts": 0,
            "htc": 0,
        },
        "descriptor_path_counts": {
            "sampled": 66,
            "native_checksum": 0,
            "generic": 0,
            "compat": 0,
        },
    },
    "sampled_object_probe": {
        "groups": [
            {
                "draw_class": "triangle",
                "cycle": "2cycle",
                "tile": "0",
                "fmt": "4",
                "siz": "0",
                "pal": "0",
                "off": "0",
                "stride": "8",
                "wh": "16x32",
                "upload_low32": "de3dac2a",
                "upload_pcrc": "00000000",
                "sampled_low32": "91887078",
                "sampled_entry_pcrc": "00000000",
                "sampled_sparse_pcrc": "00000000",
                "fs": "4",
            }
        ],
        "exact_hit_count": 99,
        "exact_miss_count": 657,
        "exact_conflict_miss_count": 66,
        "exact_unresolved_miss_count": 591,
        "top_exact_hit_buckets": [],
        "top_exact_conflict_miss_buckets": [],
        "top_exact_unresolved_miss_buckets": [
            {
                "count": 12,
                "fields": {
                    "reason": "lookup",
                    "draw_class": "triangle",
                    "cycle": "2cycle",
                    "tile": "0",
                    "sampled_low32": "91887078",
                    "palette_crc": "00000000",
                    "fs": "4",
                    "selector": "00000000de3dac2a",
                    "provider_enabled": "1",
                    "provider_entries": "195"
                },
                "sample_detail": "synthetic"
            }
        ],
    },
    "sampled_duplicate_probe": {
        "line_count": 1,
        "unique_bucket_count": 1,
        "top_buckets": [
            {
                "fields": {
                    "sampled_low32": "7701ac09",
                    "palette_crc": "00000000",
                    "fs": "768",
                    "selector": "0000000071c71cdd",
                    "total_entries": "2",
                    "policy": "surface-7701ac09",
                    "replacement_id": "legacy-844144ad-00000000-fs0-1600x16"
                }
            }
        ]
    }
}
(tmp_dir / "bundles" / "on" / "timeout-960" / "traces" / "hires-evidence.json").write_text(
    json.dumps(hires, indent=2) + "\n"
)

transport_review = {
    "groups": [
        {
            "signature": {
                "draw_class": "triangle",
                "cycle": "2cycle",
                "sampled_low32": "91887078",
                "sampled_entry_pcrc": "00000000",
                "sampled_sparse_pcrc": "00000000",
                "formatsize": 4,
                "replacement_dims": "0x0"
            },
            "canonical_identity": {
                "draw_class": "triangle",
                "cycle": "2cycle",
                "wh": "16x32",
                "formatsize": 4,
                "sampled_low32": "91887078",
                "sampled_entry_pcrc": "00000000",
                "sampled_sparse_pcrc": "00000000"
            },
            "probe_event_count": 1,
            "transport_candidates": []
        }
    ]
}
(tmp_dir / "transport-review.json").write_text(json.dumps(transport_review, indent=2) + "\n")

guard_hires = {
    "sampled_object_probe": {
        "groups": [
            {
                "draw_class": "triangle",
                "cycle": "2cycle",
                "tile": "0",
                "fmt": "4",
                "siz": "0",
                "pal": "0",
                "off": "0",
                "stride": "8",
                "wh": "16x32",
                "upload_low32": "de3dac2a",
                "upload_pcrc": "00000000",
                "sampled_low32": "91887078",
                "sampled_entry_pcrc": "00000000",
                "sampled_sparse_pcrc": "00000000",
                "fs": "4",
            }
        ],
        "top_exact_family_buckets": [],
        "top_exact_hit_buckets": [],
        "top_exact_unresolved_miss_buckets": [],
    }
}
(tmp_dir / "guards" / "title" / "traces" / "hires-evidence.json").write_text(
    json.dumps(guard_hires, indent=2) + "\n"
)
(tmp_dir / "guards" / "file" / "traces" / "hires-evidence.json").write_text(
    json.dumps(guard_hires, indent=2) + "\n"
)

def write_history(path, *, ae, rmse, hit_rows):
    path.write_text(json.dumps({
        "cache_path": str(path.with_suffix(".phrb")),
        "cache_sha256": path.stem,
        "steps": [
            {
                "step_frames": 960,
                "selected_hash": f"{path.stem}-selected",
                "legacy_hash": f"{path.stem}-legacy",
                "matches_legacy": False,
                "ae": ae,
                "rmse": rmse,
                "sampled_object_probe": {
                    "exact_hit_count": 1,
                    "exact_conflict_miss_count": 0,
                    "exact_unresolved_miss_count": 0,
                    "top_exact_hit_buckets": [
                        {
                            "count": count,
                            "fields": {
                                "sampled_low32": "1b8530fb",
                                "reason": reason,
                                "key": "52e0d2531b8530fb",
                                "repl": "1184x24",
                            },
                            "sample_detail": f"{reason} x {count}",
                        }
                        for reason, count in hit_rows
                    ],
                },
            }
        ],
    }, indent=2) + "\n")

write_history(tmp_dir / "history" / "flat-summary.json", ae=1659865, rmse=1.3326554039, hit_rows=[("sampled-sparse-exact", 1056)])
write_history(tmp_dir / "history" / "dual-summary.json", ae=34094281, rmse=10.8172496800, hit_rows=[("sampled-sparse-exact", 1056), ("sampled-sparse-ordered-surface", 1056)])
write_history(tmp_dir / "history" / "ordered-summary.json", ae=126937490, rmse=19.8116065828, hit_rows=[("sampled-sparse-ordered-surface", 2112)])
(tmp_dir / "history" / "surface-package.json").write_text(json.dumps({
    "surface_count": 1,
    "surfaces": [
        {
            "canonical_identity": {
                "sampled_low32": "1b8530fb",
            },
            "surface": {
                "sampled_low32": "1b8530fb",
                "shape_hint": "rotating-stream-edge-dwell",
                "slot_count": 34,
                "replacement_ids": ["r0", "r1", "r2"],
                "unresolved_sequences": [
                    {
                        "sequence_index": 33,
                        "upload_key": "77e5f3760b110a9b",
                    }
                ],
            },
        }
    ],
}, indent=2) + "\n")
(tmp_dir / "history" / "package-manifest.json").write_text(json.dumps({
    "records": [
        {
            "policy_key": "surface-7701ac09",
            "canonical_identity": {
                "sampled_low32": "7701ac09",
            },
            "asset_candidates": [
                {
                    "replacement_id": "legacy-844144ad-00000000-fs0-1600x16",
                    "legacy_texture_crc": "844144ad",
                    "selector_checksum64": "0000000071c71cdd",
                    "variant_group_id": "surface-7701ac09-0000000071c71cdd",
                    "materialized_path": "assets/legacy-844144ad-00000000-fs0-1600x16.png",
                    "pixel_sha256": "61827be38596dd7941e48ca97760fb7a3602c704f4dbfab44d1444d06db267a4",
                    "alpha_normalized_pixel_sha256": "f627ca4c2c322f15db26152df306bd4f983f0146409b81a4341b9b340c365a16",
                },
                {
                    "replacement_id": "legacy-e0dc03d0-00000000-fs0-1600x16",
                    "legacy_texture_crc": "e0dc03d0",
                    "selector_checksum64": "0000000071c71cdd",
                    "variant_group_id": "surface-7701ac09-0000000071c71cdd",
                    "materialized_path": "assets/legacy-e0dc03d0-00000000-fs0-1600x16.png",
                    "pixel_sha256": "61827be38596dd7941e48ca97760fb7a3602c704f4dbfab44d1444d06db267a4",
                    "alpha_normalized_pixel_sha256": "f627ca4c2c322f15db26152df306bd4f983f0146409b81a4341b9b340c365a16",
                },
            ],
            "duplicate_pixel_groups": [
                {
                    "alpha_normalized_pixel_sha256": "f627ca4c2c322f15db26152df306bd4f983f0146409b81a4341b9b340c365a16",
                    "replacement_ids": [
                        "legacy-844144ad-00000000-fs0-1600x16",
                        "legacy-e0dc03d0-00000000-fs0-1600x16",
                    ],
                }
            ],
        }
    ]
}, indent=2) + "\n")
PY

bash "$REPO_ROOT/tools/scenarios/paper-mario-title-timeout-selected-package-validation.sh" \
  --cache-path "$CACHE_PATH" \
  --bundle-root "$TMP_DIR/bundles" \
  --steps "960" \
  --transport-review "$TMP_DIR/transport-review.json" \
  --alternate-source-cache "$ALT_SOURCE_CACHE_PATH" \
  --package-manifest "$TMP_DIR/history/package-manifest.json" \
  --pool-regression-flat-summary "$TMP_DIR/history/flat-summary.json" \
  --pool-regression-dual-summary "$TMP_DIR/history/dual-summary.json" \
  --pool-regression-ordered-summary "$TMP_DIR/history/ordered-summary.json" \
  --pool-regression-surface-package "$TMP_DIR/history/surface-package.json" \
  --cross-scene-guard-evidence "title=$TMP_DIR/guards/title/traces/hires-evidence.json" \
  --cross-scene-guard-evidence "file=$TMP_DIR/guards/file/traces/hires-evidence.json" \
  --reuse

python3 - "$TMP_DIR/bundles/validation-summary.json" "$TMP_DIR/bundles/validation-summary.md" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text())
markdown = Path(sys.argv[2]).read_text()

steps = summary.get("steps") or []
if len(steps) != 1:
    raise SystemExit(f"FAIL: expected 1 step, found {len(steps)}.")

step = steps[0]
hires = step.get("hires_summary") or {}
if hires.get("source_mode") != "phrb-only":
    raise SystemExit(f"FAIL: unexpected source mode {hires.get('source_mode')!r}.")
if hires.get("source_policy") != "phrb-only":
    raise SystemExit(f"FAIL: unexpected source policy {hires.get('source_policy')!r}.")
if hires.get("native_sampled_entry_count") != 195:
    raise SystemExit(f"FAIL: unexpected native sampled count {hires.get('native_sampled_entry_count')!r}.")
descriptor_path_counts = step.get("descriptor_path_counts") or {}
if descriptor_path_counts != {"sampled": 66, "native_checksum": 0, "generic": 0, "compat": 0}:
    raise SystemExit(f"FAIL: unexpected descriptor path counts {descriptor_path_counts!r}.")
if step.get("sampled_object_probe", {}).get("exact_conflict_miss_count") != 66:
    raise SystemExit(f"FAIL: unexpected sampled conflict misses in {step!r}.")
if step.get("sampled_duplicate_probe", {}).get("unique_bucket_count") != 1:
    raise SystemExit(f"FAIL: unexpected sampled duplicate bucket count in {step!r}.")
pool_reviews = step.get("sampled_pool_reviews") or []
if pool_reviews:
    if pool_reviews[0].get("runtime_sample_replacement_id") != "legacy-038a968c-9afc43ab-fs0-1184x24":
        raise SystemExit(f"FAIL: unexpected pool runtime replacement id in {pool_reviews[0]!r}.")
alt_review = step.get("alternate_source_review") or {}
if alt_review.get("available_group_count") != 1:
    raise SystemExit(f"FAIL: unexpected alternate-source available count in {alt_review!r}.")
if alt_review.get("total_candidate_count") != 1:
    raise SystemExit(f"FAIL: unexpected alternate-source candidate count in {alt_review!r}.")
activation_review = step.get("alternate_source_activation_review") or {}
activation_summary = activation_review.get("summary") or {}
if activation_summary.get("review_bounded_probe_count") != 0:
    raise SystemExit(f"FAIL: unexpected activation review bounded-probe count in {activation_review!r}.")
if activation_summary.get("shared_scene_blocked_count") != 1:
    raise SystemExit(f"FAIL: unexpected activation review shared-scene blocked count in {activation_review!r}.")
activation_families = activation_review.get("families") or []
if len(activation_families) != 1:
    raise SystemExit(f"FAIL: expected one activation review family, found {activation_families!r}.")
if activation_families[0].get("sampled_low32") != "91887078":
    raise SystemExit(f"FAIL: unexpected activation review family payload {activation_families!r}.")
if activation_families[0].get("activation_status") != "shared-scene-source-backed-candidates":
    raise SystemExit(f"FAIL: unexpected activation review status in {activation_families!r}.")
if activation_families[0].get("activation_recommendation") != "keep-review-only-until-new-runtime-discriminator":
    raise SystemExit(f"FAIL: unexpected activation review recommendation in {activation_families!r}.")
cross_scene_review = step.get("sampled_cross_scene_review") or {}
families = cross_scene_review.get("families") or []
if len(families) != 1:
    raise SystemExit(f"FAIL: expected one cross-scene family, found {families!r}.")
if families[0].get("sampled_low32") != "91887078":
    raise SystemExit(f"FAIL: unexpected cross-scene family payload {families!r}.")
if families[0].get("promotion_status") != "no-runtime-discriminator-observed":
    raise SystemExit(f"FAIL: unexpected cross-scene promotion status in {families!r}.")
seam_register = step.get("runtime_seam_register") or {}
duplicate_families = seam_register.get("sampled_duplicate_families") or []
if duplicate_families:
    if duplicate_families[0].get("replacement_id") != "legacy-844144ad-00000000-fs0-1600x16":
        raise SystemExit(f"FAIL: unexpected duplicate replacement id in seam register {duplicate_families[0]!r}.")
duplicate_reviews = step.get("sampled_duplicate_reviews") or []
if len(duplicate_reviews) != 1:
    raise SystemExit(f"FAIL: expected one sampled duplicate review, found {duplicate_reviews!r}.")
if duplicate_reviews[0].get("recommendation") != "keep-runtime-winner-rule-and-defer-offline-dedupe":
    raise SystemExit(f"FAIL: unexpected sampled duplicate review {duplicate_reviews[0]!r}.")
pool_regression = step.get("sampled_pool_regression_review") or {}
if pool_regression.get("json_path"):
    if pool_regression.get("recommendation") != "keep-flat-runtime-binding":
        raise SystemExit(f"FAIL: unexpected pool regression recommendation in {pool_regression!r}.")
    case_metrics = pool_regression.get("case_metrics") or []
    if [case.get("label") for case in case_metrics] != ["flat", "dual", "ordered-only"]:
        raise SystemExit(f"FAIL: unexpected pool regression cases in {case_metrics!r}.")
if "source mode `phrb-only`" not in markdown:
    raise SystemExit("FAIL: markdown summary missing source mode line.")
if "source policy `phrb-only`" not in markdown:
    raise SystemExit("FAIL: markdown summary missing source policy line.")
if "descriptor paths sampled `66` / native checksum `0` / generic `0` / compat `0`" not in markdown:
    raise SystemExit("FAIL: markdown summary missing descriptor path counts.")
if "Sampled duplicate keys: `1` buckets, `1` log lines" not in markdown:
    raise SystemExit("FAIL: markdown summary missing sampled duplicate line.")
if "Alternate-source review:" not in markdown:
    raise SystemExit("FAIL: markdown summary missing alternate-source review line.")
if "Alternate-source family `91887078`" not in markdown:
    raise SystemExit("FAIL: markdown summary missing alternate-source family detail.")
if "Alternate-source activation review:" not in markdown:
    raise SystemExit("FAIL: markdown summary missing alternate-source activation review line.")
if "Alternate-source activation family `91887078`" not in markdown:
    raise SystemExit("FAIL: markdown summary missing alternate-source activation family detail.")
if "Cross-scene review:" not in markdown:
    raise SystemExit("FAIL: markdown summary missing cross-scene review line.")
if "Cross-scene family `91887078`" not in markdown:
    raise SystemExit("FAIL: markdown summary missing cross-scene family detail.")
if "Sampled duplicate review `7701ac09`" not in markdown:
    raise SystemExit("FAIL: markdown summary missing sampled duplicate review line.")
print("emu_paper_mario_title_timeout_selected_package_validation_contract: PASS")
PY
