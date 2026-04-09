#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-review-profile-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"
BUNDLE_DIR="$TMP_DIR/bundle"
TRACE_DIR="$BUNDLE_DIR/traces"
EXPLICIT_DIR="$TMP_DIR/explicit"
PROFILE_DIR="$TMP_DIR/profile"

mkdir -p "$TRACE_DIR"

python3 - "$CACHE_PATH" "$TRACE_DIR/hires-evidence.json" "$TMP_DIR/duplicate-review.json" "$TMP_DIR/alias-group-review.json" "$TMP_DIR/review-profile.json" <<'PY'
import gzip
import json
import struct
import sys
from pathlib import Path

cache_path = Path(sys.argv[1])
evidence_path = Path(sys.argv[2])
duplicate_review_path = Path(sys.argv[3])
alias_review_path = Path(sys.argv[4])
review_profile_path = Path(sys.argv[5])

TXCACHE_FORMAT_VERSION = 0x08000000
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401
GL_RGBA8 = 0x8058

texture_crc = 0x11111111
formatsize = 258
entries = [
    (0xAAAABBBB, bytes([
        0x10, 0x20, 0x30, 0xFF,
        0x40, 0x50, 0x60, 0xFF,
        0x70, 0x80, 0x90, 0xFF,
        0xA0, 0xB0, 0xC0, 0xFF,
    ])),
    (0xCCCCDDDD, bytes([
        0x10, 0x20, 0x30, 0xFF,
        0x40, 0x50, 0x60, 0xFF,
        0x70, 0x80, 0x90, 0xFF,
        0xA0, 0xB0, 0xC0, 0xFF,
    ])),
    (0xEEEEFFFF, bytes([
        0x10, 0x20, 0x30, 0xFF,
        0x40, 0x50, 0x60, 0xFF,
        0x70, 0x80, 0x90, 0xFF,
        0xA0, 0xB0, 0xC0, 0xFF,
    ])),
]

with gzip.open(cache_path, "wb") as fp:
    fp.write(struct.pack("<i", TXCACHE_FORMAT_VERSION))
    fp.write(struct.pack("<i", 0))
    for palette_crc, payload in entries:
        checksum64 = (palette_crc << 32) | texture_crc
        fp.write(struct.pack("<Q", checksum64))
        fp.write(struct.pack("<IIIHHB", 2, 2, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, 1))
        fp.write(struct.pack("<H", formatsize))
        fp.write(struct.pack("<I", len(payload)))
        fp.write(payload)

evidence = {
    "ci_palette_probe": {
        "families": [
            {
                "low32": f"{texture_crc:08x}",
                "fs": str(formatsize),
                "mode": "loadtile",
                "wh": "2x2",
                "pcrc": f"{entries[0][0]:08x}",
                "active_pool": "exact",
            }
        ],
        "usages": [],
        "emulated_tmem": [],
    },
    "sampled_object_probe": {
        "top_groups": [
            {
                "fields": {
                    "draw_class": "texrect",
                    "cycle": "1cycle",
                    "fmt": "2",
                    "siz": "1",
                    "off": "0",
                    "stride": "2",
                    "wh": "2x2",
                    "fs": str(formatsize),
                    "sampled_low32": f"{texture_crc:08x}",
                    "sampled_entry_pcrc": f"{entries[0][0]:08x}",
                    "sampled_sparse_pcrc": f"{entries[0][0]:08x}",
                    "sampled_entry_count": "1",
                    "sampled_used_count": "1",
                },
                "upload_low32s": [
                    {"value": f"{texture_crc:08x}"}
                ],
                "upload_pcrcs": [
                    {"value": f"{entries[0][0]:08x}"}
                ],
            }
        ]
    },
}
evidence_path.write_text(json.dumps(evidence, indent=2) + "\n")

policy_key = f"legacy-low32-{texture_crc:08x}-fs{formatsize}"
kept_a = f"legacy-{texture_crc:08x}-{entries[0][0]:08x}-fs{formatsize}-2x2"
drop_b = f"legacy-{texture_crc:08x}-{entries[1][0]:08x}-fs{formatsize}-2x2"
alias_c = f"legacy-{texture_crc:08x}-{entries[2][0]:08x}-fs{formatsize}-2x2"

duplicate_review = {
    "sampled_low32": f"{texture_crc:08x}",
    "selector": "0000000000000000",
    "recommendation": "keep-runtime-winner-rule-and-defer-offline-dedupe",
    "duplicate_bucket": {
        "policy": policy_key,
        "replacement_id": kept_a,
    },
    "unique_selector_replacement_ids": [
        kept_a,
        drop_b,
    ],
}
duplicate_review_path.write_text(json.dumps(duplicate_review, indent=2) + "\n")

alias_review = {
    "sampled_low32": f"{texture_crc:08x}",
    "policy_key": policy_key,
    "recommendation": "keep-selectors-distinct-and-consider-asset-level-dedupe",
    "suggested_canonical_replacement_id": kept_a,
    "suggested_alias_replacement_ids": [alias_c],
    "unique_group_replacement_ids": [
        kept_a,
        alias_c,
    ],
    "repeated_replacement_ids": {
        kept_a: 1,
        alias_c: 1,
    },
}
alias_review_path.write_text(json.dumps(alias_review, indent=2) + "\n")

review_profile = {
    "schema_version": 1,
    "duplicate_review_paths": [duplicate_review_path.name],
    "alias_group_review_paths": [alias_review_path.name],
}
review_profile_path.write_text(json.dumps(review_profile, indent=2) + "\n")
PY

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$BUNDLE_DIR" \
  --runtime-overlay-mode never \
  --duplicate-review "$TMP_DIR/duplicate-review.json" \
  --alias-group-review "$TMP_DIR/alias-group-review.json" \
  --stdout-format json \
  --output-dir "$EXPLICIT_DIR" \
  > "$TMP_DIR/explicit-result.json"

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --bundle "$BUNDLE_DIR" \
  --runtime-overlay-mode never \
  --review-profile "$TMP_DIR/review-profile.json" \
  --stdout-format json \
  --output-dir "$PROFILE_DIR" \
  > "$TMP_DIR/profile-result.json"

python3 - "$EXPLICIT_DIR" "$PROFILE_DIR" "$TMP_DIR/explicit-result.json" "$TMP_DIR/profile-result.json" "$TMP_DIR/review-profile.json" "$TMP_DIR/duplicate-review.json" "$TMP_DIR/alias-group-review.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

explicit_dir = Path(sys.argv[1])
profile_dir = Path(sys.argv[2])
explicit_result = json.loads(Path(sys.argv[3]).read_text())
profile_result = json.loads(Path(sys.argv[4]).read_text())
review_profile_path = Path(sys.argv[5]).resolve()
duplicate_review_path = Path(sys.argv[6]).resolve()
alias_review_path = Path(sys.argv[7]).resolve()

def normalized_loader_manifest(path: Path):
    data = json.loads(path.read_text())
    data["source_imported_index_path"] = "<normalized>"
    return data

def normalized_package_manifest(path: Path):
    data = json.loads(path.read_text())
    data["source_loader_manifest_path"] = "<normalized>"
    return data

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()

if explicit_result.get("duplicate_review_change_count") != 1 or explicit_result.get("alias_group_review_change_count") != 1:
    raise SystemExit(f"FAIL: explicit review build reported unexpected review change counts {explicit_result!r}.")
if profile_result.get("duplicate_review_change_count") != 1 or profile_result.get("alias_group_review_change_count") != 1:
    raise SystemExit(f"FAIL: profile review build reported unexpected review change counts {profile_result!r}.")
if [Path(value).resolve() for value in (explicit_result.get("duplicate_review_paths") or [])] != [duplicate_review_path]:
    raise SystemExit(f"FAIL: explicit duplicate review paths mismatch {explicit_result.get('duplicate_review_paths')!r}.")
if [Path(value).resolve() for value in (explicit_result.get("alias_group_review_paths") or [])] != [alias_review_path]:
    raise SystemExit(f"FAIL: explicit alias review paths mismatch {explicit_result.get('alias_group_review_paths')!r}.")
if explicit_result.get("review_profile_paths"):
    raise SystemExit(f"FAIL: explicit build unexpectedly reported review profiles {explicit_result.get('review_profile_paths')!r}.")
if [Path(value).resolve() for value in (profile_result.get("review_profile_paths") or [])] != [review_profile_path]:
    raise SystemExit(f"FAIL: profile build review profile paths mismatch {profile_result.get('review_profile_paths')!r}.")
if [Path(value).resolve() for value in (profile_result.get("duplicate_review_paths") or [])] != [duplicate_review_path]:
    raise SystemExit(f"FAIL: profile build duplicate review paths mismatch {profile_result.get('duplicate_review_paths')!r}.")
if [Path(value).resolve() for value in (profile_result.get("alias_group_review_paths") or [])] != [alias_review_path]:
    raise SystemExit(f"FAIL: profile build alias review paths mismatch {profile_result.get('alias_group_review_paths')!r}.")

if normalized_loader_manifest(explicit_dir / "loader-manifest.json") != normalized_loader_manifest(profile_dir / "loader-manifest.json"):
    raise SystemExit("FAIL: loader-manifest differs between explicit review args and review-profile build.")
if normalized_package_manifest(explicit_dir / "package" / "package-manifest.json") != normalized_package_manifest(profile_dir / "package" / "package-manifest.json"):
    raise SystemExit("FAIL: package-manifest differs between explicit review args and review-profile build.")
if sha256(explicit_dir / "package.phrb") != sha256(profile_dir / "package.phrb"):
    raise SystemExit("FAIL: package.phrb differs between explicit review args and review-profile build.")

report = json.loads((profile_dir / "hts2phrb-report.json").read_text())
loader_manifest = json.loads((profile_dir / "loader-manifest.json").read_text())
package_manifest = json.loads((profile_dir / "package" / "package-manifest.json").read_text())
summary_text = (profile_dir / "hts2phrb-summary.md").read_text()

if report.get("runtime_overlay_built"):
    raise SystemExit(f"FAIL: expected runtime overlay to stay disabled, got {report!r}.")
if report.get("runtime_overlay_reason") != "disabled":
    raise SystemExit(f"FAIL: expected disabled runtime overlay reason, got {report.get('runtime_overlay_reason')!r}.")
if report.get("duplicate_review_change_count") != 1 or report.get("alias_group_review_change_count") != 1:
    raise SystemExit(f"FAIL: report missing review change counts {report!r}.")
if "## Review Inputs" not in summary_text:
    raise SystemExit("FAIL: summary did not include Review Inputs section.")

record = loader_manifest["records"][0]
if record.get("asset_candidate_count") != 2:
    raise SystemExit(f"FAIL: expected deduped+aliased asset_candidate_count=2, got {record!r}.")
selector_rows = [
    {
        "replacement_id": candidate.get("replacement_id"),
        "legacy_palette_crc": candidate.get("legacy_palette_crc"),
        "selector_checksum64": candidate.get("selector_checksum64"),
    }
    for candidate in (record.get("asset_candidates") or [])
]
expected_selector_rows = [
    {
        "replacement_id": "legacy-11111111-aaaabbbb-fs258-2x2",
        "legacy_palette_crc": "aaaabbbb",
        "selector_checksum64": "0000000000000000",
    },
    {
        "replacement_id": "legacy-11111111-aaaabbbb-fs258-2x2",
        "legacy_palette_crc": "aaaabbbb",
        "selector_checksum64": "0000000000000000",
    },
]
if selector_rows != expected_selector_rows:
    raise SystemExit(f"FAIL: unexpected reviewed selector rows {selector_rows!r}.")

package_record = package_manifest["records"][0]
materialized_paths = sorted({
    candidate.get("materialized_path")
    for candidate in (package_record.get("asset_candidates") or [])
})
if materialized_paths != ["assets/legacy-11111111-aaaabbbb-fs258-2x2.rgba"]:
    raise SystemExit(f"FAIL: expected single canonical materialized asset path, got {materialized_paths!r}.")

print("emu_hts2phrb_review_profile: PASS")
PY
