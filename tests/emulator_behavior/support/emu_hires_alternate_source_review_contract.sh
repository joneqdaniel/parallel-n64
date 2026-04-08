#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$REPO_ROOT/assets/PAPER MARIO_HIRESTEXTURES.hts"
if [[ ! -f "$CACHE_PATH" ]]; then
  echo "FAIL: expected cache asset at $CACHE_PATH" >&2
  exit 1
fi

cat > "$TMP_DIR/selector-review.json" <<'EOF'
{
  "unresolved": [
    {
      "sampled_low32": "91887078",
      "draw_class": "triangle",
      "cycle": "2cycle",
      "fs": "4",
      "package_status": "absent-from-package",
      "transport_status": "legacy-transport-candidate-free"
    },
    {
      "sampled_low32": "6af0d9ca",
      "draw_class": "triangle",
      "cycle": "2cycle",
      "fs": "768",
      "package_status": "absent-from-package",
      "transport_status": "legacy-transport-candidate-free"
    },
    {
      "sampled_low32": "e0d4d0dc",
      "draw_class": "triangle",
      "cycle": "2cycle",
      "fs": "2",
      "package_status": "absent-from-package",
      "transport_status": "legacy-transport-candidate-free"
    }
  ]
}
EOF

cat > "$TMP_DIR/transport-review.json" <<'EOF'
{
  "groups": [
    {
      "signature": {
        "draw_class": "triangle",
        "cycle": "2cycle",
        "sampled_low32": "91887078",
        "formatsize": 4
      },
      "canonical_identity": {
        "wh": "16x32"
      },
      "transport_candidates": []
    },
    {
      "signature": {
        "draw_class": "triangle",
        "cycle": "2cycle",
        "sampled_low32": "91887078",
        "formatsize": 4
      },
      "canonical_identity": {
        "wh": "16x32"
      },
      "transport_candidates": []
    },
    {
      "signature": {
        "draw_class": "triangle",
        "cycle": "2cycle",
        "sampled_low32": "6af0d9ca",
        "formatsize": 768
      },
      "canonical_identity": {
        "wh": "32x32"
      },
      "transport_candidates": []
    },
    {
      "signature": {
        "draw_class": "triangle",
        "cycle": "2cycle",
        "sampled_low32": "e0d4d0dc",
        "formatsize": 2
      },
      "canonical_identity": {
        "wh": "32x16"
      },
      "transport_candidates": []
    }
  ]
}
EOF

python3 "$REPO_ROOT/tools/hires_seed_alternate_source_review.py" \
  --review "$TMP_DIR/transport-review.json" \
  --selector-review "$TMP_DIR/selector-review.json" \
  --cache "$CACHE_PATH" \
  --output-json "$TMP_DIR/alternate-source-review.json" \
  --output-markdown "$TMP_DIR/alternate-source-review.md"

python3 - "$TMP_DIR/alternate-source-review.json" "$TMP_DIR/alternate-source-review.md" <<'PY'
import json
import sys
from pathlib import Path

review = json.loads(Path(sys.argv[1]).read_text())
markdown = Path(sys.argv[2]).read_text()

def check(condition, message):
    if not condition:
        raise SystemExit(message)

check(review.get("group_count") == 3, f"unexpected group count: {review}")
check(review.get("available_group_count") == 3, f"unexpected available count: {review}")
check(review.get("total_candidate_count") == 13, f"unexpected total candidate count: {review}")

counts = {}
for group in review.get("groups", []):
    signature = group.get("signature") or {}
    seeded = group.get("seeded_transport_pool") or {}
    low32 = signature.get("sampled_low32")
    counts[low32] = int(seeded.get("candidate_count") or 0)
    check(group.get("alternate_source_status") == "source-backed-candidates-available", f"unexpected status for {low32}: {group}")
    check(seeded.get("source") == "alternate-source-dimension-seed", f"unexpected source for {low32}: {seeded}")
    check(seeded.get("candidate_formatsizes") == [0], f"unexpected candidate formatsizes for {low32}: {seeded}")
    if low32 == "91887078":
        check(group.get("matched_review_group_count") == 2, f"unexpected matched review group count for {low32}: {group}")
        check(seeded.get("matched_review_group_count") == 2, f"unexpected seeded matched review group count for {low32}: {seeded}")
        check(seeded.get("seed_dimensions") == "16x32", f"unexpected seed dimensions for {low32}: {seeded}")

check(counts.get("91887078") == 1, f"unexpected 91887078 count: {counts}")
check(counts.get("6af0d9ca") == 7, f"unexpected 6af0d9ca count: {counts}")
check(counts.get("e0d4d0dc") == 5, f"unexpected e0d4d0dc count: {counts}")

check("Alternate-Source Review" in markdown, "markdown missing title")
check("`91887078` `triangle` / `2cycle` `fs=4`" in markdown, "markdown missing 91887078 section")
check("`6af0d9ca` `triangle` / `2cycle` `fs=768`" in markdown, "markdown missing 6af0d9ca section")
check("`e0d4d0dc` `triangle` / `2cycle` `fs=2`" in markdown, "markdown missing e0d4d0dc section")
check("Matched review groups: `2`" in markdown, "markdown missing matched-review-group detail")

print("emu_hires_alternate_source_review_contract: PASS")
PY
