#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

ENRICHED_CACHE_PATH_CURRENT="$REPO_ROOT/artifacts/hts2phrb-review/20260408-pm64-all-families-authority-context-abs-summary/package.phrb"
ENRICHED_CACHE_PATH_LEGACY="$REPO_ROOT/artifacts/hts2phrb-review/20260407-pm64-all-families-authority-context-root/package.phrb"
ZERO_CONFIG_CACHE_PATH="$REPO_ROOT/artifacts/hts2phrb/paper-mario-hirestextures-9fa7bc07-all-families/package.phrb"

if [[ -n "${EMU_RUNTIME_PM64_FULL_CACHE_PHRB:-}" ]]; then
  CACHE_PATH="${EMU_RUNTIME_PM64_FULL_CACHE_PHRB}"
else
  CACHE_PATH="$ENRICHED_CACHE_PATH_CURRENT"
  if [[ ! -f "$CACHE_PATH" ]]; then
    CACHE_PATH="$ENRICHED_CACHE_PATH_LEGACY"
  fi
fi
ENFORCE_ENRICHED_CONTRACT=0
if [[ "$CACHE_PATH" == "$ENRICHED_CACHE_PATH_CURRENT" || "$CACHE_PATH" == "$ENRICHED_CACHE_PATH_LEGACY" ]]; then
  ENFORCE_ENRICHED_CONTRACT=1
fi
ENFORCE_ZERO_CONFIG_CONTRACT=0
if [[ "$CACHE_PATH" == "$ZERO_CONFIG_CACHE_PATH" ]]; then
  ENFORCE_ZERO_CONFIG_CONTRACT=1
fi
BUNDLE_ROOT="${EMU_RUNTIME_PM64_FULL_CACHE_BUNDLE_ROOT:-}"

if [[ "${EMU_ENABLE_RUNTIME_CONFORMANCE:-0}" != "1" ]]; then
  echo "SKIP: set EMU_ENABLE_RUNTIME_CONFORMANCE=1 to run Paper Mario full-cache PHRB authority conformance."
  exit 77
fi

if [[ ! -x "$REPO_ROOT/tools/scenarios/paper-mario-full-cache-phrb-authority-validation.sh" ]]; then
  echo "FAIL: full-cache PHRB authority validation wrapper is missing or not executable." >&2
  exit 1
fi

if [[ ! -f "$CACHE_PATH" ]]; then
  echo "SKIP: enriched full-cache Paper Mario PHRB package not found at $CACHE_PATH (run the authority refresh workflow or set EMU_RUNTIME_PM64_FULL_CACHE_PHRB to override explicitly, including the zero-config lane)."
  exit 77
fi

require_runtime_env_prereqs() {
  local env_path="$1"
  local label="$2"
  if [[ ! -f "$env_path" ]]; then
    echo "SKIP: runtime env missing for $label at $env_path."
    exit 77
  fi

  local bin_path base_cfg core_path rom_path authoritative_state_path
  bin_path="$(
    ENV_PATH="$env_path" python3 - <<'PY'
import os
from pathlib import Path

env_path = Path(os.environ["ENV_PATH"])
values = {}
for raw in env_path.read_text().splitlines():
    line = raw.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    values[key] = value.strip().strip('"')
for key in ("RETROARCH_BIN", "RETROARCH_BASE_CONFIG", "CORE_PATH", "ROM_PATH", "AUTHORITATIVE_STATE_PATH"):
    print(values.get(key, ""))
PY
  )"

  mapfile -t prereq_paths <<<"$bin_path"
  bin_path="${prereq_paths[0]:-}"
  base_cfg="${prereq_paths[1]:-}"
  core_path="${prereq_paths[2]:-}"
  rom_path="${prereq_paths[3]:-}"
  authoritative_state_path="${prereq_paths[4]:-}"

  if [[ -z "$bin_path" || ! -x "$bin_path" ]]; then
    echo "SKIP: RetroArch binary missing for $label at $bin_path."
    exit 77
  fi
  if [[ -z "$base_cfg" || ! -f "$base_cfg" ]]; then
    echo "SKIP: RetroArch config missing for $label at $base_cfg."
    exit 77
  fi
  if [[ -z "$core_path" || ! -f "$core_path" ]]; then
    echo "SKIP: libretro core missing for $label at $core_path."
    exit 77
  fi
  if [[ -z "$rom_path" || ! -f "$rom_path" ]]; then
    echo "SKIP: Paper Mario ROM missing for $label at $rom_path."
    exit 77
  fi
  if [[ -z "$authoritative_state_path" || ! -f "$authoritative_state_path" ]]; then
    echo "SKIP: authoritative state missing for $label at $authoritative_state_path."
    exit 77
  fi
}

require_runtime_env_prereqs "$REPO_ROOT/tools/scenarios/paper-mario-title-screen.runtime.env" "paper-mario-title-screen"
require_runtime_env_prereqs "$REPO_ROOT/tools/scenarios/paper-mario-file-select.runtime.env" "paper-mario-file-select"
require_runtime_env_prereqs "$REPO_ROOT/tools/scenarios/paper-mario-kmr-03-entry-5.runtime.env" "paper-mario-kmr-03-entry-5"

cleanup_bundle_root=0
if [[ -z "$BUNDLE_ROOT" ]]; then
  BUNDLE_ROOT="$(mktemp -d)"
  cleanup_bundle_root=1
fi

cleanup() {
  local rc=$?
  if (( cleanup_bundle_root )) && [[ $rc -eq 0 ]]; then
    rm -rf "$BUNDLE_ROOT"
  else
    echo "[conformance] bundle root: $BUNDLE_ROOT"
  fi
  exit "$rc"
}
trap cleanup EXIT

set +e
timeout --signal=INT --kill-after=15 600s \
  "$REPO_ROOT/tools/scenarios/paper-mario-full-cache-phrb-authority-validation.sh" \
  --cache-path "$CACHE_PATH" \
  --bundle-root "$BUNDLE_ROOT"
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  echo "FAIL: full-cache PHRB authority validation exited with status $rc." >&2
  exit 1
fi

SUMMARY_PATH="$BUNDLE_ROOT/validation-summary.json"
if [[ ! -f "$SUMMARY_PATH" ]]; then
  echo "FAIL: full-cache PHRB authority validation did not produce $SUMMARY_PATH." >&2
  exit 1
fi

python3 - "$SUMMARY_PATH" "$ENFORCE_ENRICHED_CONTRACT" "$ENFORCE_ZERO_CONFIG_CONTRACT" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text())
enforce_enriched_contract = bool(int(sys.argv[2]))
enforce_zero_config_contract = bool(int(sys.argv[3]))
fixtures = summary.get("fixtures") or []
expected_screenshot_hashes = {
    "title-screen": "0e854083b48ccf48e0a372e39ca439c17f0e66523423fb2c3b68b94181c72ad5",
    "file-select": "43bd91dab1dfa4001365caee5ba03bc4ae1999fd012f5e943093615b4c858ca9",
    "kmr-03-entry-5": "212ffb9329b8d78e608874e524534ca54505a26204abe78524ef8fca97a1b638",
}
zero_config_expected = {
    "title-screen": {
        "screenshot_sha256": "ba91ffce0cc7b6053568c0a7774bf0ae80825c95d95fce89ba4a9f79c62b9d16",
        "native_sampled_entry_count": 0,
        "entry_class": "compat-only",
        "descriptor_path_class": "compat-only",
        "descriptor_path_counts": {"sampled": 0, "native_checksum": 0, "generic": 0, "compat": 178},
    },
    "file-select": {
        "screenshot_sha256": "8a90f7874bd797a186ff85d488033dc332b2a75f5bec91ad33ca8246e6be7730",
        "native_sampled_entry_count": 0,
        "entry_class": "compat-only",
        "descriptor_path_class": "compat-only",
        "descriptor_path_counts": {"sampled": 0, "native_checksum": 0, "generic": 0, "compat": 82},
    },
    "kmr-03-entry-5": {
        "screenshot_sha256": "3a175a30d8154df34cd17d21eb8d6997ef12d6846bddf2b6c7f9c2074e0a215e",
        "native_sampled_entry_count": 0,
        "entry_class": "compat-only",
        "descriptor_path_class": "compat-only",
        "descriptor_path_counts": {"sampled": 0, "native_checksum": 0, "generic": 0, "compat": 112},
    },
}
if not summary.get("all_passed"):
    raise SystemExit("FAIL: full-cache PHRB authority summary is not all_passed.")
if len(fixtures) != 3:
    raise SystemExit(f"FAIL: expected 3 fixtures, found {len(fixtures)}.")
for fixture in fixtures:
    if not fixture.get("passed"):
        raise SystemExit(f"FAIL: fixture {fixture.get('label')} did not pass.")
    hires = fixture.get("hires_summary") or {}
    if hires.get("source_mode") != "phrb-only":
        raise SystemExit(
            f"FAIL: fixture {fixture.get('label')} expected source_mode=phrb-only, "
            f"got {hires.get('source_mode')!r}."
        )
    if int(hires.get("entry_count") or 0) < 1:
        raise SystemExit(f"FAIL: fixture {fixture.get('label')} has no hi-res entries.")
    if int(hires.get("source_phrb_count") or 0) < 1:
        raise SystemExit(f"FAIL: fixture {fixture.get('label')} has no phrb-backed hi-res entries.")
    descriptor_paths = hires.get("descriptor_path_counts") or {}
    if enforce_enriched_contract:
        expected_hash = expected_screenshot_hashes.get(fixture.get("label"))
        if expected_hash and fixture.get("screenshot_sha256") != expected_hash:
            raise SystemExit(
                f"FAIL: fixture {fixture.get('label')} expected screenshot hash {expected_hash}, "
                f"got {fixture.get('screenshot_sha256')!r}."
            )
        if int(hires.get("native_sampled_entry_count") or 0) < 1:
            raise SystemExit(
                f"FAIL: fixture {fixture.get('label')} expected native sampled entries on the enriched full-cache lane."
            )
        if hires.get("descriptor_path_class") != "sampled-only":
            raise SystemExit(
                f"FAIL: fixture {fixture.get('label')} expected descriptor_path_class=sampled-only on the enriched full-cache lane, "
                f"got {hires.get('descriptor_path_class')!r}."
            )
        if int(descriptor_paths.get("generic") or 0) != 0:
            raise SystemExit(
                f"FAIL: fixture {fixture.get('label')} expected generic descriptor traffic to be zero on the enriched full-cache lane, "
                f"got {descriptor_paths.get('generic')!r}."
            )
        if int(descriptor_paths.get("compat") or 0) != 0:
            raise SystemExit(
                f"FAIL: fixture {fixture.get('label')} expected compat descriptor traffic to be zero on the enriched full-cache lane, "
                f"got {descriptor_paths.get('compat')!r}."
            )
    if enforce_zero_config_contract:
        zero_expected = zero_config_expected.get(fixture.get("label"))
        if zero_expected is None:
            raise SystemExit(f"FAIL: unexpected fixture label for zero-config contract: {fixture.get('label')!r}.")
        if fixture.get("screenshot_sha256") != zero_expected["screenshot_sha256"]:
            raise SystemExit(
                f"FAIL: fixture {fixture.get('label')} expected zero-config screenshot hash {zero_expected['screenshot_sha256']}, "
                f"got {fixture.get('screenshot_sha256')!r}."
            )
        if int(hires.get("native_sampled_entry_count") or 0) != zero_expected["native_sampled_entry_count"]:
            raise SystemExit(
                f"FAIL: fixture {fixture.get('label')} expected native_sampled_entry_count="
                f"{zero_expected['native_sampled_entry_count']} on the zero-config lane, "
                f"got {hires.get('native_sampled_entry_count')!r}."
            )
        if hires.get("entry_class") != zero_expected["entry_class"]:
            raise SystemExit(
                f"FAIL: fixture {fixture.get('label')} expected entry_class={zero_expected['entry_class']!r} on the zero-config lane, "
                f"got {hires.get('entry_class')!r}."
            )
        if hires.get("descriptor_path_class") != zero_expected["descriptor_path_class"]:
            raise SystemExit(
                f"FAIL: fixture {fixture.get('label')} expected descriptor_path_class={zero_expected['descriptor_path_class']!r} on the zero-config lane, "
                f"got {hires.get('descriptor_path_class')!r}."
            )
        if descriptor_paths != zero_expected["descriptor_path_counts"]:
            raise SystemExit(
                f"FAIL: fixture {fixture.get('label')} expected zero-config descriptor_path_counts="
                f"{zero_expected['descriptor_path_counts']!r}, got {descriptor_paths!r}."
            )
PY

echo "emu_conformance_paper_mario_full_cache_phrb_authorities: PASS ($CACHE_PATH)"
