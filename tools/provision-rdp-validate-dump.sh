#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_SOURCE_DIR="${HOME}/code/mupen/parallel-rdp-upstream"
DEFAULT_REPO_URL="https://github.com/Themaister/parallel-rdp.git"

source_dir="${RDP_VALIDATE_DUMP_SOURCE_DIR:-$DEFAULT_SOURCE_DIR}"
repo_url="${RDP_VALIDATE_DUMP_REPO_URL:-$DEFAULT_REPO_URL}"
build_dir=""
jobs="${JOBS:-$(nproc)}"
refresh=0

usage() {
  cat <<'USAGE'
Usage:
  tools/provision-rdp-validate-dump.sh [options]

Options:
  --source-dir PATH    Source checkout directory (default: ~/code/mupen/parallel-rdp-upstream)
  --build-dir PATH     Build directory (default: <source-dir>/build)
  --repo-url URL       Git URL if source checkout is missing
  --jobs N             Parallel build jobs (default: nproc)
  --refresh            Fetch latest remote state before building
  -h, --help           Show this help

Outputs:
  Prints absolute path to the built rdp-validate-dump binary on success.
USAGE
}

while (($#)); do
  case "$1" in
    --source-dir)
      shift
      source_dir="${1:-}"
      ;;
    --build-dir)
      shift
      build_dir="${1:-}"
      ;;
    --repo-url)
      shift
      repo_url="${1:-}"
      ;;
    --jobs)
      shift
      jobs="${1:-}"
      ;;
    --refresh)
      refresh=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ -z "$source_dir" ]]; then
  echo "--source-dir cannot be empty." >&2
  exit 2
fi

if [[ -z "$build_dir" ]]; then
  build_dir="$source_dir/build"
fi

if (( ! refresh )) && [[ -x "$build_dir/rdp-validate-dump" ]]; then
  echo "[validator] using existing binary: $build_dir/rdp-validate-dump" >&2
  echo "$build_dir/rdp-validate-dump"
  exit 0
fi

if [[ ! -d "$source_dir/.git" ]]; then
  echo "[validator] cloning $repo_url -> $source_dir" >&2
  git clone --recursive "$repo_url" "$source_dir"
else
  echo "[validator] using existing checkout: $source_dir" >&2
  if (( refresh )); then
    git -C "$source_dir" fetch --tags --prune origin
    git -C "$source_dir" pull --ff-only
  fi
  git -C "$source_dir" submodule update --init --recursive
fi

echo "[validator] configure: $build_dir" >&2
cmake -S "$source_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release >&2

echo "[validator] build" >&2
cmake --build "$build_dir" --parallel "$jobs" >&2

validator="$build_dir/rdp-validate-dump"
if [[ ! -x "$validator" ]]; then
  echo "Failed to locate built validator at: $validator" >&2
  exit 1
fi

echo "$validator"
