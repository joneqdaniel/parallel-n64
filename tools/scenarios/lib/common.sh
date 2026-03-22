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
