#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/logs" "$TMP_DIR/traces"

{
  for i in $(seq 0 19); do
    low32=$(printf "%08x" $((0x10000000 + i)))
    printf '[INFO]: Hi-res sampled-object probe: draw_class=triangle cycle=2cycle tile=0 fmt=4 siz=0 pal=0 off=0 stride=8 wh=16x32 upload_low32=%s upload_pcrc=00000000 sampled_low32=%s sampled_entry_pcrc=00000000 sampled_sparse_pcrc=00000000 sampled_entry_count=0 sampled_used_count=0 fs=4 entry_hit=0 sparse_hit=0 family=0 unique_repl_dims=0 sample_repl=0x0.\n' "$low32" "$low32"
  done
  for _ in $(seq 1 5); do
    printf '[INFO]: Hi-res sampled-object probe: draw_class=triangle cycle=2cycle tile=0 fmt=0 siz=3 pal=0 off=0 stride=64 wh=32x32 upload_low32=1d27afb6 upload_pcrc=00000000 sampled_low32=6af0d9ca sampled_entry_pcrc=00000000 sampled_sparse_pcrc=00000000 sampled_entry_count=0 sampled_used_count=0 fs=768 entry_hit=0 sparse_hit=0 family=0 unique_repl_dims=0 sample_repl=0x0.\n'
  done
} > "$TMP_DIR/logs/retroarch.log"

# shellcheck disable=SC1091
source "$REPO_ROOT/tools/scenarios/lib/common.sh"
scenario_extract_hires_log_evidence "$TMP_DIR" "$TMP_DIR/traces/hires-evidence.json"

python3 - "$TMP_DIR/traces/hires-evidence.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
probe = data.get("sampled_object_probe") or {}
groups = probe.get("groups") or []
top_groups = probe.get("top_groups") or []

def check(condition, message):
    if not condition:
        raise SystemExit(message)

check(probe.get("unique_group_count") == 21, f"unexpected unique group count: {probe}")
check(len(groups) == 20, f"unexpected stored group count: {len(groups)}")
check(top_groups, f"missing top groups: {probe}")
check(top_groups[0].get("fields", {}).get("sampled_low32") == "6af0d9ca", f"unexpected top group ordering: {top_groups[:1]}")
check(any(group.get("sampled_low32") == "6af0d9ca" for group in groups), f"hot family missing from groups: {groups}")
check(not any(group.get("sampled_low32") == "10000013" for group in groups), f"lowest-ranked tie group should have been trimmed from groups: {groups}")

print("emu_hires_sampled_group_capture_contract: PASS")
PY
