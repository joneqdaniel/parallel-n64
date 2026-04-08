#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BINDINGS_INPUT="$REPO_ROOT/artifacts/hires-pack-review/20260330-selected-plus-timeout-960-v1-add-1b85/bindings.json"
POLICY_INPUT="$REPO_ROOT/tools/hires_pack_transport_policy.json"
REVIEW_PROFILE_INPUT="$REPO_ROOT/tools/hires_selected_package_review_profile.json"
DUPLICATE_REVIEW_INPUT="$REPO_ROOT/artifacts/paper-mario-probes/validation/20260407-selected-package-duplicate-review/on/timeout-960/traces/hires-sampled-duplicate-review-7701ac09.json"
ALIAS_GROUP_REVIEW_INPUT="$REPO_ROOT/artifacts/hires-pack-review/20260407-selected-plus-timeout-960-v1-dedupe-7701ac09-alias-group-review/review.json"

(
  cd "$REPO_ROOT"
  python3 "$REPO_ROOT/tools/hires_pack_build_selected_package.py" \
    --bindings-input "$BINDINGS_INPUT" \
    --duplicate-review "$DUPLICATE_REVIEW_INPUT" \
    --alias-group-review "$ALIAS_GROUP_REVIEW_INPUT" \
    --policy "$POLICY_INPUT" \
    --output-dir "$TMP_DIR/explicit" \
    > "$TMP_DIR/explicit-result.json"

  python3 "$REPO_ROOT/tools/hires_pack_build_selected_package.py" \
    --bindings-input "$BINDINGS_INPUT" \
    --review-profile "$REVIEW_PROFILE_INPUT" \
    --policy "$POLICY_INPUT" \
    --output-dir "$TMP_DIR/profile" \
    > "$TMP_DIR/profile-result.json"
)

python3 - "$TMP_DIR/explicit" "$TMP_DIR/profile" "$TMP_DIR/profile-result.json" "$REVIEW_PROFILE_INPUT" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

explicit_dir = Path(sys.argv[1])
profile_dir = Path(sys.argv[2])
profile_result_path = Path(sys.argv[3])
review_profile_path = Path(sys.argv[4]).resolve()

profile_result = json.loads(profile_result_path.read_text())
review_profile_paths = [Path(value).resolve() for value in profile_result.get("review_profile_paths") or []]
if review_profile_paths != [review_profile_path]:
    raise SystemExit(f"FAIL: builder did not report the expected review profile path: {review_profile_paths!r}")

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()

explicit_loader_manifest = json.loads((explicit_dir / "loader-manifest.json").read_text())
profile_loader_manifest = json.loads((profile_dir / "loader-manifest.json").read_text())
explicit_loader_manifest["source_bindings_path"] = "<normalized>"
profile_loader_manifest["source_bindings_path"] = "<normalized>"
if explicit_loader_manifest != profile_loader_manifest:
    raise SystemExit("FAIL: normalized loader-manifest differs between explicit review args and review-profile build.")

explicit_package_manifest = json.loads((explicit_dir / "package/package-manifest.json").read_text())
profile_package_manifest = json.loads((profile_dir / "package/package-manifest.json").read_text())
explicit_package_manifest["source_loader_manifest_path"] = "<normalized>"
profile_package_manifest["source_loader_manifest_path"] = "<normalized>"
if explicit_package_manifest != profile_package_manifest:
    raise SystemExit("FAIL: normalized package-manifest differs between explicit review args and review-profile build.")

explicit_hash = sha256(explicit_dir / "package.phrb")
profile_hash = sha256(profile_dir / "package.phrb")
if explicit_hash != profile_hash:
    raise SystemExit(
        f"FAIL: package.phrb differs between explicit review args and review-profile build: "
        f"{explicit_hash} != {profile_hash}"
    )

package_manifest = json.loads((profile_dir / "package/package-manifest.json").read_text())
record = None
for candidate_record in package_manifest.get("records") or []:
    canonical_identity = candidate_record.get("canonical_identity") or {}
    if str(canonical_identity.get("sampled_low32") or "").lower() == "7701ac09":
        record = candidate_record
        break
if record is None:
    raise SystemExit("FAIL: missing sampled_low32=7701ac09 package-manifest record in review-profile build.")

materialized_paths = sorted({
    candidate.get("materialized_path")
    for candidate in (record.get("asset_candidates") or [])
    if str(candidate.get("selector_checksum64") or "").lower() in {
        "000000002cf87740",
        "0000000071c71cdd",
        "00000000844144ad",
        "00000000e0dc03d0",
    }
})
if materialized_paths != ["assets/legacy-844144ad-00000000-fs0-1600x16.png"]:
    raise SystemExit(f"FAIL: expected canonical materialized asset path in review-profile build, got {materialized_paths!r}.")

print("emu_hires_pack_build_selected_package_review_profile_contract: PASS")
PY
