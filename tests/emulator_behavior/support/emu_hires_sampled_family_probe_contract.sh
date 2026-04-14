#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/logs" "$TMP_DIR/traces"

cat > "$TMP_DIR/logs/retroarch.log" <<'EOF'
Hi-res keying summary: lookups=48467 hits=0 misses=48467 filtered=0 block_probe_hits=0 provider=on entries=66 native_sampled=65 compat=1 sampled_index=65 sampled_dupe_keys=0 sampled_dupe_entries=0 sampled_families=4 compat_low32_families=1 sources(phrb=66) descriptor_paths(sampled=12 native_checksum=3 generic=4 compat=1) sampled_detail(family_singleton=2 ordered_surface_singleton=1) generic_detail(identity_assisted=3 plain=1 native=0 compat=1 unknown=0).
Hi-res keying hit: mode=triangle addr=0x001234 tile=0 fmt=4 siz=0 pal=0 wh=16x32 key=0000000091887078 pcrc=00000000 fs=4 descriptor_path=sampled resolution_reason=sampled-family-unique-upload hit=1.
Hi-res keying hit: mode=triangle addr=0x001238 tile=0 fmt=4 siz=0 pal=0 wh=16x32 key=0000000091887078 pcrc=00000000 fs=4 descriptor_path=sampled resolution_reason=sampled-family-ordered-surface-singleton-upload hit=1.
Hi-res sampled-object exact miss: reason=lookup draw_class=texrect cycle=copy tile=0 sampled_low32=1b8530fb palette_crc=52e0d253 fs=258 selector=52e0d2531b8530fb provider_enabled=1 provider_entries=66.
Hi-res sampled-object family: available=1 draw_class=texrect cycle=copy tile=0 sampled_low32=1b8530fb palette_crc=52e0d253 fs=258 selector=52e0d2531b8530fb prefer_exact_fs=1 exact_entries=33 generic_entries=0 active_entries=33 unique_checksums=33 unique_selectors=33 zero_selectors=0 matching_selectors=0 ordered_selectors=0 repl_dims=1 uniform_repl_dims=1 sample_repl=1184x24 active_is_pool=1 sample_policy=sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb-pool sample_replacement_id=legacy-1b8530fb-a sampled_object=sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb.
Hi-res sampled-object exact miss: reason=lookup draw_class=triangle cycle=2cycle tile=0 sampled_low32=91887078 palette_crc=00000000 fs=4 selector=00000000de3dac2a provider_enabled=1 provider_entries=66.
Hi-res sampled-object family: available=0 draw_class=triangle cycle=2cycle tile=0 sampled_low32=91887078 palette_crc=00000000 fs=4 selector=00000000de3dac2a.
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
probe = data.get("sampled_object_probe") or {}

def check(condition, message):
    if not condition:
        raise SystemExit(message)

check(summary.get("provider") == "on", f"unexpected summary provider: {summary}")
check(summary.get("source_mode") == "phrb-only", f"unexpected summary source mode: {summary}")
check(summary.get("entry_count") == 66, f"unexpected entry_count: {summary}")
check(summary.get("native_sampled_entry_count") == 65, f"unexpected native sampled count: {summary}")
check(summary.get("compat_entry_count") == 1, f"unexpected compat count: {summary}")
check(summary.get("sampled_index_count") == 65, f"unexpected sampled index count: {summary}")
check(summary.get("sampled_duplicate_key_count") == 0, f"unexpected sampled duplicate key count: {summary}")
check(summary.get("sampled_duplicate_entry_count") == 0, f"unexpected sampled duplicate entry count: {summary}")
check(summary.get("sampled_family_count") == 4, f"unexpected sampled family count: {summary}")
check(summary.get("compat_low32_family_count") == 1, f"unexpected compat family count: {summary}")
check((summary.get("source_counts") or {}).get("phrb") == 66, f"unexpected phrb count: {summary}")
check((summary.get("descriptor_path_counts") or {}).get("sampled") == 12, f"unexpected sampled descriptor path count: {summary}")
check((summary.get("descriptor_path_counts") or {}).get("native_checksum") == 3, f"unexpected native checksum descriptor path count: {summary}")
check((summary.get("descriptor_path_counts") or {}).get("generic") == 4, f"unexpected generic descriptor path count: {summary}")
check((summary.get("descriptor_path_counts") or {}).get("compat") == 1, f"unexpected compat descriptor path count: {summary}")
check((summary.get("descriptor_path_detail_counts") or {}).get("sampled_family_singleton") == 2, f"unexpected sampled family singleton count: {summary}")
check((summary.get("descriptor_path_detail_counts") or {}).get("sampled_ordered_surface_singleton") == 1, f"unexpected sampled ordered-surface singleton count: {summary}")
check((summary.get("descriptor_path_detail_counts") or {}).get("generic_identity_assisted") == 3, f"unexpected generic identity-assisted count: {summary}")
check((summary.get("descriptor_path_detail_counts") or {}).get("generic_plain") == 1, f"unexpected generic plain count: {summary}")
check((summary.get("descriptor_path_detail_counts") or {}).get("generic_native_plain") == 0, f"unexpected generic native-plain count: {summary}")
check((summary.get("descriptor_path_detail_counts") or {}).get("generic_compat_plain") == 1, f"unexpected generic compat-plain count: {summary}")
check((summary.get("descriptor_path_detail_counts") or {}).get("generic_unknown_plain") == 0, f"unexpected generic unknown-plain count: {summary}")
check((summary.get("resolution_reason_counts") or {}).get("sampled-family-unique-upload") == 1, f"unexpected unique resolution-reason count: {summary}")
check((summary.get("resolution_reason_counts") or {}).get("sampled-family-ordered-surface-singleton-upload") == 1, f"unexpected ordered-singleton resolution-reason count: {summary}")

check(probe.get("family_line_count") == 2, f"unexpected family line count: {probe}")
check(probe.get("unique_exact_family_bucket_count") == 2, f"unexpected family bucket count: {probe}")

buckets = probe.get("top_exact_family_buckets") or []
check(len(buckets) == 2, f"unexpected family buckets: {buckets}")

pool_bucket = next((item for item in buckets if item.get("fields", {}).get("sampled_low32") == "1b8530fb"), None)
check(pool_bucket is not None, f"missing pool bucket: {buckets}")
pool_fields = pool_bucket.get("fields", {})
check(pool_fields.get("available") == "1", f"unexpected pool availability: {pool_fields}")
check(pool_fields.get("active_is_pool") == "1", f"unexpected pool classification: {pool_fields}")
check(pool_fields.get("sample_policy") == "sampled-fmt2-siz1-off0-stride296-wh296x6-fs258-low321b8530fb-pool", f"unexpected pool policy: {pool_fields}")
check(pool_fields.get("sample_replacement_id") == "legacy-1b8530fb-a", f"unexpected pool replacement id: {pool_fields}")
check(pool_fields.get("selector") == "52e0d2531b8530fb", f"unexpected pool selector: {pool_fields}")

missing_bucket = next((item for item in buckets if item.get("fields", {}).get("sampled_low32") == "91887078"), None)
check(missing_bucket is not None, f"missing candidate-free bucket: {buckets}")
missing_fields = missing_bucket.get("fields", {})
check(missing_fields.get("available") == "0", f"unexpected missing availability: {missing_fields}")
check(missing_fields.get("selector") == "00000000de3dac2a", f"unexpected missing selector: {missing_fields}")

print("emu_hires_sampled_family_probe_contract: PASS")
PY
