#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"

python3 - "$REPO_ROOT/tools/hires_block_family_probe.py" <<'PY'
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
sys.path.insert(0, str(module_path.parent))
spec = importlib.util.spec_from_file_location("hires_block_family_probe", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def check(condition, message):
    if not condition:
        raise SystemExit(message)

case_no_simple = module.classify_report(
    {"mode": "block"},
    [],
    [],
)
check(case_no_simple["recommended_outcome"] == "no-simple-loadblock-retry",
      f"unexpected no-simple outcome: {case_no_simple}")

case_native = module.classify_report(
    {"mode": "block"},
    [{
        "exact_surface_family_entry_count": 2,
        "reinterpretation_hits": [],
    }],
    [],
)
check(case_native["recommended_outcome"] == "candidate-native-surface",
      f"unexpected native outcome: {case_native}")

case_retry = module.classify_report(
    {"mode": "block"},
    [{
        "exact_surface_family_entry_count": 0,
        "reinterpretation_hits": [{"family_entry_count": 1}],
    }],
    [],
)
check(case_retry["recommended_outcome"] == "candidate-compat-retry",
      f"unexpected compat outcome: {case_retry}")

print("emu_hires_block_family_probe_contract: PASS")
PY
