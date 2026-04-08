#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SURFACE_PACKAGE_INPUT="$REPO_ROOT/artifacts/hires-pack-review/20260330-1b85-sampled-surface-package/surface-package.json"
POLICY_INPUT="$REPO_ROOT/tools/hires_surface_transport_review_policy.json"

python3 "$REPO_ROOT/tools/hires_apply_surface_transport_policy.py" \
  --surface-package "$SURFACE_PACKAGE_INPUT" \
  --policy "$POLICY_INPUT" \
  --output "$TMP_DIR/reviewed-surface-package.json"

python3 - "$TMP_DIR/reviewed-surface-package.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
surfaces = data.get("surfaces") or []
if len(surfaces) != 1:
    raise SystemExit(f"FAIL: expected exactly one reviewed surface, got {len(surfaces)}.")

record = surfaces[0]
surface = record.get("surface") or {}
slots = surface.get("slots") or []
if len(slots) != 34:
    raise SystemExit(f"FAIL: expected 34 slots in reviewed surface, got {len(slots)}.")
if slots[33].get("replacement_id") != "legacy-5f6dd165-f978d303-fs0-1184x24":
    raise SystemExit(f"FAIL: unresolved tail slot was not filled: {slots[33]!r}.")
if surface.get("unresolved_sequences") != []:
    raise SystemExit(f"FAIL: unresolved sequences were not cleared: {surface.get('unresolved_sequences')!r}.")
if record.get("selector_mode") != "dual":
    raise SystemExit(f"FAIL: selector_mode was not promoted to dual: {record.get('selector_mode')!r}.")
if record.get("allow_runtime_selector_compile") is not True:
    raise SystemExit(
        f"FAIL: allow_runtime_selector_compile was not enabled: {record.get('allow_runtime_selector_compile')!r}."
    )

provenance = (record.get("provenance") or {}).get("surface_transport_policy") or {}
slot_aliases = provenance.get("slot_aliases") or {}
if len(slot_aliases.get("applied_aliases") or []) != 1:
    raise SystemExit(f"FAIL: expected one applied alias in provenance, got {slot_aliases!r}.")
selector_mode = provenance.get("selector_mode") or {}
if selector_mode.get("allow_runtime_selector_compile") is not True:
    raise SystemExit(f"FAIL: selector-mode provenance missing runtime compile flag: {selector_mode!r}.")

print("emu_hires_apply_surface_transport_policy_contract: PASS")
PY
