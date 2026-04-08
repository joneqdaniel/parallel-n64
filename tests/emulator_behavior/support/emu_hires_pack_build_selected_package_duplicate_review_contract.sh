#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BINDINGS_INPUT="$REPO_ROOT/artifacts/hires-pack-review/20260330-selected-plus-timeout-960-v1-add-1b85/bindings.json"
POLICY_INPUT="$REPO_ROOT/tools/hires_pack_transport_policy.json"
DUPLICATE_REVIEW_INPUT="$REPO_ROOT/artifacts/paper-mario-probes/validation/20260407-selected-package-duplicate-review/on/timeout-960/traces/hires-sampled-duplicate-review-7701ac09.json"

(
  cd "$REPO_ROOT"
  python3 "$REPO_ROOT/tools/hires_pack_build_selected_package.py" \
    --bindings-input "$BINDINGS_INPUT" \
    --duplicate-review "$DUPLICATE_REVIEW_INPUT" \
    --policy "$POLICY_INPUT" \
    --output-dir "$TMP_DIR/output"
)

python3 - "$TMP_DIR/output/loader-manifest.json" "$TMP_DIR/output/package/package-manifest.json" "$TMP_DIR/output/package.phrb" <<'PY'
import json
import sys
from pathlib import Path

loader_manifest = json.loads(Path(sys.argv[1]).read_text())
package_manifest = json.loads(Path(sys.argv[2]).read_text())
binary_path = Path(sys.argv[3])

record = None
for candidate_record in loader_manifest.get("records") or []:
    canonical_identity = candidate_record.get("canonical_identity") or {}
    if str(canonical_identity.get("sampled_low32") or "").lower() == "7701ac09":
        record = candidate_record
        break
if record is None:
    raise SystemExit("FAIL: missing sampled_low32=7701ac09 loader-manifest record.")

if int(record.get("asset_candidate_count") or -1) != 54:
    raise SystemExit(f"FAIL: unexpected deduped asset_candidate_count {record.get('asset_candidate_count')!r}.")

selector_rows = [
    {
        "replacement_id": candidate.get("replacement_id"),
        "selector_checksum64": candidate.get("selector_checksum64"),
    }
    for candidate in (record.get("asset_candidates") or [])
    if str(candidate.get("selector_checksum64") or "").lower() == "0000000071c71cdd"
]
if selector_rows != [
    {
        "replacement_id": "legacy-844144ad-00000000-fs0-1600x16",
        "selector_checksum64": "0000000071c71cdd",
    }
]:
    raise SystemExit(f"FAIL: unexpected deduped selector rows {selector_rows!r}.")

package_record = None
for candidate_record in package_manifest.get("records") or []:
    canonical_identity = candidate_record.get("canonical_identity") or {}
    if str(canonical_identity.get("sampled_low32") or "").lower() == "7701ac09":
        package_record = candidate_record
        break
if package_record is None:
    raise SystemExit("FAIL: missing sampled_low32=7701ac09 package-manifest record.")

if int(package_record.get("duplicate_pixel_group_count") or -1) != 1:
    raise SystemExit(
        f"FAIL: expected broader duplicate pixel group to remain after review-only dedupe, got {package_record!r}."
    )

group_ids = (package_record.get("duplicate_pixel_groups") or [{}])[0].get("replacement_ids") or []
expected_group_ids = [
    "legacy-2cf87740-00000000-fs0-1600x16",
    "legacy-844144ad-00000000-fs0-1600x16",
    "legacy-844144ad-00000000-fs0-1600x16",
    "legacy-e0dc03d0-00000000-fs0-1600x16",
]
if group_ids != expected_group_ids:
    raise SystemExit(f"FAIL: unexpected duplicate pixel group ids {group_ids!r}.")

if not binary_path.is_file() or binary_path.stat().st_size <= 0:
    raise SystemExit("FAIL: expected emitted binary package.")

print("emu_hires_pack_build_selected_package_duplicate_review_contract: PASS")
PY
