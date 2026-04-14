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
[INFO] Hi-res capability check: descriptor_indexing=1 runtime_descriptor_array=1 sampled_image_array_non_uniform_indexing=1 descriptor_binding_variable_descriptor_count=1 descriptor_binding_partially_bound=1 descriptor_binding_update_after_bind=1 maxDescriptorSetUpdateAfterBindSampledImages=8388606 cache_path=/tmp/example/legacy.hts source_mode=mixed.
[INFO] Hi-res replacement cache loaded: 12 entries from /tmp/example/legacy.hts (source mode mixed)
[INFO] Hi-res keying summary: lookups=5 hits=3 misses=2 provider=on entries=12 native_sampled=8 compat=4 sampled_index=8 sampled_dupe_keys=0 sampled_dupe_entries=0 sampled_families=2 compat_low32_families=1 sources(phrb=5 hts=6 htc=1) descriptor_paths(sampled=1 native_checksum=1 generic=0 compat=1) sampled_detail(family_singleton=1 ordered_surface_singleton=0) generic_detail(identity_assisted=0 plain=0).
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

if caps.get("cache_path") != "/tmp/example/legacy.hts":
    raise SystemExit(f"FAIL: capability cache_path parse mismatch: {caps.get('cache_path')!r}")
if evidence.get("cache_path") != "/tmp/example/legacy.hts":
    raise SystemExit(f"FAIL: top-level cache_path parse mismatch: {evidence.get('cache_path')!r}")
if not evidence.get("cache_loaded"):
    raise SystemExit(f"FAIL: cache_loaded should be true for legacy evidence: {evidence!r}")
if summary.get("source_mode") != "mixed":
    raise SystemExit(f"FAIL: expected summary source_mode=mixed, got {summary.get('source_mode')!r}")
source_counts = summary.get("source_counts") or {}
if source_counts.get("phrb") != 5 or source_counts.get("hts") != 6 or source_counts.get("htc") != 1:
    raise SystemExit(f"FAIL: legacy source counts parse mismatch: {source_counts!r}")
if "source_policy" in evidence:
    raise SystemExit(f"FAIL: stale source_policy should not be parsed into evidence: {evidence.get('source_policy')!r}")
if "source_policy" in summary:
    raise SystemExit(f"FAIL: stale source_policy should not be synthesized into summary: {summary.get('source_policy')!r}")
PY

echo "emu_hires_legacy_evidence_bundle_contract: PASS"
