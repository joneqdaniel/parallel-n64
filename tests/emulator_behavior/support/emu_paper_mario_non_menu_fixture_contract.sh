#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_PATH="$REPO_ROOT/tools/fixtures/paper-mario-kmr-03-entry-5.yaml"
GRAPH_PATH="$REPO_ROOT/tools/fixtures/paper-mario-authority-graph.yaml"
RUNTIME_ENV_PATH="$REPO_ROOT/tools/scenarios/paper-mario-kmr-03-entry-5.runtime.env"
SCENARIO_PATH="$REPO_ROOT/tools/scenarios/paper-mario-kmr-03-entry-5.sh"
REMINT_PATH="$REPO_ROOT/tools/scenarios/remint-paper-mario-kmr-03-entry-5-authority.sh"

for path in "$FIXTURE_PATH" "$GRAPH_PATH" "$RUNTIME_ENV_PATH" "$SCENARIO_PATH" "$REMINT_PATH"; do
  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing required non-menu fixture file: $path" >&2
    exit 1
  fi
done

python3 - "$FIXTURE_PATH" "$GRAPH_PATH" "$RUNTIME_ENV_PATH" <<'PY'
from pathlib import Path
import sys

fixture_path = Path(sys.argv[1])
graph_path = Path(sys.argv[2])
runtime_env_path = Path(sys.argv[3])

fixture = fixture_path.read_text()
graph = graph_path.read_text()
runtime_env = runtime_env_path.read_text()

checks = [
    ("fixture id", "id: paper-mario-kmr-03-entry-5" in fixture),
    ("fixture status", "status: active" in fixture),
    ("fixture node id", "node_id: kmr_03_entry_5_idle" in fixture),
    ("fixture bootstrap parent", "bootstrap_parent_fixture_id: paper-mario-title-screen" in fixture),
    ("graph node id", "id: kmr_03_entry_5_idle" in graph),
    ("graph fixture id", "fixture_id: paper-mario-kmr-03-entry-5" in graph),
    ("graph status", "status: active" in graph),
    ("graph state path", "assets/states/paper-mario-kmr-03-entry-5/ParaLLEl N64/Paper Mario (USA).state" in graph),
    ("graph capture hash", "04ea11ae5d0bd5b64d79851d88e406f3167454a5033630396e6fc492f60052d5" in graph),
    ("graph probe lineage hash", "probe_capture_sha256: 4bd3929dabff3ffb1b7e03a9c10d8ce50e9b6d0f067825d3a788c48a41b6fc62" in graph),
    ("runtime authoritative path", 'AUTHORITATIVE_STATE_PATH="/home/auro/code/parallel-n64/assets/states/paper-mario-kmr-03-entry-5/ParaLLEl N64/Paper Mario (USA).state"' in runtime_env),
    ("runtime bootstrap path", 'BOOTSTRAP_STATE_PATH="/home/auro/code/parallel-n64/assets/states/paper-mario-title-screen/ParaLLEl N64/Paper Mario (USA).state"' in runtime_env),
    ("runtime expected hash", 'EXPECTED_SCREENSHOT_SHA256_OFF="04ea11ae5d0bd5b64d79851d88e406f3167454a5033630396e6fc492f60052d5"' in runtime_env),
    ("runtime world init", 'EXPECTED_INIT_SYMBOL="state_init_world"' in runtime_env),
    ("runtime world step", 'EXPECTED_STEP_SYMBOL="state_step_world"' in runtime_env),
    ("runtime timeout frames", 'TIMEOUT_STEP_FRAMES="960"' in runtime_env),
]

failed = [name for name, ok in checks if not ok]
if failed:
    raise SystemExit("non-menu fixture contract failed: " + ", ".join(failed))

print("emu_paper_mario_non_menu_fixture_contract: PASS")
PY
