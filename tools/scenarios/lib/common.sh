#!/usr/bin/env bash

scenario_sha256_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "missing"
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    shasum -a 256 "$path" | awk '{print $1}'
  fi
}

scenario_json_bool() {
  if [[ "$1" == "1" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

scenario_default_bundle_dir() {
  local repo_root="$1"
  local fixture_id="$2"
  local mode="$3"
  local timestamp
  timestamp="$(date +"%Y%m%d-%H%M%S")"
  printf '%s/artifacts/%s/%s/%s\n' "$repo_root" "$fixture_id" "$mode" "$timestamp"
}

scenario_prepare_bundle_dirs() {
  local bundle_dir="$1"
  mkdir -p "$bundle_dir"/captures "$bundle_dir"/logs "$bundle_dir"/traces
}

scenario_print_header() {
  local fixture_id="$1"
  local mode="$2"
  local bundle_dir="$3"
  local manifest="$4"

  echo "[scenario] fixture: $fixture_id"
  echo "[scenario] mode: $mode"
  echo "[scenario] bundle: $bundle_dir"
  echo "[scenario] manifest: $manifest"
  echo "[scenario] internal scale: 4x"
  echo "[scenario] execution: serial"
}

scenario_patch_file() {
  local path="$1"
  local expr="$2"
  perl -0pi -e "$expr" "$path"
}

scenario_stage_optional_savefile() {
  local savefile_path="$1"
  local bundle_dir="$2"
  local rom_basename="$3"

  if [[ -z "$savefile_path" || ! -f "$savefile_path" ]]; then
    return 1
  fi

  mkdir -p "$bundle_dir/savefiles/ParaLLEl N64"
  cp "$savefile_path" "$bundle_dir/savefiles/ParaLLEl N64/${rom_basename}.srm"
}

scenario_decode_paper_mario_semantic_state() {
  local bundle_dir="$1"
  local output_path="$2"

  python - "$bundle_dir" "$output_path" <<'PY'
import json
import hashlib
import sys
from pathlib import Path

bundle_dir = Path(sys.argv[1])
output_path = Path(sys.argv[2])

LOAD_TYPE_NAMES = {
    0: "LOAD_FROM_MAP",
    1: "LOAD_FROM_FILE_SELECT",
}

AREA_NAMES = {
    0: "AREA_KMR",
    1: "AREA_MAC",
    2: "AREA_TIK",
    3: "AREA_KGR",
    4: "AREA_KKJ",
    5: "AREA_HOS",
    6: "AREA_NOK",
    7: "AREA_TRD",
    8: "AREA_IWA",
    9: "AREA_DRO",
    10: "AREA_SBK",
    11: "AREA_ISK",
    12: "AREA_MIM",
    13: "AREA_OBK",
    14: "AREA_ARN",
    15: "AREA_DGB",
    16: "AREA_OMO",
    17: "AREA_JAN",
    18: "AREA_KZN",
    19: "AREA_FLO",
    20: "AREA_SAM",
    21: "AREA_PRA",
    22: "AREA_KPA",
    23: "AREA_OSR",
    24: "AREA_END",
    25: "AREA_MGM",
    26: "AREA_GV",
    27: "AREA_TST",
}

EMPIRICAL_PHASE_BY_WINDOW_SHA256 = {
    "db67c1ef1d1916e044bf53aded99d66adf4e776fd7438012bd7b44d618fb98eb": "title_screen_authority",
    "220e633751b7992388351bce48f3f9f79aa17f95bf7655f1dc0bc2cd52a70cf4": "file_select_authority",
    "d5ca8402cf1962e121653214e8f7050c769e89eb5f37b421794a3df0185e3ea9": "post_file_select_transition_candidate",
}
trace_path = bundle_dir / "traces" / "paper-mario-gamestatus.core-memory.txt"
expected_base = 0x800740AA
expected_size = 0xE6

def load_trace(path: Path):
    if not path.is_file():
        return None
    fields = path.read_text().split()
    if not fields or fields[0] != "READ_CORE_MEMORY":
        raise SystemExit(f"Unexpected Paper Mario snapshot format: {path}")
    base_address = int(fields[1], 16)
    data = bytes(int(x, 16) for x in fields[2:])
    return {"path": str(path), "base_address": base_address, "data": data}

def u8(buf, off):
    return buf[off]

def s8(buf, off):
    value = buf[off]
    return value - 256 if value >= 128 else value

def u16le(buf, off):
    return buf[off] | (buf[off + 1] << 8)

def s16le(buf, off):
    value = u16le(buf, off)
    return value - 65536 if value >= 32768 else value

def u32le(buf, off):
    return (
        buf[off]
        | (buf[off + 1] << 8)
        | (buf[off + 2] << 16)
        | (buf[off + 3] << 24)
    )

trace = load_trace(trace_path)
if trace is None:
    raise SystemExit("Paper Mario gamestatus snapshot not found in bundle traces.")
if trace["base_address"] != expected_base:
    raise SystemExit(
        f"Unexpected base address for {trace_path.name}: "
        f"0x{trace['base_address']:08x} != 0x{expected_base:08x}"
    )
if len(trace["data"]) < expected_size:
    raise SystemExit(
        f"Snapshot too short for {trace_path.name}: "
        f"{len(trace['data'])} < {expected_size}"
    )

gamestatus = trace["data"]
window_sha256 = hashlib.sha256(gamestatus).hexdigest()

result = {
    "sources": {
        "gamestatus_window": {
            "path": trace["path"],
            "base_address": f"0x{trace['base_address']:08x}",
            "window_size_bytes": len(trace["data"]),
            "window_sha256": window_sha256,
            "description": "Empirical vanilla Paper Mario US gGameStatus slice starting at +0x86.",
        }
    },
    "paper_mario_us": {
        "empirical_phase_guess": EMPIRICAL_PHASE_BY_WINDOW_SHA256.get(window_sha256, "unknown"),
        "game_status": {
            "area_id": s16le(gamestatus, 0x00),
            "area_name": AREA_NAMES.get(s16le(gamestatus, 0x00), "UNKNOWN"),
            "prev_area": s16le(gamestatus, 0x02),
            "prev_area_name": AREA_NAMES.get(s16le(gamestatus, 0x02), "UNKNOWN"),
            "did_area_change": s16le(gamestatus, 0x04),
            "map_id": s16le(gamestatus, 0x06),
            "entry_id": s16le(gamestatus, 0x08),
            "intro_part": s8(gamestatus, 0x22),
            "startup_state": s8(gamestatus, 0x26),
            "title_screen_timer": s8(gamestatus, 0x29),
            "title_screen_dismiss_time": s8(gamestatus, 0x2A),
            "frame_counter": u16le(gamestatus, 0xAE),
            "save_slot": u8(gamestatus, 0xE0),
            "load_type": u8(gamestatus, 0xE1),
            "load_type_name": LOAD_TYPE_NAMES.get(u8(gamestatus, 0xE1), "UNKNOWN"),
            "save_count": u32le(gamestatus, 0xE2),
        }
    },
}

output_path.write_text(json.dumps(result, indent=2) + "\n")
PY
}
