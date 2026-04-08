#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

make_evidence() {
  local scene_dir="$1"
  local groups_json="$2"
  local family_buckets_json="$3"
  local hit_buckets_json="$4"
  local log_text="$5"
  mkdir -p "$scene_dir/traces" "$scene_dir/logs"
  cat > "$scene_dir/traces/hires-evidence.json" <<EOF
{
  "sampled_object_probe": {
    "groups": $groups_json,
    "top_exact_family_buckets": $family_buckets_json,
    "top_exact_hit_buckets": $hit_buckets_json,
    "top_exact_unresolved_miss_buckets": []
  }
}
EOF
  cat > "$scene_dir/logs/retroarch.log" <<EOF
$log_text
EOF
}

make_evidence "$TMP_DIR/timeout" '
[
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
    "fs": "4"
  }
]
' '
[
  {
    "count": 10296,
    "fields": {
      "available": "0",
      "draw_class": "triangle",
      "cycle": "2cycle",
      "tile": "0",
      "sampled_low32": "91887078",
      "palette_crc": "00000000",
      "fs": "4",
      "selector": "00000000de3dac2a"
    }
  },
  {
    "count": 7276,
    "fields": {
      "available": "0",
      "draw_class": "triangle",
      "cycle": "2cycle",
      "tile": "0",
      "sampled_low32": "6af0d9ca",
      "palette_crc": "00000000",
      "fs": "768",
      "selector": "000000001d27afb6"
    }
  }
]
' '
[
  {
    "count": 4096,
    "fields": {
      "draw_class": "triangle",
      "cycle": "2cycle",
      "tile": "0",
      "sampled_low32": "6af0d9ca"
    }
  }
]
' '
[INFO]: Hi-res sampled-object probe: draw_class=triangle cycle=2cycle tile=0 fmt=4 siz=0 pal=0 off=0 stride=8 wh=16x32 upload_low32=de3dac2a upload_pcrc=00000000 sampled_low32=91887078 sampled_entry_pcrc=00000000 sampled_sparse_pcrc=00000000 fs=4.
[INFO]: Hi-res sampled-object probe: draw_class=triangle cycle=2cycle tile=0 fmt=0 siz=3 pal=0 off=0 stride=32 wh=32x32 upload_low32=1d27afb6 upload_pcrc=00000000 sampled_low32=6af0d9ca sampled_entry_pcrc=00000000 sampled_sparse_pcrc=00000000 fs=768.
'

make_evidence "$TMP_DIR/title" '
[
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
    "fs": "4"
  }
]
' '
[
  {
    "count": 48,
    "fields": {
      "available": "0",
      "draw_class": "triangle",
      "cycle": "2cycle",
      "tile": "0",
      "sampled_low32": "91887078",
      "palette_crc": "00000000",
      "fs": "4",
      "selector": "00000000de3dac2a"
    }
  }
]
' '[]' '
[INFO]: Hi-res sampled-object probe: draw_class=triangle cycle=2cycle tile=0 fmt=4 siz=0 pal=0 off=0 stride=8 wh=16x32 upload_low32=de3dac2a upload_pcrc=00000000 sampled_low32=91887078 sampled_entry_pcrc=00000000 sampled_sparse_pcrc=00000000 fs=4.
'

make_evidence "$TMP_DIR/file" '
[
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
    "fs": "4"
  }
]
' '
[
  {
    "count": 24,
    "fields": {
      "available": "0",
      "draw_class": "triangle",
      "cycle": "2cycle",
      "tile": "0",
      "sampled_low32": "91887078",
      "palette_crc": "00000000",
      "fs": "4",
      "selector": "00000000de3dac2a"
    }
  }
]
' '[]' '
[INFO]: Hi-res sampled-object probe: draw_class=triangle cycle=2cycle tile=0 fmt=4 siz=0 pal=0 off=0 stride=8 wh=16x32 upload_low32=de3dac2a upload_pcrc=00000000 sampled_low32=91887078 sampled_entry_pcrc=00000000 sampled_sparse_pcrc=00000000 fs=4.
'

python3 "$REPO_ROOT/tools/hires_sampled_cross_scene_review.py" \
  --evidence timeout="$TMP_DIR/timeout/traces/hires-evidence.json" \
  --evidence title="$TMP_DIR/title/traces/hires-evidence.json" \
  --evidence file="$TMP_DIR/file/traces/hires-evidence.json" \
  --sampled-low32 91887078 \
  --sampled-low32 6af0d9ca \
  --target-label timeout \
  --guard-label title \
  --guard-label file \
  --output-json "$TMP_DIR/cross-scene-review.json" \
  --output-markdown "$TMP_DIR/cross-scene-review.md"

cat > "$TMP_DIR/review.json" <<'EOF'
{
  "cache": "/tmp/source.hts",
  "groups": [
    {
      "signature": {
        "sampled_low32": "91887078"
      },
      "canonical_identity": {
        "fmt": 4,
        "siz": 0,
        "off": 0,
        "stride": 8,
        "wh": "16x32",
        "formatsize": 4,
        "sampled_low32": "91887078"
      },
      "transport_candidates": [
        {
          "replacement_id": "legacy-9188",
          "checksum64": "0000000091887078",
          "texture_crc": "91887078",
          "palette_crc": "00000000",
          "formatsize": 0,
          "width": 16,
          "height": 32,
          "data_size": 2048,
          "upload_checksum64": "00000000de3dac2a"
        }
      ],
      "top_upload_families": [],
      "probe_event_count": 48,
      "exact_hit_count": 0,
      "transport_candidate_dims": ["16x32"]
    }
  ]
}
EOF

if python3 "$REPO_ROOT/tools/hires_pack_emit_probe_pool_binding.py" \
  --review "$TMP_DIR/review.json" \
  --sampled-low32 91887078 \
  --selector-mode zero \
  --cross-scene-review "$TMP_DIR/cross-scene-review.json" \
  --output "$TMP_DIR/should-not-exist.json" >"$TMP_DIR/guard.log" 2>&1; then
  echo "expected zero-selector guard to fail" >&2
  exit 1
fi

python3 "$REPO_ROOT/tools/hires_pack_emit_probe_pool_binding.py" \
  --review "$TMP_DIR/review.json" \
  --sampled-low32 91887078 \
  --selector-mode zero \
  --cross-scene-review "$TMP_DIR/cross-scene-review.json" \
  --allow-shared-scene-family \
  --output "$TMP_DIR/guard-override.json"

python3 - "$TMP_DIR/cross-scene-review.json" "$TMP_DIR/cross-scene-review.md" "$TMP_DIR/guard.log" "$TMP_DIR/guard-override.json" <<'PY'
import json
import sys
from pathlib import Path

review = json.loads(Path(sys.argv[1]).read_text())
markdown = Path(sys.argv[2]).read_text()
guard_log = Path(sys.argv[3]).read_text()
binding = json.loads(Path(sys.argv[4]).read_text())

def check(condition, message):
    if not condition:
        raise SystemExit(message)

families = {item["sampled_low32"]: item for item in review.get("families", [])}
shared = families.get("91887078")
check(shared is not None, f"missing shared family: {families}")
check(shared.get("promotion_status") == "no-runtime-discriminator-observed", f"unexpected shared status: {shared}")
check(shared.get("shared_signature_count") == 1, f"unexpected shared signature count: {shared}")
check(shared.get("target_exclusive_signature_count") == 0, f"unexpected target-exclusive count: {shared}")
check(shared.get("shared_guard_labels") == ["file", "title"], f"unexpected shared guard labels: {shared}")
check(shared.get("guard_labels_without_observation") == [], f"unexpected guard labels without observation: {shared}")

exclusive = families.get("6af0d9ca")
check(exclusive is not None, f"missing exclusive family: {families}")
check(exclusive.get("promotion_status") == "target-exclusive-runtime-signatures-observed", f"unexpected exclusive status: {exclusive}")
check(exclusive.get("shared_signature_count") == 0, f"unexpected exclusive shared count: {exclusive}")
check(exclusive.get("target_exclusive_signature_count") == 1, f"unexpected exclusive target-exclusive count: {exclusive}")
check(exclusive.get("shared_guard_labels") == [], f"unexpected exclusive shared guard labels: {exclusive}")
timeout_label = {label["label"]: label for label in exclusive.get("labels", [])}.get("timeout") or {}
check(timeout_label.get("group_signature_count") == 0, f"expected timeout fallback to come from log, got: {timeout_label}")
check(timeout_label.get("log_signature_count") == 1, f"expected timeout log signature count, got: {timeout_label}")

check("no-runtime-discriminator-observed" in markdown, "markdown missing shared-family status")
check("target-exclusive-runtime-signatures-observed" in markdown, "markdown missing exclusive-family status")
check("refuse selector_mode='zero'" in guard_log, f"guard did not explain failure: {guard_log}")

rows = binding.get("bindings") or []
check(len(rows) == 1, f"unexpected binding rows: {binding}")
cross_scene = rows[0].get("cross_scene_review") or {}
check(cross_scene.get("promotion_status") == "no-runtime-discriminator-observed", f"unexpected cross-scene binding metadata: {cross_scene}")
check(cross_scene.get("shared_signature_count") == 1, f"unexpected shared signature count in binding metadata: {cross_scene}")

print("emu_hires_sampled_cross_scene_review_contract: PASS")
PY
