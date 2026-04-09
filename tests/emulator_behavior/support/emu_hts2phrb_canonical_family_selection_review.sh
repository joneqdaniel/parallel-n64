#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/parallel-n64-hts2phrb-family-selection-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CACHE_PATH="$TMP_DIR/sample.htc"
OUTPUT_DIR="$TMP_DIR/out"
REVIEW_PATH="$TMP_DIR/canonical-family-selection-review.json"

python3 - "$CACHE_PATH" <<'PY'
import gzip
import struct
import sys
from pathlib import Path

cache_path = Path(sys.argv[1])

TXCACHE_FORMAT_VERSION = 0x08000000
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401
GL_RGBA8 = 0x8058

texture_crc = 0x33333333
payload_2x2 = bytes([
    0x10, 0x20, 0x30, 0xFF,
    0x40, 0x50, 0x60, 0xFF,
    0x70, 0x80, 0x90, 0xFF,
    0xA0, 0xB0, 0xC0, 0xFF,
])
payload_3x3 = bytes([
    0x11, 0x21, 0x31, 0xFF, 0x12, 0x22, 0x32, 0xFF, 0x13, 0x23, 0x33, 0xFF,
    0x41, 0x51, 0x61, 0xFF, 0x42, 0x52, 0x62, 0xFF, 0x43, 0x53, 0x63, 0xFF,
    0x71, 0x81, 0x91, 0xFF, 0x72, 0x82, 0x92, 0xFF, 0x73, 0x83, 0x93, 0xFF,
])

records = [
    (0xAAAABBBB, 258, 2, 2, payload_2x2),
    (0xCCCCDDDD, 258, 3, 3, payload_3x3),
]

with gzip.open(cache_path, "wb") as fp:
    fp.write(struct.pack("<i", TXCACHE_FORMAT_VERSION))
    fp.write(struct.pack("<i", 0))
    for palette_crc, formatsize, width, height, payload in records:
        checksum64 = (palette_crc << 32) | texture_crc
        fp.write(struct.pack("<Q", checksum64))
        fp.write(struct.pack("<IIIHHB", width, height, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, 1))
        fp.write(struct.pack("<H", formatsize))
        fp.write(struct.pack("<I", len(payload)))
        fp.write(payload)
PY

cat > "$REVIEW_PATH" <<'JSON'
{
  "schema_version": 1,
  "kind": "canonical-family-selection-review",
  "selections": [
    {
      "family_key": "33333333:fs258",
      "selected_variant_group_dims": "3x3",
      "selection_reason": "review-family-selection",
      "review_group_variant_group_dims": ["2x2", "3x3"],
      "review_group_cluster_class": "same-aspect",
      "review_group_action_hint": "context-bundle-review"
    }
  ]
}
JSON

python3 "$ROOT_DIR/tools/hts2phrb.py" \
  --cache "$CACHE_PATH" \
  --all-families \
  --canonical-family-selection-review "$REVIEW_PATH" \
  --stdout-format json \
  --output-dir "$OUTPUT_DIR" \
  > "$TMP_DIR/report.json"

python3 - "$TMP_DIR/report.json" "$OUTPUT_DIR/migration-plan.json" "$REVIEW_PATH" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text())
migration = json.loads(Path(sys.argv[2]).read_text())
review_path = str(Path(sys.argv[3]).resolve())

if report["conversion_outcome"] != "promotable-runtime-package":
    raise SystemExit(f"unexpected conversion outcome: {report['conversion_outcome']!r}")
if report.get("import_state_counts") != {"exact-authority": 1}:
    raise SystemExit(f"unexpected import state counts: {report.get('import_state_counts')!r}")
if report.get("runtime_state_counts") != {"runtime-ready-package": 1}:
    raise SystemExit(f"unexpected runtime state counts: {report.get('runtime_state_counts')!r}")
if report.get("canonical_family_selection_review_paths") != [review_path]:
    raise SystemExit(
        f"unexpected canonical family selection review paths: {report.get('canonical_family_selection_review_paths')!r}"
    )
if report.get("canonical_family_selection_review_input_count") != 1:
    raise SystemExit(
        f"unexpected canonical family selection review input count: {report.get('canonical_family_selection_review_input_count')!r}"
    )
if report.get("canonical_family_selection_review_selection_count") != 1:
    raise SystemExit(
        f"unexpected canonical family selection review selection count: {report.get('canonical_family_selection_review_selection_count')!r}"
    )
if report.get("canonical_family_selection_review_family_count") != 1:
    raise SystemExit(
        f"unexpected canonical family selection review family count: {report.get('canonical_family_selection_review_family_count')!r}"
    )

imported_index = migration.get("imported_index") or {}
if imported_index.get("unresolved_families") != []:
    raise SystemExit(f"unexpected unresolved families: {imported_index.get('unresolved_families')!r}")
exact_authorities = imported_index.get("exact_authorities") or []
if len(exact_authorities) != 1:
    raise SystemExit(f"unexpected exact authority entries: {exact_authorities!r}")

family = exact_authorities[0]
selector_policy = family.get("selector_policy") or {}
if selector_policy.get("selection_reason") != "review-family-selection":
    raise SystemExit(f"unexpected selector policy: {selector_policy!r}")
if selector_policy.get("selected_variant_group_id") != "legacy-low32-33333333-fs258-3x3":
    raise SystemExit(f"unexpected selected variant group: {selector_policy!r}")
if family.get("candidate_replacement_ids") != ["legacy-33333333-ccccdddd-fs258-3x3"]:
    raise SystemExit(f"unexpected candidate replacements: {family.get('candidate_replacement_ids')!r}")

applied_policy = selector_policy.get("applied_policy") or {}
selection_override = applied_policy.get("selection_override") or {}
if selection_override.get("selected_variant_group_dims") != "3x3":
    raise SystemExit(f"unexpected applied policy selection override: {selection_override!r}")
if selection_override.get("review_source_path") != review_path:
    raise SystemExit(f"unexpected review source path: {selection_override!r}")

diagnostics = family.get("diagnostics") or {}
family_policy_selection = diagnostics.get("family_policy_selection") or {}
if family_policy_selection.get("selected_dims") != "3x3":
    raise SystemExit(f"unexpected family policy selection diagnostics: {family_policy_selection!r}")
if family_policy_selection.get("review_group_action_hint") != "context-bundle-review":
    raise SystemExit(f"unexpected family policy selection action hint: {family_policy_selection!r}")
PY

echo "emu_hts2phrb_canonical_family_selection_review: PASS"
