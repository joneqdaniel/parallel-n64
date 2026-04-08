#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/logs" "$TMP_DIR/traces"

cat > "$TMP_DIR/logs/retroarch.log" <<'EOF'
Hi-res sampled pool stream: draw_class=texrect cycle=copy tile=0 sampled_low32=1b8530fb palette_crc=52e0d253 fs=258 selector=52e0d2531b8530fb observed_selector=05556c97b0f2a1dd observed_selector_source=texel1 observed_count=1 unique_observed_selectors=1 transition_count=0 repeat_count=0 current_run=1 max_run=1 active_entries=33 runtime_unique_selectors=33 ordered_selectors=0 sample_policy=sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb-pool sample_replacement_id=legacy-1b8530fb-a sampled_object=sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb.
Hi-res sampled pool stream: draw_class=texrect cycle=copy tile=0 sampled_low32=1b8530fb palette_crc=52e0d253 fs=258 selector=52e0d2531b8530fb observed_selector=05556c97b0f2a1dd observed_selector_source=texel1 observed_count=2 unique_observed_selectors=1 transition_count=0 repeat_count=1 current_run=2 max_run=2 active_entries=33 runtime_unique_selectors=33 ordered_selectors=0 sample_policy=sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb-pool sample_replacement_id=legacy-1b8530fb-a sampled_object=sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb.
Hi-res sampled pool stream: draw_class=texrect cycle=copy tile=0 sampled_low32=1b8530fb palette_crc=52e0d253 fs=258 selector=52e0d2531b8530fb observed_selector=05556c9778538e1e observed_selector_source=texel1 observed_count=3 unique_observed_selectors=2 transition_count=1 repeat_count=1 current_run=1 max_run=2 active_entries=33 runtime_unique_selectors=33 ordered_selectors=0 sample_policy=sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb-pool sample_replacement_id=legacy-1b8530fb-a sampled_object=sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb.
EOF

# shellcheck disable=SC1091
source "$REPO_ROOT/tools/scenarios/lib/common.sh"
scenario_extract_hires_log_evidence "$TMP_DIR" "$TMP_DIR/traces/hires-evidence.json"

python3 - "$TMP_DIR/traces/hires-evidence.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())
probe = data.get("sampled_pool_stream_probe") or {}

def check(condition, message):
    if not condition:
        raise SystemExit(message)

check(probe.get("available") is True, f"probe unavailable: {probe}")
check(probe.get("line_count") == 3, f"unexpected line count: {probe}")
check(probe.get("unique_bucket_count") == 2, f"unexpected bucket count: {probe}")
check(probe.get("family_count") == 1, f"unexpected family count: {probe}")

buckets = probe.get("top_buckets") or []
check(len(buckets) == 2, f"unexpected buckets: {buckets}")
top_bucket = buckets[0].get("fields") or {}
check(top_bucket.get("observed_selector") == "05556c97b0f2a1dd", f"unexpected top bucket selector: {top_bucket}")

family = (probe.get("top_families") or [None])[0]
check(family is not None, f"missing family rollup: {probe}")
family_fields = family.get("fields") or {}
check(family_fields.get("sampled_low32") == "1b8530fb", f"unexpected family low32: {family_fields}")
check(family_fields.get("observed_count") == "3", f"unexpected observed count: {family_fields}")
check(family_fields.get("unique_observed_selectors") == "2", f"unexpected unique selector count: {family_fields}")
check(family_fields.get("transition_count") == "1", f"unexpected transition count: {family_fields}")
check(family_fields.get("repeat_count") == "1", f"unexpected repeat count: {family_fields}")
check(family_fields.get("current_run") == "1", f"unexpected current run: {family_fields}")
check(family_fields.get("max_run") == "2", f"unexpected max run: {family_fields}")
check(family_fields.get("observed_selector") == "05556c9778538e1e", f"unexpected latest selector: {family_fields}")
check(family_fields.get("observed_selector_source") == "texel1", f"unexpected selector source: {family_fields}")
print("emu_hires_sampled_pool_stream_probe_contract: PASS")
PY
