#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BINDINGS_INPUT="$REPO_ROOT/artifacts/hires-pack-review/20260330-selected-plus-timeout-960-v1-add-1b85/bindings.json"
SURFACE_PACKAGE_INPUT="$REPO_ROOT/artifacts/hires-pack-review/20260330-1b85-sampled-surface-package/surface-package.json"
SURFACE_POLICY_INPUT="$REPO_ROOT/tools/hires_surface_transport_review_policy.json"
POLICY_INPUT="$REPO_ROOT/tools/hires_pack_transport_policy.json"
REFERENCE_PACKAGE="$REPO_ROOT/artifacts/hires-pack-review/20260407-selected-plus-timeout-960-v1-1b85-tail-slot-review/package.phrb"

(
  cd "$REPO_ROOT"
  python3 "$REPO_ROOT/tools/hires_pack_build_selected_package.py" \
    --bindings-input "$BINDINGS_INPUT" \
    --surface-package-input "$SURFACE_PACKAGE_INPUT" \
    --surface-transport-policy "$SURFACE_POLICY_INPUT" \
    --policy "$POLICY_INPUT" \
    --output-dir "$TMP_DIR/output" > "$TMP_DIR/build-result.json"
)

python3 - "$TMP_DIR/output/bindings.json" "$TMP_DIR/output/package.phrb" "$TMP_DIR/build-result.json" "$REFERENCE_PACKAGE" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

bindings = json.loads(Path(sys.argv[1]).read_text())
binary_path = Path(sys.argv[2])
result = json.loads(Path(sys.argv[3]).read_text())
reference_package = Path(sys.argv[4])

surface_binding = None
for binding in bindings.get("bindings") or []:
    if binding.get("policy_key") == "surface-1b8530fb":
        surface_binding = binding
        break
if surface_binding is None:
    raise SystemExit("FAIL: missing surface-1b8530fb binding in builder output.")

if surface_binding.get("selector_mode") != "dual":
    raise SystemExit(f"FAIL: expected dual selector mode, got {surface_binding.get('selector_mode')!r}.")
if len(surface_binding.get("surface_slots") or []) != 34:
    raise SystemExit(f"FAIL: expected 34 surface slots, got {surface_binding!r}.")
if len(surface_binding.get("transport_candidates") or []) != 68:
    raise SystemExit(f"FAIL: expected 68 surface transport candidates, got {surface_binding!r}.")

reviewed_paths = result.get("reviewed_surface_package_paths") or []
if len(reviewed_paths) != 1:
    raise SystemExit(f"FAIL: expected one reviewed surface package path, got {result!r}.")
reviewed_surface = json.loads(Path(reviewed_paths[0]).read_text())
reviewed_record = reviewed_surface.get("surfaces", [])[0]
if reviewed_record.get("allow_runtime_selector_compile") is not True:
    raise SystemExit(f"FAIL: reviewed surface package missing runtime compile flag: {reviewed_record!r}.")

built_hash = hashlib.sha256(binary_path.read_bytes()).hexdigest()
reference_hash = hashlib.sha256(reference_package.read_bytes()).hexdigest()
if built_hash != reference_hash:
    raise SystemExit(
        f"FAIL: expected builder surface-policy package to match reference hash {reference_hash}, got {built_hash}."
    )

print("emu_hires_pack_build_selected_package_surface_transport_policy_contract: PASS")
PY
