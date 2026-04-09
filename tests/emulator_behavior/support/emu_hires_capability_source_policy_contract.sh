#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/tools/scenarios/lib/common.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

BUNDLE_DIR="$TMPDIR/bundle"
mkdir -p "$BUNDLE_DIR/logs"
cat > "$BUNDLE_DIR/logs/retroarch.log" <<'EOF'
[INFO] Hi-res capability check: descriptor_indexing=1 runtime_descriptor_array=1 sampled_image_array_non_uniform_indexing=1 descriptor_binding_variable_descriptor_count=1 descriptor_binding_partially_bound=1 descriptor_binding_update_after_bind=1 maxDescriptorSetUpdateAfterBindSampledImages=8388606 cache_path=/tmp/example/package.phrb source_mode=auto.
[INFO] Hi-res replacement cache loaded: 12 entries from /tmp/example/package.phrb (source mode auto)
[INFO] Hi-res keying summary: lookups=1 hits=1 misses=0 provider=on entries=12 native_sampled=1 compat=11 sampled_index=1 sampled_dupe_keys=0 sampled_dupe_entries=0 sampled_families=1 compat_low32_families=11 sources(phrb=12 hts=0 htc=0) descriptor_paths(sampled=1 native_checksum=0 generic=0 compat=0) sampled_detail(family_singleton=1 ordered_surface_singleton=0) generic_detail(identity_assisted=0 plain=0).
EOF

OUTPUT_JSON="$TMPDIR/hires-evidence.json"
scenario_extract_hires_log_evidence "$BUNDLE_DIR" "$OUTPUT_JSON"

python3 - "$OUTPUT_JSON" <<'PY'
import json
import sys
from pathlib import Path

evidence = json.loads(Path(sys.argv[1]).read_text())
caps = evidence.get("capabilities") or {}
summary = evidence.get("summary") or {}

if caps.get("cache_path") != "/tmp/example/package.phrb":
    raise SystemExit(f"FAIL: capability cache_path polluted by source mode suffix: {caps.get('cache_path')!r}")
if evidence.get("cache_path") != "/tmp/example/package.phrb":
    raise SystemExit(f"FAIL: top-level cache_path polluted by source mode suffix: {evidence.get('cache_path')!r}")
if evidence.get("source_policy") != "auto":
    raise SystemExit(f"FAIL: expected parsed source_policy=auto, got {evidence.get('source_policy')!r}")
if summary.get("source_policy") != "auto":
    raise SystemExit(f"FAIL: expected summary source_policy=auto, got {summary.get('source_policy')!r}")
if summary.get("source_mode") != "phrb-only":
    raise SystemExit(f"FAIL: expected summary source_mode=phrb-only, got {summary.get('source_mode')!r}")
PY

echo "emu_hires_capability_source_policy_contract: PASS"
