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

AREA_MAP_NAMES = {
    0: [
        "kmr_00",
        "kmr_02",
        "kmr_03",
        "kmr_04",
        "kmr_05",
        "kmr_06",
        "kmr_07",
        "kmr_09",
        "kmr_10",
        "kmr_11",
        "kmr_12",
        "kmr_20",
        "kmr_21",
        "kmr_22",
        "kmr_23",
        "kmr_24",
        "kmr_30",
    ],
    5: [
        "hos_00",
        "hos_01",
        "hos_02",
        "hos_03",
        "hos_04",
        "hos_05",
        "hos_06",
        "hos_10",
        "hos_20",
    ],
    23: [
        "osr_00",
        "osr_01",
        "osr_02",
        "osr_03",
        "osr_04",
    ],
}

EMPIRICAL_PHASE_BY_WINDOW_SHA256 = {
    "db67c1ef1d1916e044bf53aded99d66adf4e776fd7438012bd7b44d618fb98eb": "title_screen_authority",
    "220e633751b7992388351bce48f3f9f79aa17f95bf7655f1dc0bc2cd52a70cf4": "file_select_authority",
    "d5ca8402cf1962e121653214e8f7050c769e89eb5f37b421794a3df0185e3ea9": "post_file_select_transition_candidate",
}
CUR_GAME_MODE_PHASE_BY_POINTERS = {
    (0x80033E70, 0x800340A4): "logos_callbacks",
    (0x80035058, 0x800354EC): "file_select_callbacks",
    (0x80035660, 0x80035B40): "exit_file_select_callbacks",
    (0x80035E24, 0x80035EEC): "enter_world_callbacks",
    (0x80035D30, 0x80035D54): "world_callbacks",
    (0x80036650, 0x80036854): "intro_callbacks",
    (0x80036DF0, 0x800370B4): "title_screen_callbacks",
}
CUR_GAME_MODE_POINTER_NAMES = {
    0x80033E70: "state_init_logos",
    0x800340A4: "state_step_logos",
    0x80035058: "state_init_file_select",
    0x800354EC: "state_step_file_select",
    0x80035660: "state_init_exit_file_select",
    0x80035B40: "state_step_exit_file_select",
    0x80035D30: "state_init_world",
    0x80035D54: "state_step_world",
    0x80035E24: "state_init_enter_world",
    0x80035EEC: "state_step_enter_world",
    0x80036650: "state_init_intro",
    0x80036854: "state_step_intro",
    0x80036DF0: "state_init_title_screen",
    0x800370B4: "state_step_title_screen",
}
trace_path = bundle_dir / "traces" / "paper-mario-gamestatus.core-memory.txt"
expected_base = 0x800740AA
expected_size = 0xE6
cur_game_mode_trace_path = bundle_dir / "traces" / "paper-mario-curgamemode.core-memory.txt"
cur_game_mode_expected_base = 0x80151700
cur_game_mode_expected_size = 0x14
transition_trace_path = bundle_dir / "traces" / "paper-mario-transition.core-memory.txt"
transition_expected_base = 0x800A0944
transition_expected_size = 0x08

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
area_id = s16le(gamestatus, 0x00)
map_id = s16le(gamestatus, 0x06)
map_name_candidates = AREA_MAP_NAMES.get(area_id, [])
map_name_candidate = None
if 0 <= map_id < len(map_name_candidates):
    map_name_candidate = map_name_candidates[map_id]

cur_game_mode_trace = load_trace(cur_game_mode_trace_path)
if cur_game_mode_trace is not None:
    if cur_game_mode_trace["base_address"] != cur_game_mode_expected_base:
        raise SystemExit(
            f"Unexpected base address for {cur_game_mode_trace_path.name}: "
            f"0x{cur_game_mode_trace['base_address']:08x} != 0x{cur_game_mode_expected_base:08x}"
        )
    if len(cur_game_mode_trace["data"]) < cur_game_mode_expected_size:
        raise SystemExit(
            f"Snapshot too short for {cur_game_mode_trace_path.name}: "
            f"{len(cur_game_mode_trace['data'])} < {cur_game_mode_expected_size}"
        )

transition_trace = load_trace(transition_trace_path)
if transition_trace is not None:
    if transition_trace["base_address"] != transition_expected_base:
        raise SystemExit(
            f"Unexpected base address for {transition_trace_path.name}: "
            f"0x{transition_trace['base_address']:08x} != 0x{transition_expected_base:08x}"
        )
    if len(transition_trace["data"]) < transition_expected_size:
        raise SystemExit(
            f"Snapshot too short for {transition_trace_path.name}: "
            f"{len(transition_trace['data'])} < {transition_expected_size}"
        )

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
            "area_id": area_id,
            "area_name": AREA_NAMES.get(area_id, "UNKNOWN"),
            "prev_area": s16le(gamestatus, 0x02),
            "prev_area_name": AREA_NAMES.get(s16le(gamestatus, 0x02), "UNKNOWN"),
            "did_area_change": s16le(gamestatus, 0x04),
            "map_id": map_id,
            "map_name_candidate": map_name_candidate,
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

if cur_game_mode_trace is not None:
    cur_game_mode = cur_game_mode_trace["data"]
    init_ptr = u32le(cur_game_mode, 0x04)
    step_ptr = u32le(cur_game_mode, 0x08)
    render_front_ui_ptr = u32le(cur_game_mode, 0x0C)
    render_back_ui_ptr = u32le(cur_game_mode, 0x10)
    result["sources"]["cur_game_mode"] = {
        "path": cur_game_mode_trace["path"],
        "base_address": f"0x{cur_game_mode_trace['base_address']:08x}",
        "window_size_bytes": len(cur_game_mode_trace["data"]),
        "window_sha256": hashlib.sha256(cur_game_mode).hexdigest(),
        "description": "Vanilla Paper Mario US CurGameMode runtime block from symbol_addrs.txt.",
    }
    result["paper_mario_us"]["cur_game_mode"] = {
        "layout_note": "Runtime observations currently indicate a 2-byte leading field, then 2-byte flags, then init/step/renderFront/renderBack pointers.",
        "leading_u16": u16le(cur_game_mode, 0x00),
        "flags": u16le(cur_game_mode, 0x02),
        "init_ptr": f"0x{init_ptr:08x}",
        "init_symbol": CUR_GAME_MODE_POINTER_NAMES.get(init_ptr),
        "step_ptr": f"0x{step_ptr:08x}",
        "step_symbol": CUR_GAME_MODE_POINTER_NAMES.get(step_ptr),
        "render_front_ui_ptr": f"0x{render_front_ui_ptr:08x}",
        "render_front_ui_symbol": CUR_GAME_MODE_POINTER_NAMES.get(render_front_ui_ptr, "game_mode_nop" if render_front_ui_ptr == 0x80112B90 else None),
        "render_back_ui_ptr": f"0x{render_back_ui_ptr:08x}",
        "render_back_ui_symbol": CUR_GAME_MODE_POINTER_NAMES.get(render_back_ui_ptr),
        "phase_guess": CUR_GAME_MODE_PHASE_BY_POINTERS.get((init_ptr, step_ptr), "unknown"),
    }

if transition_trace is not None:
    transition = transition_trace["data"]
    result["sources"]["map_transition_state"] = {
        "path": transition_trace["path"],
        "base_address": f"0x{transition_trace['base_address']:08x}",
        "window_size_bytes": len(transition_trace["data"]),
        "window_sha256": hashlib.sha256(transition).hexdigest(),
        "description": "Vanilla Paper Mario US map-transition globals from symbol_addrs.txt.",
    }
    result["paper_mario_us"]["map_transition"] = {
        "state": s16le(transition, 0x00),
        "state_time": s16le(transition, 0x02),
        "loaded_from_file_select": s16le(transition, 0x04),
    }

output_path.write_text(json.dumps(result, indent=2) + "\n")
PY
}
