#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bundle/logs" "$TMP_DIR/bundle/traces"

python3 - "$TMP_DIR" <<'PY'
import json
import sys
from pathlib import Path

tmp_dir = Path(sys.argv[1])

selector_review = {
    "pool_families": [
        {
            "sampled_low32": "1b8530fb",
            "draw_class": "texrect",
            "cycle": "copy",
            "fs": "258",
            "pool_recommendation": "defer-runtime-pool-semantics",
            "runtime_sample_policy": "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb-pool",
            "runtime_sample_replacement_id": "legacy-1b8530fb-a",
            "runtime_sampled_object": "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb",
            "runtime_sample_repl": "1184x24",
            "pool_matching_runtime_selector_count": 0,
            "selectors": [
                {"selector": "52e0d2531b8530fb", "count": 14},
            ],
        }
    ]
}
transport_review = {
    "groups": [
        {
            "signature": {
                "draw_class": "texrect",
                "cycle": "copy",
                "sampled_low32": "1b8530fb",
                "sampled_entry_pcrc": "98bb9d8e",
                "sampled_sparse_pcrc": "52e0d253",
                "formatsize": 258,
                "replacement_dims": "1184x24",
            },
            "transport_candidates": [
                {
                    "replacement_id": "legacy-k0",
                    "checksum64": "05556c97b0f2a1dd",
                    "texture_crc": "b0f2a1dd",
                    "palette_crc": "05556c97",
                    "formatsize": 258,
                    "width": 1184,
                    "height": 24,
                    "data_size": 16,
                    "pixel_sha256": "a" * 64,
                },
                {
                    "replacement_id": "legacy-k1",
                    "checksum64": "05556c9778538e1e",
                    "texture_crc": "78538e1e",
                    "palette_crc": "05556c97",
                    "formatsize": 258,
                    "width": 1184,
                    "height": 24,
                    "data_size": 16,
                    "pixel_sha256": "b" * 64,
                },
                {
                    "replacement_id": "legacy-k2",
                    "checksum64": "bcd3f9be959b49bf",
                    "texture_crc": "959b49bf",
                    "palette_crc": "bcd3f9be",
                    "formatsize": 258,
                    "width": 1184,
                    "height": 24,
                    "data_size": 16,
                    "pixel_sha256": "c" * 64,
                },
                {
                    "replacement_id": "legacy-k3",
                    "checksum64": "9afc43ab038a968c",
                    "texture_crc": "038a968c",
                    "palette_crc": "9afc43ab",
                    "formatsize": 258,
                    "width": 1184,
                    "height": 24,
                    "data_size": 16,
                    "pixel_sha256": "d" * 64,
                },
            ],
        },
        {
            "signature": {
                "draw_class": "texrect",
                "cycle": "copy",
                "sampled_low32": "1b8530fb",
                "sampled_entry_pcrc": "98bb9d8e",
                "sampled_sparse_pcrc": "52e0d253",
                "formatsize": 258,
                "replacement_dims": "0x0",
            },
            "probe_event_count": 1,
            "transport_candidates": [],
        },
    ]
}

(tmp_dir / "selector-review.json").write_text(json.dumps(selector_review, indent=2) + "\n")
(tmp_dir / "transport-review.json").write_text(json.dumps(transport_review, indent=2) + "\n")

keys = [
    "05556c97b0f2a1dd",
    "05556c9778538e1e",
    "bcd3f9be959b49bf",
    "9afc43ab038a968c",
    "77e5f3760b110a9b",
    "05556c97b0f2a1dd",
    "05556c9778538e1e",
    "bcd3f9be959b49bf",
    "9afc43ab038a968c",
    "77e5f3760b110a9b",
    "05556c97b0f2a1dd",
    "05556c9778538e1e",
    "bcd3f9be959b49bf",
    "9afc43ab038a968c",
    "77e5f3760b110a9b",
    "77e5f3760b110a9b",
    "77e5f3760b110a9b",
    "77e5f3760b110a9b",
]
lines = []
for key in keys:
    lines.append(
        "Hi-res draw usage: "
        "draw_class=texrect cycle=copy copy=1 base_tile=0 uses_texel0=1 uses_texel1=1 "
        "texel0_hit=1 texel0_key=52e0d2531b8530fb texel0_fs=258 texel0_w=296 texel0_h=6 "
        f"texel1_tile=1 texel1_hit=0 texel1_key={key} texel1_fs=258 texel1_w=1184 texel1_h=24 "
        "fmt=2 siz=1 pal=0 offset=0 stride=296 sl=0 tl=0 sh=1183 th=23 "
        "mask_s=0 shift_s=0 mask_t=0 shift_t=0 clamp_s=0 mirror_s=0 clamp_t=0 mirror_t=0.\n"
    )
(tmp_dir / "bundle" / "logs" / "retroarch.log").write_text("".join(lines))
PY

python3 "$REPO_ROOT/tools/hires_sampled_pool_review.py" \
  --bundle-dir "$TMP_DIR/bundle" \
  --selector-review "$TMP_DIR/selector-review.json" \
  --transport-review "$TMP_DIR/transport-review.json" \
  --sampled-low32 "1b8530fb" \
  --output "$TMP_DIR/pool-review.md" \
  --output-json "$TMP_DIR/pool-review.json"

python3 - "$TMP_DIR/pool-review.json" "$TMP_DIR/pool-review.md" <<'PY'
import json
import sys
from pathlib import Path

review = json.loads(Path(sys.argv[1]).read_text())
markdown = Path(sys.argv[2]).read_text()

def check(condition, message):
    if not condition:
        raise SystemExit(message)

check(review.get("sampled_low32") == "1b8530fb", f"unexpected sampled_low32: {review}")
check(review.get("pool_recommendation") == "defer-runtime-pool-semantics", f"unexpected pool recommendation: {review}")
check(review.get("runtime_shape_recommendation") == "keep-flat-runtime-binding", f"unexpected runtime shape recommendation: {review}")
check(review.get("runtime_sample_replacement_id") == "legacy-1b8530fb-a", f"unexpected runtime sample replacement id: {review}")
check(review.get("runtime_sample_repl") == "1184x24", f"unexpected runtime sample repl: {review}")
check((review.get("transport_group_signature") or {}).get("replacement_dims") == "1184x24", f"unexpected transport group selection: {review}")

sequence = review.get("sequence_summary") or {}
check(sequence.get("shape_hint") == "rotating-stream-edge-dwell", f"unexpected sequence summary: {sequence}")
check(sequence.get("dominant_delta") == 1, f"unexpected dominant delta: {sequence}")

surface_map = review.get("surface_map_summary") or {}
check(surface_map.get("slot_count") == 5, f"unexpected slot count: {surface_map}")
check(surface_map.get("mapped_candidate_count") == 4, f"unexpected mapped count: {surface_map}")
check(surface_map.get("unresolved_count") == 1, f"unexpected unresolved count: {surface_map}")
check(surface_map.get("candidate_count") == 4, f"unexpected candidate count: {surface_map}")

edge_review = review.get("edge_review") or {}
check(edge_review.get("edge_only") is True, f"unexpected edge review: {edge_review}")
check(edge_review.get("unresolved_count") == 1, f"unexpected edge review count: {edge_review}")

tail_dwell = review.get("tail_dwell") or {}
check(tail_dwell.get("present") is True, f"unexpected tail dwell: {tail_dwell}")
check(tail_dwell.get("aligns_with_unresolved_slot") is True, f"unexpected tail dwell alignment: {tail_dwell}")
check(tail_dwell.get("position_class") == "right-edge", f"unexpected tail dwell class: {tail_dwell}")
check(tail_dwell.get("run_length") == 4, f"unexpected tail dwell length: {tail_dwell}")

check("runtime_shape_recommendation: `keep-flat-runtime-binding`" in markdown, "markdown missing runtime recommendation")
check("runtime_sample_replacement_id: `legacy-1b8530fb-a`" in markdown, "markdown missing runtime replacement id")
check("shape_hint: `rotating-stream-edge-dwell`" in markdown, "markdown missing shape hint")
print("emu_hires_sampled_pool_review_contract: PASS")
PY

: > "$TMP_DIR/bundle/logs/retroarch.log"

python3 "$REPO_ROOT/tools/hires_sampled_pool_review.py" \
  --bundle-dir "$TMP_DIR/bundle" \
  --selector-review "$TMP_DIR/selector-review.json" \
  --transport-review "$TMP_DIR/transport-review.json" \
  --sampled-low32 "1b8530fb" \
  --allow-missing-draw-sequence \
  --output "$TMP_DIR/pool-review-deferred.md" \
  --output-json "$TMP_DIR/pool-review-deferred.json"

python3 - "$TMP_DIR/pool-review-deferred.json" "$TMP_DIR/pool-review-deferred.md" <<'PY'
import json
import sys
from pathlib import Path

review = json.loads(Path(sys.argv[1]).read_text())
markdown = Path(sys.argv[2]).read_text()

def check(condition, message):
    if not condition:
        raise SystemExit(message)

check(review.get("review_status") == "deferred-no-live-draw-sequence", f"unexpected deferred review status: {review}")
check(review.get("pool_recommendation") == "defer-runtime-pool-semantics", f"unexpected deferred pool recommendation: {review}")
check(review.get("runtime_shape_recommendation") is None, f"unexpected deferred runtime shape recommendation: {review}")
check(review.get("runtime_sample_replacement_id") == "legacy-1b8530fb-a", f"unexpected deferred runtime sample replacement id: {review}")
reasons = review.get("recommendation_reasons") or []
check("defer-to-historical-pool-regression-review" in reasons, f"unexpected deferred reasons: {review}")
check("review_status: `deferred-no-live-draw-sequence`" in markdown, "markdown missing deferred review status")
check("use the historical pool-regression review as the controlling runtime-shape evidence for now" in markdown, "markdown missing deferred explanation")
print("emu_hires_sampled_pool_review_contract: PASS (deferred)")
PY
