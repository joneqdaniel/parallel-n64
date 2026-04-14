#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
RENDERER="$REPO_ROOT/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_renderer.cpp"

python3 - "$RENDERER" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text()

draw_gate = re.search(
    r"if \(!replacement_tiles\[base_tile\]\.hit &&.*?"
    r"hires_rdram_load_addr\[base_tile\] != 0\)\s*\{",
    source,
    re.S,
)
if not draw_gate:
    raise SystemExit("FAIL: could not locate draw-time compat gate in rdp_renderer.cpp")

if "base_meta.stride != 0" in draw_gate.group(0):
    raise SystemExit("FAIL: zero-line compat path is still gated on base_meta.stride != 0")

fallback = re.search(
    r"if \(bpl == 0\)\s*\{\s*"
    r"// Fallback: compute stride from tile dimensions \(matches GlideN64 for zero-line tiles\)\s*"
    r"uint32_t computed_bpl = detail::compute_hires_texture_row_bytes\(tile_width, meta\.size\);\s*"
    r"if \(computed_bpl == 0\)\s*return 0;\s*"
    r"bpl = computed_bpl;\s*"
    r"\}",
    source,
    re.S,
)
if not fallback:
    raise SystemExit("FAIL: missing zero-line stride fallback in compute_gliden64_compat_checksum64()")

print("emu_rdp_hires_zero_line_compat_gate_contract: PASS")
PY
