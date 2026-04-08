#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

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
      "seeded_transport_pool": {
        "candidate_count": 1,
        "seed_dimensions": "16x32",
        "seed_dimension_set": ["16x32"],
        "candidate_formatsizes": [0]
      }
    },
    {
      "signature": {
        "sampled_low32": "6af0d9ca",
        "draw_class": "triangle",
        "cycle": "2cycle",
        "formatsize": 768
      },
      "alternate_source_status": "source-backed-candidates-available",
      "seeded_transport_pool": {
        "candidate_count": 7,
        "seed_dimensions": "32x32",
        "seed_dimension_set": ["32x32"],
        "candidate_formatsizes": [0]
      }
    },
    {
      "signature": {
        "sampled_low32": "deadbeef",
        "draw_class": "triangle",
        "cycle": "2cycle",
        "formatsize": 2
      },
      "alternate_source_status": "source-backed-candidate-free",
      "seeded_transport_pool": {
        "candidate_count": 0,
        "seed_dimensions": "32x16",
        "seed_dimension_set": ["32x16"],
        "candidate_formatsizes": []
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
      "shared_guard_labels": ["title", "file"],
      "guard_labels_without_observation": []
    },
    {
      "sampled_low32": "6af0d9ca",
      "promotion_status": "target-exclusive-runtime-signatures-observed",
      "recommendation": "candidate-bounded-target-exclusive-probe-is-allowed",
      "shared_guard_labels": [],
      "guard_labels_without_observation": ["file"]
    }
  ]
}
EOF

python3 "$REPO_ROOT/tools/hires_alternate_source_activation_review.py" \
  --alternate-source-review "$TMP_DIR/alternate-source-review.json" \
  --cross-scene-review "$TMP_DIR/cross-scene-review.json" \
  --output-json "$TMP_DIR/activation-review.json" \
  --output-markdown "$TMP_DIR/activation-review.md"

python3 - "$TMP_DIR/activation-review.json" "$TMP_DIR/activation-review.md" <<'PY'
import json
import sys
from pathlib import Path

review = json.loads(Path(sys.argv[1]).read_text())
markdown = Path(sys.argv[2]).read_text()

def check(condition, message):
    if not condition:
        raise SystemExit(message)

families = {row["sampled_low32"]: row for row in review.get("families", [])}
check(review.get("summary", {}).get("review_bounded_probe_count") == 1, f"unexpected summary: {review}")
check(review.get("summary", {}).get("shared_scene_blocked_count") == 1, f"unexpected summary: {review}")
check(review.get("summary", {}).get("no_source_count") == 1, f"unexpected summary: {review}")

shared = families.get("91887078")
check(shared is not None, f"missing shared family: {families}")
check(shared.get("activation_status") == "shared-scene-source-backed-candidates", f"unexpected shared family: {shared}")
check(shared.get("activation_recommendation") == "keep-review-only-until-new-runtime-discriminator", f"unexpected shared family: {shared}")

exclusive = families.get("6af0d9ca")
check(exclusive is not None, f"missing exclusive family: {families}")
check(exclusive.get("activation_status") == "target-exclusive-source-backed-candidates", f"unexpected exclusive family: {exclusive}")
check(exclusive.get("activation_recommendation") == "review-bounded-probe-allowed", f"unexpected exclusive family: {exclusive}")

empty = families.get("deadbeef")
check(empty is not None, f"missing no-source family: {families}")
check(empty.get("activation_status") == "no-source-backed-candidates", f"unexpected no-source family: {empty}")
check(empty.get("activation_recommendation") == "defer-until-new-source-evidence", f"unexpected no-source family: {empty}")

check("Alternate-Source Activation Review" in markdown, "markdown missing title")
check("shared-scene-source-backed-candidates" in markdown, "markdown missing shared-scene status")
check("target-exclusive-source-backed-candidates" in markdown, "markdown missing target-exclusive status")
check("no-source-backed-candidates" in markdown, "markdown missing no-source status")

print("emu_hires_alternate_source_activation_review_contract: PASS")
PY
