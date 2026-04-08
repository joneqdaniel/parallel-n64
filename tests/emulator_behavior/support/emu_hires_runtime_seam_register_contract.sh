#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bundle/traces"

cat > "$TMP_DIR/bundle/traces/hires-evidence.json" <<'EOF'
{
  "sampled_pool_stream_probe": {
    "line_count": 3,
    "family_count": 1,
    "top_families": [
      {
        "count": 3,
        "fields": {
          "sampled_low32": "1b8530fb",
          "palette_crc": "52e0d253",
          "fs": "258",
          "observed_selector": "05556c9778538e1e",
          "observed_selector_source": "texel1",
          "observed_count": "3",
          "unique_observed_selectors": "2",
          "transition_count": "1",
          "repeat_count": "1",
          "current_run": "1",
          "max_run": "2",
          "active_entries": "33",
          "runtime_unique_selectors": "33",
          "ordered_selectors": "0",
          "sample_policy": "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb-pool",
          "sample_replacement_id": "legacy-1b8530fb-a",
          "sampled_object": "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb"
        },
        "sample_detail": "synthetic"
      }
    ]
  },
  "sampled_duplicate_probe": {
    "line_count": 1,
    "unique_bucket_count": 1,
    "top_buckets": [
      {
        "count": 1,
        "fields": {
          "sampled_low32": "7701ac09",
          "palette_crc": "00000000",
          "fs": "768",
          "selector": "0000000071c71cdd",
          "total_entries": "2",
          "duplicate_entries": "1",
          "policy": "surface-7701ac09",
          "replacement_id": "legacy-844144ad-00000000-fs0-1600x16",
          "sampled_object": "sampled-fmt0-siz3-off0-stride400-wh200x2-fs768-low327701ac09",
          "repl": "1600x16",
          "source": "/tmp/package.phrb#surface-7701ac09"
        },
        "sample_detail": "synthetic"
      }
    ]
  }
}
EOF

cat > "$TMP_DIR/selector-review.json" <<'EOF'
{
  "unresolved": [
    {
      "sampled_low32": "91887078",
      "draw_class": "triangle",
      "cycle": "2cycle",
      "fs": "4",
      "count": 10296,
      "package_status": "absent-from-package",
      "transport_status": "legacy-transport-candidate-free",
      "matching_transport_candidate_count": 0,
      "matching_transport_group_count": 1,
      "sample_detail": "candidate-free"
    },
    {
      "sampled_low32": "28916d63",
      "draw_class": "texrect",
      "cycle": "copy",
      "fs": "258",
      "count": 11984,
      "package_status": "absent-from-package",
      "transport_status": "legacy-transport-candidates-available",
      "matching_transport_candidate_count": 29,
      "matching_transport_group_count": 1,
      "sample_detail": "candidate-backed"
    }
  ],
  "pool_families": [
    {
      "sampled_low32": "1b8530fb",
      "draw_class": "texrect",
      "cycle": "copy",
      "fs": "258",
      "count": 2112,
      "pool_recommendation": "defer-runtime-pool-semantics",
      "pool_package_status": "present-pool-selector-conflict",
      "pool_runtime_status": "runtime-pool-family",
      "runtime_sample_policy": "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb-pool",
      "runtime_sample_replacement_id": "legacy-1b8530fb-a",
      "runtime_sampled_object": "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb",
      "runtime_unique_selector_count": 33,
      "runtime_matching_selector_count": 0,
      "matching_transport_candidate_count": 33,
      "transport_status": "legacy-transport-candidates-available"
    }
  ]
}
EOF

cat > "$TMP_DIR/alternate-source-review.json" <<'EOF'
{
  "groups": [
    {
      "signature": {
        "sampled_low32": "91887078",
        "draw_class": "triangle",
        "cycle": "2cycle",
        "formatsize": 4
      },
      "alternate_source_status": "source-backed-candidates-available",
      "unique_transport_pixel_count": 2,
      "seeded_transport_pool": {
        "cache_path": "/tmp/source.hts",
        "seed_dimensions": "16x32",
        "candidate_count": 2,
        "candidate_formatsizes": [0]
      }
    }
  ]
}
EOF

cat > "$TMP_DIR/cross-scene-review.json" <<'EOF'
{
  "families": [
    {
      "sampled_low32": "91887078",
      "promotion_status": "no-runtime-discriminator-observed",
      "recommendation": "keep-family-review-only-until-new-runtime-discriminator-or-source-evidence",
      "shared_signature_count": 1,
      "target_exclusive_signature_count": 0,
      "guard_exclusive_signature_count": 0,
      "target_labels": ["timeout"],
      "guard_labels": ["title", "file", "world"],
      "shared_guard_labels": ["title", "file"],
      "guard_labels_without_observation": ["world"]
    }
  ]
}
EOF

python3 "$REPO_ROOT/tools/hires_alternate_source_activation_review.py" \
  --alternate-source-review "$TMP_DIR/alternate-source-review.json" \
  --cross-scene-review "$TMP_DIR/cross-scene-review.json" \
  --output-json "$TMP_DIR/alternate-source-activation-review.json" \
  --output-markdown "$TMP_DIR/alternate-source-activation-review.md"

python3 "$REPO_ROOT/tools/hires_runtime_seam_register.py" \
  --bundle-dir "$TMP_DIR/bundle" \
  --selector-review "$TMP_DIR/selector-review.json" \
  --alternate-source-review "$TMP_DIR/alternate-source-review.json" \
  --cross-scene-review "$TMP_DIR/cross-scene-review.json" \
  --alternate-source-activation-review "$TMP_DIR/alternate-source-activation-review.json" \
  --output "$TMP_DIR/runtime-seam-register.md" \
  --output-json "$TMP_DIR/runtime-seam-register.json"

python3 - "$TMP_DIR/runtime-seam-register.json" "$TMP_DIR/runtime-seam-register.md" <<'PY'
import json
import sys
from pathlib import Path

register = json.loads(Path(sys.argv[1]).read_text())
markdown = Path(sys.argv[2]).read_text()

def check(condition, message):
    if not condition:
        raise SystemExit(message)

summary = register.get("summary") or {}
check(summary.get("candidate_free_absent_family_count") == 1, f"unexpected candidate-free count: {summary}")
check(summary.get("candidate_free_alt_source_available_count") == 1, f"unexpected alternate-source ready count: {summary}")
check(summary.get("candidate_free_alt_source_total_candidates") == 2, f"unexpected alternate-source candidate total: {summary}")
check(summary.get("candidate_free_no_runtime_discriminator_count") == 1, f"unexpected no-runtime-discriminator count: {summary}")
check(summary.get("candidate_free_review_bounded_probe_count") == 0, f"unexpected review-bounded probe count: {summary}")
check(summary.get("candidate_backed_absent_family_count") == 1, f"unexpected candidate-backed count: {summary}")
check(summary.get("pool_conflict_family_count") == 1, f"unexpected pool-conflict count: {summary}")
check(summary.get("sampled_duplicate_family_count") == 1, f"unexpected sampled-duplicate count: {summary}")

recommendations = set(register.get("recommendations") or [])
check("prefer-review-only-alternate-source-lane-for-candidate-free-families" in recommendations, f"missing alternate-source recommendation: {recommendations}")
check("keep-cross-scene-shared-candidate-free-families-review-only" in recommendations, f"missing cross-scene recommendation: {recommendations}")
check("keep-candidate-backed-absent-families-separated-from-runtime-pool-work" in recommendations, f"missing candidate-backed recommendation: {recommendations}")
check("defer-runtime-pool-semantics-until-selector-stream-model-is-bounded" in recommendations, f"missing pool recommendation: {recommendations}")
check("defer-native-duplicate-resolution-policy-until-active-winner-rules-are-designed" in recommendations, f"missing duplicate recommendation: {recommendations}")

candidate_free = (register.get("candidate_free_absent_families") or [None])[0]
check(candidate_free is not None and candidate_free.get("alternate_source_candidate_count") == 2, f"unexpected candidate-free row: {candidate_free}")
check(candidate_free.get("alternate_source_seed_dimensions") == "16x32", f"unexpected alternate-source dimensions: {candidate_free}")
check(candidate_free.get("cross_scene_promotion_status") == "no-runtime-discriminator-observed", f"unexpected cross-scene promotion status: {candidate_free}")
check(candidate_free.get("activation_status") == "shared-scene-source-backed-candidates", f"unexpected activation status: {candidate_free}")
check(candidate_free.get("activation_recommendation") == "keep-review-only-until-new-runtime-discriminator", f"unexpected activation recommendation: {candidate_free}")
check(candidate_free.get("cross_scene_shared_guard_labels") == ["title", "file"], f"unexpected shared guard labels: {candidate_free}")
check(candidate_free.get("cross_scene_guard_labels_without_observation") == ["world"], f"unexpected absent guard labels: {candidate_free}")
pool = (register.get("pool_conflict_families") or [None])[0]
check(pool is not None and pool.get("sampled_low32") == "1b8530fb", f"unexpected pool family: {pool}")
check(pool.get("runtime_sample_replacement_id") == "legacy-1b8530fb-a", f"unexpected pool replacement id: {pool}")
check(pool.get("stream_observed_count") == "3", f"unexpected pool stream observed count: {pool}")
check(pool.get("stream_unique_observed_selectors") == "2", f"unexpected pool stream selector count: {pool}")
check(pool.get("stream_transition_count") == "1", f"unexpected pool stream transition count: {pool}")
check(pool.get("stream_max_run") == "2", f"unexpected pool stream max run: {pool}")
check(pool.get("stream_observed_selector") == "05556c9778538e1e", f"unexpected pool stream selector: {pool}")
dupe = (register.get("sampled_duplicate_families") or [None])[0]
check(dupe is not None and dupe.get("sampled_low32") == "7701ac09", f"unexpected duplicate family: {dupe}")
check(dupe.get("replacement_id") == "legacy-844144ad-00000000-fs0-1600x16", f"unexpected duplicate replacement id: {dupe}")

check("Candidate-Free Absent Families" in markdown, "markdown missing candidate-free section")
check("alternate source `2` candidates at `16x32`" in markdown, "markdown missing alternate-source detail")
check("cross-scene `no-runtime-discriminator-observed`" in markdown, "markdown missing cross-scene detail")
check("activation `shared-scene-source-backed-candidates`" in markdown, "markdown missing activation detail")
check("shared guards `title,file`" in markdown, "markdown missing shared guard detail")
check("absent guards `world`" in markdown, "markdown missing absent guard detail")
check("Sampled Duplicate Families" in markdown, "markdown missing sampled duplicate section")
check("replacement `legacy-1b8530fb-a`" in markdown, "markdown missing pool replacement detail")
check("stream observed `3` across `2` selectors, transitions `1`, max run `2`" in markdown, "markdown missing pool stream detail")
check("replacement `legacy-844144ad-00000000-fs0-1600x16`" in markdown, "markdown missing sampled duplicate replacement detail")

print("emu_hires_runtime_seam_register_contract: PASS")
PY
