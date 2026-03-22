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

scenario_decode_paper_mario_game_status_snapshot() {
  local snapshot_path="$1"
  local output_path="$2"
  local -a fields=()
  local area_id=0
  local map_id=0
  local entry_id=0
  local intro_part=0
  local startup_state=0

  if [[ ! -f "$snapshot_path" ]]; then
    echo "Paper Mario snapshot not found: $snapshot_path" >&2
    return 1
  fi

  read -r -a fields < "$snapshot_path" || true
  if [[ "${fields[0]:-}" != "READ_CORE_MEMORY" ]]; then
    echo "Unexpected Paper Mario snapshot format: $snapshot_path" >&2
    return 1
  fi

  if (( ${#fields[@]} < 42 )); then
    echo "Paper Mario snapshot too short: $snapshot_path" >&2
    return 1
  fi

  area_id=$(( (16#${fields[2]} << 8) | 16#${fields[3]} ))
  map_id=$(( (16#${fields[8]} << 8) | 16#${fields[9]} ))
  entry_id=$(( (16#${fields[10]} << 8) | 16#${fields[11]} ))
  intro_part=$(( 16#${fields[36]} ))
  startup_state=$(( 16#${fields[40]} ))

  cat > "$output_path" <<EOF
{
  "source_trace": "$snapshot_path",
  "base_address": "0x${fields[1]}",
  "window_size_bytes": 40,
  "paper_mario_us_gamestatus": {
    "area_id": $area_id,
    "map_id": $map_id,
    "entry_id": $entry_id,
    "intro_part": $intro_part,
    "startup_state": $startup_state
  }
}
EOF
}
