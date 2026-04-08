#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/logs" "$TMP_DIR/traces"

cat > "$TMP_DIR/logs/retroarch.log" <<'EOF'
Hi-res keying summary: lookups=48467 hits=0 misses=48467 filtered=0 block_probe_hits=0 provider=on entries=195 native_sampled=195 compat=0 sampled_index=194 sampled_dupe_keys=1 sampled_dupe_entries=1 sampled_families=10 compat_low32_families=0 sources(phrb=195 hts=0 htc=0) descriptor_paths(sampled=20 native_checksum=5 generic=0 compat=0).
Hi-res sampled duplicate: sampled_fmt=0 sampled_siz=3 tex_offset=0 stride=400 wh=200x2 sampled_low32=7701ac09 palette_crc=00000000 fs=768 selector=0000000071c71cdd total_entries=2 duplicate_entries=1 active_checksum=000000007701ac09 repl=1600x16 policy=surface-7701ac09 replacement_id=legacy-844144ad-00000000-fs0-1600x16 sampled_object=sampled-fmt0-siz3-off0-stride400-wh200x2-fs768-low327701ac09 source=/tmp/package.phrb#surface-7701ac09.
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
summary = data.get("summary") or {}
probe = data.get("sampled_duplicate_probe") or {}

def check(condition, message):
    if not condition:
        raise SystemExit(message)

check(summary.get("sampled_duplicate_key_count") == 1, f"unexpected sampled duplicate key count: {summary}")
check(summary.get("sampled_duplicate_entry_count") == 1, f"unexpected sampled duplicate entry count: {summary}")
check((summary.get("descriptor_path_counts") or {}).get("sampled") == 20, f"unexpected sampled descriptor path count: {summary}")
check((summary.get("descriptor_path_counts") or {}).get("native_checksum") == 5, f"unexpected native checksum descriptor path count: {summary}")
check((summary.get("descriptor_path_counts") or {}).get("generic") == 0, f"unexpected generic descriptor path count: {summary}")
check((summary.get("descriptor_path_counts") or {}).get("compat") == 0, f"unexpected compat descriptor path count: {summary}")
check(probe.get("available") is True, f"duplicate probe should be available: {probe}")
check(probe.get("line_count") == 1, f"unexpected duplicate probe line count: {probe}")
check(probe.get("unique_bucket_count") == 1, f"unexpected duplicate probe bucket count: {probe}")

bucket = (probe.get("top_buckets") or [None])[0]
check(bucket is not None, f"duplicate probe should expose one bucket: {probe}")
fields = bucket.get("fields") or {}
check(fields.get("sampled_low32") == "7701ac09", f"unexpected duplicate low32: {fields}")
check(fields.get("palette_crc") == "00000000", f"unexpected duplicate palette crc: {fields}")
check(fields.get("fs") == "768", f"unexpected duplicate formatsize: {fields}")
check(fields.get("selector") == "0000000071c71cdd", f"unexpected duplicate selector: {fields}")
check(fields.get("total_entries") == "2", f"unexpected duplicate total entries: {fields}")
check(fields.get("duplicate_entries") == "1", f"unexpected duplicate extra entries: {fields}")
check(fields.get("policy") == "surface-7701ac09", f"unexpected duplicate active policy: {fields}")
check(fields.get("replacement_id") == "legacy-844144ad-00000000-fs0-1600x16", f"unexpected duplicate replacement id: {fields}")

print("emu_hires_sampled_duplicate_probe_contract: PASS")
PY
