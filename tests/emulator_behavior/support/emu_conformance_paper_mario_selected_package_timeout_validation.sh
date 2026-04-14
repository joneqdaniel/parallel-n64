#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

CACHE_PATH_DEFAULT="$REPO_ROOT/artifacts/hires-pack-review/20260330-selected-plus-timeout-960-v1-add-1b85/package.phrb"
LOADER_MANIFEST_DEFAULT="$REPO_ROOT/artifacts/hires-pack-review/20260330-selected-plus-timeout-960-v1-add-1b85/loader-manifest.json"
TRANSPORT_REVIEW_DEFAULT="$REPO_ROOT/artifacts/hires-pack-review/20260406-timeout-960-sampled-transport-next/review.json"
TITLE_GUARD_EVIDENCE_DEFAULT="$REPO_ROOT/artifacts/paper-mario-probes/validation/20260406-201200-selected-package-authorities/title-screen/traces/hires-evidence.json"
FILE_GUARD_EVIDENCE_DEFAULT="$REPO_ROOT/artifacts/paper-mario-probes/validation/20260406-201200-selected-package-authorities/file-select/traces/hires-evidence.json"
WORLD_GUARD_EVIDENCE_DEFAULT="$REPO_ROOT/artifacts/paper-mario-probes/validation/20260406-201200-selected-package-authorities/kmr-03-entry-5/traces/hires-evidence.json"
PACKAGE_MANIFEST_DEFAULT="$REPO_ROOT/artifacts/hires-pack-review/20260330-selected-plus-timeout-960-v1-add-1b85/package/package-manifest.json"
POOL_REGRESSION_FLAT_SUMMARY_DEFAULT="$REPO_ROOT/artifacts/paper-mario-probes/validation/20260330-v31-legacy-timeout-960-add-1b85/validation-summary.json"
POOL_REGRESSION_DUAL_SUMMARY_DEFAULT="$REPO_ROOT/artifacts/paper-mario-probes/validation/20260330-v34-v32base-surface-1b85-timeout-960/validation-summary.json"
POOL_REGRESSION_ORDERED_SUMMARY_DEFAULT="$REPO_ROOT/artifacts/paper-mario-probes/validation/20260330-v35-v32base-surface-1b85-ordered-only-timeout-960/validation-summary.json"
POOL_REGRESSION_SURFACE_PACKAGE_DEFAULT="$REPO_ROOT/artifacts/hires-pack-review/20260330-1b85-sampled-surface-package/surface-package.json"
EXPECTED_ON_HASH_DEFAULT="4bd3929dabff3ffb1b7e03a9c10d8ce50e9b6d0f067825d3a788c48a41b6fc62"
EXPECTED_SAMPLED_DUPLICATE_KEYS_DEFAULT="1"
EXPECTED_SAMPLED_DUPLICATE_ENTRIES_DEFAULT="1"

CACHE_PATH="${EMU_RUNTIME_PM64_SELECTED_PHRB:-$CACHE_PATH_DEFAULT}"
LOADER_MANIFEST="${EMU_RUNTIME_PM64_SELECTED_LOADER_MANIFEST:-$LOADER_MANIFEST_DEFAULT}"
TRANSPORT_REVIEW="${EMU_RUNTIME_PM64_SELECTED_TRANSPORT_REVIEW:-$TRANSPORT_REVIEW_DEFAULT}"
ALT_SOURCE_CACHE="${EMU_RUNTIME_PM64_SELECTED_ALT_SOURCE_CACHE:-}"
TITLE_GUARD_EVIDENCE="${EMU_RUNTIME_PM64_SELECTED_TIMEOUT_TITLE_GUARD_EVIDENCE:-$TITLE_GUARD_EVIDENCE_DEFAULT}"
FILE_GUARD_EVIDENCE="${EMU_RUNTIME_PM64_SELECTED_TIMEOUT_FILE_GUARD_EVIDENCE:-$FILE_GUARD_EVIDENCE_DEFAULT}"
WORLD_GUARD_EVIDENCE="${EMU_RUNTIME_PM64_SELECTED_TIMEOUT_WORLD_GUARD_EVIDENCE:-$WORLD_GUARD_EVIDENCE_DEFAULT}"
PACKAGE_MANIFEST="${EMU_RUNTIME_PM64_SELECTED_TIMEOUT_PACKAGE_MANIFEST:-$PACKAGE_MANIFEST_DEFAULT}"
POOL_REGRESSION_FLAT_SUMMARY="${EMU_RUNTIME_PM64_SELECTED_TIMEOUT_POOL_REGRESSION_FLAT_SUMMARY:-$POOL_REGRESSION_FLAT_SUMMARY_DEFAULT}"
POOL_REGRESSION_DUAL_SUMMARY="${EMU_RUNTIME_PM64_SELECTED_TIMEOUT_POOL_REGRESSION_DUAL_SUMMARY:-$POOL_REGRESSION_DUAL_SUMMARY_DEFAULT}"
POOL_REGRESSION_ORDERED_SUMMARY="${EMU_RUNTIME_PM64_SELECTED_TIMEOUT_POOL_REGRESSION_ORDERED_SUMMARY:-$POOL_REGRESSION_ORDERED_SUMMARY_DEFAULT}"
POOL_REGRESSION_SURFACE_PACKAGE="${EMU_RUNTIME_PM64_SELECTED_TIMEOUT_POOL_REGRESSION_SURFACE_PACKAGE:-$POOL_REGRESSION_SURFACE_PACKAGE_DEFAULT}"
EXPECTED_ON_HASH="${EMU_RUNTIME_PM64_SELECTED_TIMEOUT_ON_HASH:-$EXPECTED_ON_HASH_DEFAULT}"
EXPECTED_SAMPLED_DUPLICATE_KEYS="${EMU_RUNTIME_PM64_SELECTED_TIMEOUT_EXPECTED_SAMPLED_DUPLICATE_KEYS:-$EXPECTED_SAMPLED_DUPLICATE_KEYS_DEFAULT}"
EXPECTED_SAMPLED_DUPLICATE_ENTRIES="${EMU_RUNTIME_PM64_SELECTED_TIMEOUT_EXPECTED_SAMPLED_DUPLICATE_ENTRIES:-$EXPECTED_SAMPLED_DUPLICATE_ENTRIES_DEFAULT}"
BUNDLE_ROOT="${EMU_RUNTIME_PM64_SELECTED_TIMEOUT_BUNDLE_ROOT:-}"

if [[ "${EMU_ENABLE_RUNTIME_CONFORMANCE:-0}" != "1" ]]; then
  echo "SKIP: set EMU_ENABLE_RUNTIME_CONFORMANCE=1 to run Paper Mario selected-package timeout conformance."
  exit 77
fi

SCENARIO="$REPO_ROOT/tools/scenarios/paper-mario-title-timeout-selected-package-validation.sh"
if [[ ! -x "$SCENARIO" ]]; then
  echo "FAIL: timeout selected-package validation wrapper is missing or not executable." >&2
  exit 1
fi

if [[ ! -f "$CACHE_PATH" ]]; then
  echo "SKIP: selected Paper Mario PHRB package not found at $CACHE_PATH (set EMU_RUNTIME_PM64_SELECTED_PHRB to override)."
  exit 77
fi

if [[ ! -f "$LOADER_MANIFEST" ]]; then
  echo "SKIP: selected-package loader manifest not found at $LOADER_MANIFEST."
  exit 77
fi

if [[ ! -f "$TRANSPORT_REVIEW" ]]; then
  echo "SKIP: selected-package transport review not found at $TRANSPORT_REVIEW."
  exit 77
fi
if [[ -n "$ALT_SOURCE_CACHE" && ! -f "$ALT_SOURCE_CACHE" ]]; then
  echo "SKIP: alternate-source cache not found at $ALT_SOURCE_CACHE."
  exit 77
fi
for history_path in \
  "$PACKAGE_MANIFEST" \
  "$POOL_REGRESSION_FLAT_SUMMARY" \
  "$POOL_REGRESSION_DUAL_SUMMARY" \
  "$POOL_REGRESSION_ORDERED_SUMMARY" \
  "$POOL_REGRESSION_SURFACE_PACKAGE"; do
  if [[ ! -f "$history_path" ]]; then
    echo "SKIP: timeout pool-regression input not found at $history_path."
    exit 77
  fi
done

TITLE_ENV="$REPO_ROOT/tools/scenarios/paper-mario-title-screen.runtime.env"
if [[ ! -f "$TITLE_ENV" ]]; then
  echo "SKIP: runtime env missing for paper-mario-title-screen at $TITLE_ENV."
  exit 77
fi

readarray -t prereq_paths < <(
  ENV_PATH="$TITLE_ENV" python3 - <<'PY'
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
)

bin_path="${prereq_paths[0]:-}"
base_cfg="${prereq_paths[1]:-}"
core_path="${prereq_paths[2]:-}"
rom_path="${prereq_paths[3]:-}"
authoritative_state_path="${prereq_paths[4]:-}"

if [[ -z "$bin_path" || ! -x "$bin_path" ]]; then
  echo "SKIP: RetroArch binary missing for title-timeout conformance at $bin_path."
  exit 77
fi
if [[ -z "$base_cfg" || ! -f "$base_cfg" ]]; then
  echo "SKIP: RetroArch config missing for title-timeout conformance at $base_cfg."
  exit 77
fi
if [[ -z "$core_path" || ! -f "$core_path" ]]; then
  echo "SKIP: libretro core missing for title-timeout conformance at $core_path."
  exit 77
fi
if [[ -z "$rom_path" || ! -f "$rom_path" ]]; then
  echo "SKIP: Paper Mario ROM missing for title-timeout conformance at $rom_path."
  exit 77
fi
if [[ -z "$authoritative_state_path" || ! -f "$authoritative_state_path" ]]; then
  echo "SKIP: authoritative state missing for title-timeout conformance at $authoritative_state_path."
  exit 77
fi

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
scenario_cmd=(
  timeout --signal=INT --kill-after=15 600s
  "$SCENARIO"
  --cache-path "$CACHE_PATH" \
  --bundle-root "$BUNDLE_ROOT" \
  --steps "960" \
  --loader-manifest "$LOADER_MANIFEST" \
  --transport-review "$TRANSPORT_REVIEW"
  --package-manifest "$PACKAGE_MANIFEST"
  --pool-regression-flat-summary "$POOL_REGRESSION_FLAT_SUMMARY"
  --pool-regression-dual-summary "$POOL_REGRESSION_DUAL_SUMMARY"
  --pool-regression-ordered-summary "$POOL_REGRESSION_ORDERED_SUMMARY"
  --pool-regression-surface-package "$POOL_REGRESSION_SURFACE_PACKAGE"
)
if [[ -n "$ALT_SOURCE_CACHE" ]]; then
  scenario_cmd+=(--alternate-source-cache "$ALT_SOURCE_CACHE")
fi
if [[ -f "$TITLE_GUARD_EVIDENCE" && -f "$FILE_GUARD_EVIDENCE" ]]; then
  scenario_cmd+=(--cross-scene-guard-evidence "title=$TITLE_GUARD_EVIDENCE")
  scenario_cmd+=(--cross-scene-guard-evidence "file=$FILE_GUARD_EVIDENCE")
  if [[ -f "$WORLD_GUARD_EVIDENCE" ]]; then
    scenario_cmd+=(--cross-scene-guard-evidence "world=$WORLD_GUARD_EVIDENCE")
  fi
fi
"${scenario_cmd[@]}"
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  echo "FAIL: selected-package timeout validation exited with status $rc." >&2
  exit 1
fi

SUMMARY_PATH="$BUNDLE_ROOT/validation-summary.json"
REVIEW_PATH="$BUNDLE_ROOT/on/timeout-960/traces/hires-sampled-selector-review.json"
POOL_REVIEW_PATH="$BUNDLE_ROOT/on/timeout-960/traces/hires-sampled-pool-review-1b8530fb.json"
SEAM_REGISTER_PATH="$BUNDLE_ROOT/on/timeout-960/traces/hires-runtime-seam-register.json"
ALT_REVIEW_PATH="$BUNDLE_ROOT/on/timeout-960/traces/hires-alternate-source-review.json"
CROSS_SCENE_REVIEW_PATH="$BUNDLE_ROOT/on/timeout-960/traces/hires-sampled-cross-scene-review.json"
ALT_ACTIVATION_REVIEW_PATH="$BUNDLE_ROOT/on/timeout-960/traces/hires-alternate-source-activation-review.json"
SAMPLED_DUPLICATE_REVIEW_PATH="$BUNDLE_ROOT/on/timeout-960/traces/hires-sampled-duplicate-review-7701ac09.json"
POOL_REGRESSION_REVIEW_PATH="$BUNDLE_ROOT/on/timeout-960/traces/hires-sampled-pool-regression-review-1b8530fb.json"
if [[ ! -f "$SUMMARY_PATH" ]]; then
  echo "FAIL: selected-package timeout validation did not produce $SUMMARY_PATH." >&2
  exit 1
fi
if [[ ! -f "$REVIEW_PATH" ]]; then
  echo "FAIL: selected-package timeout validation did not produce $REVIEW_PATH." >&2
  exit 1
fi
if [[ ! -f "$POOL_REVIEW_PATH" ]]; then
  echo "FAIL: selected-package timeout validation did not produce $POOL_REVIEW_PATH." >&2
  exit 1
fi
if [[ ! -f "$SEAM_REGISTER_PATH" ]]; then
  echo "FAIL: selected-package timeout validation did not produce $SEAM_REGISTER_PATH." >&2
  exit 1
fi
if [[ -n "$ALT_SOURCE_CACHE" && ! -f "$ALT_REVIEW_PATH" ]]; then
  echo "FAIL: selected-package timeout validation did not produce $ALT_REVIEW_PATH." >&2
  exit 1
fi
if [[ -f "$TITLE_GUARD_EVIDENCE" && -f "$FILE_GUARD_EVIDENCE" && ! -f "$CROSS_SCENE_REVIEW_PATH" ]]; then
  echo "FAIL: selected-package timeout validation did not produce $CROSS_SCENE_REVIEW_PATH." >&2
  exit 1
fi
if [[ -n "$ALT_SOURCE_CACHE" && -f "$TITLE_GUARD_EVIDENCE" && -f "$FILE_GUARD_EVIDENCE" && ! -f "$ALT_ACTIVATION_REVIEW_PATH" ]]; then
  echo "FAIL: selected-package timeout validation did not produce $ALT_ACTIVATION_REVIEW_PATH." >&2
  exit 1
fi
if (( EXPECTED_SAMPLED_DUPLICATE_KEYS > 0 )) && [[ ! -f "$SAMPLED_DUPLICATE_REVIEW_PATH" ]]; then
  echo "FAIL: selected-package timeout validation did not produce $SAMPLED_DUPLICATE_REVIEW_PATH." >&2
  exit 1
fi
if [[ ! -f "$POOL_REGRESSION_REVIEW_PATH" ]]; then
  echo "FAIL: selected-package timeout validation did not produce $POOL_REGRESSION_REVIEW_PATH." >&2
  exit 1
fi

python3 - "$SUMMARY_PATH" "$REVIEW_PATH" "$POOL_REVIEW_PATH" "$SEAM_REGISTER_PATH" "$ALT_REVIEW_PATH" "$CROSS_SCENE_REVIEW_PATH" "$ALT_ACTIVATION_REVIEW_PATH" "$SAMPLED_DUPLICATE_REVIEW_PATH" "$POOL_REGRESSION_REVIEW_PATH" "$TITLE_GUARD_EVIDENCE" "$FILE_GUARD_EVIDENCE" "$WORLD_GUARD_EVIDENCE" "$EXPECTED_ON_HASH" "$EXPECTED_SAMPLED_DUPLICATE_KEYS" "$EXPECTED_SAMPLED_DUPLICATE_ENTRIES" "$ALT_SOURCE_CACHE" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text())
review = json.loads(Path(sys.argv[2]).read_text())
pool_review = json.loads(Path(sys.argv[3]).read_text())
seam_register = json.loads(Path(sys.argv[4]).read_text())
alternate_source_review_path = Path(sys.argv[5])
alternate_source_review = json.loads(alternate_source_review_path.read_text()) if alternate_source_review_path.is_file() else {}
cross_scene_review_path = Path(sys.argv[6])
alternate_source_activation_review_path = Path(sys.argv[7])
sampled_duplicate_review_path = Path(sys.argv[8])
sampled_duplicate_review = json.loads(sampled_duplicate_review_path.read_text()) if sampled_duplicate_review_path.is_file() else {}
alternate_source_activation_review = (
    json.loads(alternate_source_activation_review_path.read_text())
    if alternate_source_activation_review_path.is_file()
    else {}
)
pool_regression_review = json.loads(Path(sys.argv[9]).read_text())
guard_paths_present = Path(sys.argv[10]).is_file() and Path(sys.argv[11]).is_file()
world_guard_present = Path(sys.argv[12]).is_file()
expected_on_hash = sys.argv[13]
expected_sampled_duplicate_keys = int(sys.argv[14])
expected_sampled_duplicate_entries = int(sys.argv[15])
alt_source_present = Path(sys.argv[16]).is_file() if sys.argv[16] else False
cross_scene_review = json.loads(cross_scene_review_path.read_text()) if cross_scene_review_path.is_file() else {}

steps = summary.get("steps") or []
if len(steps) != 1:
    raise SystemExit(f"FAIL: expected 1 timeout step, found {len(steps)}.")

step = steps[0]
if int(step.get("step_frames") or 0) != 960:
    raise SystemExit(f"FAIL: expected timeout step_frames=960, got {step.get('step_frames')!r}.")
if step.get("on_hash") != expected_on_hash:
    raise SystemExit(
        f"FAIL: expected selected-package timeout on_hash={expected_on_hash}, "
        f"got {step.get('on_hash')!r}."
    )
if not bool(step.get("matches_off")):
    raise SystemExit(f"FAIL: expected current selected-package timeout lane to remain pixel-identical to off, got {step!r}.")

semantic = step.get("semantic") or {}
if semantic.get("map_name_candidate") != "kmr_03" or int(semantic.get("entry_id") or -1) != 5:
    raise SystemExit(f"FAIL: unexpected semantic state {semantic!r}.")
if semantic.get("init_symbol") != "state_init_world" or semantic.get("step_symbol") != "state_step_world":
    raise SystemExit(f"FAIL: unexpected semantic callbacks {semantic!r}.")

hires = step.get("hires_summary") or {}
if hires.get("source_mode") != "phrb-only":
    raise SystemExit(f"FAIL: expected source_mode=phrb-only, got {hires.get('source_mode')!r}.")
if int(hires.get("entry_count") or 0) < 1:
    raise SystemExit("FAIL: selected-package timeout lane has no hi-res entries.")
if int(hires.get("native_sampled_entry_count") or 0) < 1:
    raise SystemExit("FAIL: selected-package timeout lane has no native sampled entries.")
sampled_index_count = int(hires.get("sampled_index_count") or 0)
sampled_duplicate_key_count = int(hires.get("sampled_duplicate_key_count") or 0)
sampled_duplicate_entry_count = int(hires.get("sampled_duplicate_entry_count") or 0)
native_sampled_entry_count = int(hires.get("native_sampled_entry_count") or 0)
if sampled_duplicate_key_count != expected_sampled_duplicate_keys:
    raise SystemExit(
        "FAIL: expected sampled_duplicate_key_count="
        f"{expected_sampled_duplicate_keys}, got {sampled_duplicate_key_count}."
    )
if sampled_duplicate_entry_count != expected_sampled_duplicate_entries:
    raise SystemExit(
        "FAIL: expected sampled_duplicate_entry_count="
        f"{expected_sampled_duplicate_entries}, got {sampled_duplicate_entry_count}."
    )
if sampled_index_count + sampled_duplicate_entry_count != native_sampled_entry_count:
    raise SystemExit(
        "FAIL: expected sampled_index_count + sampled_duplicate_entry_count == "
        f"native_sampled_entry_count, got {sampled_index_count} + "
        f"{sampled_duplicate_entry_count} != {native_sampled_entry_count}."
    )
descriptor_path_counts = step.get("descriptor_path_counts") or {}
if int(descriptor_path_counts.get("sampled") or 0) < 1:
    raise SystemExit(f"FAIL: expected sampled descriptor-path resolutions in selected-package timeout lane, got {descriptor_path_counts!r}.")
if int(descriptor_path_counts.get("native_checksum") or 0) != 0:
    raise SystemExit(f"FAIL: expected native_checksum descriptor-path resolutions to remain zero in current timeout lane, got {descriptor_path_counts!r}.")
if int(descriptor_path_counts.get("generic") or 0) != 0:
    raise SystemExit(f"FAIL: expected generic descriptor-path resolutions to remain zero in current timeout lane, got {descriptor_path_counts!r}.")
if int(descriptor_path_counts.get("compat") or 0) != 0:
    raise SystemExit(f"FAIL: expected compat descriptor-path resolutions to remain zero in current timeout lane, got {descriptor_path_counts!r}.")
duplicate_probe = step.get("sampled_duplicate_probe") or {}
if expected_sampled_duplicate_keys > 0:
    if int(duplicate_probe.get("line_count") or 0) < expected_sampled_duplicate_keys:
        raise SystemExit(
            "FAIL: expected duplicate probe line_count to cover sampled duplicate keys, got "
            f"{duplicate_probe.get('line_count')!r}."
        )
    if int(duplicate_probe.get("unique_bucket_count") or 0) < expected_sampled_duplicate_keys:
        raise SystemExit(
            "FAIL: expected duplicate probe unique_bucket_count to cover sampled duplicate keys, got "
            f"{duplicate_probe.get('unique_bucket_count')!r}."
        )

probe = step.get("sampled_object_probe") or {}
if int(probe.get("exact_hit_count") or 0) < 1:
    raise SystemExit(f"FAIL: expected sampled exact hits in timeout probe, got {probe!r}.")
if int(probe.get("exact_unresolved_miss_count") or 0) < 1:
    raise SystemExit(f"FAIL: expected sampled unresolved misses in timeout probe, got {probe!r}.")

pool_families = review.get("pool_families") or []
target = None
for family in pool_families:
    if family.get("sampled_low32") == "1b8530fb":
        target = family
        break
if target is None:
    raise SystemExit("FAIL: review did not report the 1b8530fb pool family.")
if target.get("pool_recommendation") != "defer-runtime-pool-semantics":
    raise SystemExit(
        "FAIL: expected 1b8530fb pool recommendation to remain "
        f"'defer-runtime-pool-semantics', got {target.get('pool_recommendation')!r}."
    )
if not target.get("runtime_sample_replacement_id"):
    raise SystemExit("FAIL: expected 1b8530fb pool family to carry a runtime_sample_replacement_id.")

if pool_review.get("pool_recommendation") != "defer-runtime-pool-semantics":
    raise SystemExit(f"FAIL: unexpected pool review recommendation {pool_review.get('pool_recommendation')!r}.")
pool_review_status = pool_review.get("review_status") or "complete"
if pool_review_status == "complete":
    if pool_review.get("runtime_shape_recommendation") != "keep-flat-runtime-binding":
        raise SystemExit(
            "FAIL: expected pool review runtime_shape_recommendation='keep-flat-runtime-binding', "
            f"got {pool_review.get('runtime_shape_recommendation')!r}."
        )
elif pool_review_status == "deferred-no-live-draw-sequence":
    reasons = pool_review.get("recommendation_reasons") or []
    if "defer-to-historical-pool-regression-review" not in reasons:
        raise SystemExit(f"FAIL: expected deferred pool review to explain fallback to historical regression, got {pool_review!r}.")
else:
    raise SystemExit(f"FAIL: unexpected pool review status {pool_review_status!r}.")
if not pool_review.get("runtime_sample_replacement_id"):
    raise SystemExit("FAIL: expected pool review to carry a runtime_sample_replacement_id.")
if pool_review_status == "complete":
    sequence = pool_review.get("sequence_summary") or {}
    surface_map = pool_review.get("surface_map_summary") or {}
    tail_dwell = pool_review.get("tail_dwell") or {}
    if sequence.get("shape_hint") != "rotating-stream-edge-dwell":
        raise SystemExit(f"FAIL: unexpected pool review shape_hint {sequence.get('shape_hint')!r}.")
    if int(surface_map.get("unresolved_count") or -1) != 1:
        raise SystemExit(f"FAIL: unexpected pool review unresolved_count {surface_map.get('unresolved_count')!r}.")
    if not bool(tail_dwell.get("aligns_with_unresolved_slot")):
        raise SystemExit("FAIL: expected tail dwell to align with unresolved slot.")

summary_counts = seam_register.get("summary") or {}
candidate_free_alt_source_available_count = int(summary_counts.get("candidate_free_alt_source_available_count") or 0)
if alt_source_present:
    if candidate_free_alt_source_available_count < 1:
        raise SystemExit(
            "FAIL: expected runtime seam register to include alternate-source-ready candidate-free families, "
            f"got {summary_counts!r}."
        )
else:
    if candidate_free_alt_source_available_count != 0:
        raise SystemExit(
            "FAIL: expected runtime seam register alternate-source-ready family count to remain zero "
            f"without an explicit alternate-source cache, got {summary_counts!r}."
        )
if int(summary_counts.get("candidate_free_review_bounded_probe_count") or 0) != 0:
    raise SystemExit(
        "FAIL: expected runtime seam register candidate_free_review_bounded_probe_count=0 for the "
        f"current selected-package timeout lane, got {summary_counts!r}."
    )
if int(summary_counts.get("pool_conflict_family_count") or 0) < 1:
    raise SystemExit(f"FAIL: expected runtime seam register to include at least one pool-conflict family, got {summary_counts!r}.")
actual_sampled_duplicate_family_count = int(summary_counts.get("sampled_duplicate_family_count") or 0)
if expected_sampled_duplicate_keys > 0:
    if actual_sampled_duplicate_family_count < expected_sampled_duplicate_keys:
        raise SystemExit(f"FAIL: expected runtime seam register to include sampled duplicate families, got {summary_counts!r}.")
else:
    if actual_sampled_duplicate_family_count != 0:
        raise SystemExit(f"FAIL: expected runtime seam register sampled duplicate families to be eliminated, got {summary_counts!r}.")
candidate_free = {
    row.get("sampled_low32"): row for row in seam_register.get("candidate_free_absent_families") or []
}
for sampled_low32 in ("91887078", "6af0d9ca", "e0d4d0dc"):
    row = candidate_free.get(sampled_low32)
    if row is None:
        raise SystemExit(f"FAIL: expected runtime seam register to include candidate-free family {sampled_low32}.")
    alt_candidate_count = int(row.get("alternate_source_candidate_count") or 0)
    if alt_source_present:
        if alt_candidate_count < 1:
            raise SystemExit(f"FAIL: expected alternate-source candidates for {sampled_low32}, got {row!r}.")
    else:
        if alt_candidate_count != 0:
            raise SystemExit(
                "FAIL: expected no alternate-source candidates without an explicit alternate-source cache, "
                f"got {row!r}."
            )
duplicate_family = next((row for row in seam_register.get("sampled_duplicate_families") or [] if row.get("sampled_low32") == "7701ac09"), None)
if expected_sampled_duplicate_keys > 0:
    if duplicate_family is None:
        raise SystemExit("FAIL: expected runtime seam register to include sampled duplicate family 7701ac09.")
    if duplicate_family.get("selector") != "0000000071c71cdd":
        raise SystemExit(f"FAIL: unexpected runtime seam duplicate selector {duplicate_family.get('selector')!r}.")
    if not duplicate_family.get("replacement_id"):
        raise SystemExit("FAIL: expected runtime seam duplicate family 7701ac09 to carry an active replacement_id.")
    if sampled_duplicate_review.get("recommendation") != "keep-runtime-winner-rule-and-defer-offline-dedupe":
        raise SystemExit(f"FAIL: unexpected sampled duplicate review {sampled_duplicate_review!r}.")
    if sampled_duplicate_review.get("selector_candidate_count") != 2:
        raise SystemExit(f"FAIL: unexpected sampled duplicate review selector candidate count {sampled_duplicate_review!r}.")
else:
    if duplicate_family is not None:
        raise SystemExit(f"FAIL: expected runtime seam duplicate family 7701ac09 to be eliminated, got {duplicate_family!r}.")
    if sampled_duplicate_review:
        raise SystemExit(f"FAIL: expected no sampled duplicate review payload after duplicate elimination, got {sampled_duplicate_review!r}.")
if (pool_regression_review.get("recommendation") or {}).get("recommendation") != "keep-flat-runtime-binding":
    raise SystemExit(f"FAIL: unexpected pool regression recommendation {pool_regression_review!r}.")
if (pool_regression_review.get("recommendation") or {}).get("pool_follow_up") != "defer-runtime-pool-semantics":
    raise SystemExit(f"FAIL: unexpected pool regression follow-up {pool_regression_review!r}.")
if [case.get("label") for case in (pool_regression_review.get("cases") or [])] != ["flat", "dual", "ordered-only"]:
    raise SystemExit(f"FAIL: unexpected pool regression cases {pool_regression_review!r}.")

if alt_source_present:
    alt_groups = {str((group.get("signature") or {}).get("sampled_low32") or "").lower(): group for group in alternate_source_review.get("groups") or []}
    expected_alt_counts = {"91887078": 1, "6af0d9ca": 7, "e0d4d0dc": 5}
    for sampled_low32, expected_count in expected_alt_counts.items():
        group = alt_groups.get(sampled_low32)
        if group is None:
            raise SystemExit(f"FAIL: expected alternate-source review to include {sampled_low32}.")
        seeded = group.get("seeded_transport_pool") or {}
        if int(seeded.get("candidate_count") or 0) != expected_count:
            raise SystemExit(
                f"FAIL: expected alternate-source review candidate_count={expected_count} for {sampled_low32}, "
                f"got {seeded.get('candidate_count')!r}."
            )
else:
    if alternate_source_review.get("json_path") or alternate_source_review.get("group_count") or alternate_source_review.get("available_group_count") or alternate_source_review.get("total_candidate_count") or (alternate_source_review.get("groups") or []):
        raise SystemExit(f"FAIL: unexpected alternate-source review payload without explicit alternate-source cache: {alternate_source_review!r}.")

if guard_paths_present:
    activation_summary = step.get("alternate_source_activation_review") or {}
    cross_scene_summary = step.get("sampled_cross_scene_review") or {}
    duplicate_reviews = step.get("sampled_duplicate_reviews") or []
    pool_regression_summary = step.get("sampled_pool_regression_review") or {}
    activation_families = activation_summary.get("families") or []
    families = cross_scene_summary.get("families") or []
    if len(families) < 1:
        raise SystemExit(f"FAIL: expected cross-scene review families in summary, got {cross_scene_summary!r}.")
    if len(cross_scene_review.get("families") or []) < 1:
        raise SystemExit(f"FAIL: expected cross-scene review payload, got {cross_scene_review!r}.")
    if alt_source_present:
        if len(activation_families) < 3:
            raise SystemExit(f"FAIL: expected activation review families in summary, got {activation_summary!r}.")
        if len(alternate_source_activation_review.get("families") or []) < 3:
            raise SystemExit(
                "FAIL: expected alternate-source activation review payload to cover the triangle trio, "
                f"got {alternate_source_activation_review!r}."
            )
        if int((activation_summary.get("summary") or {}).get("review_bounded_probe_count") or 0) != 0:
            raise SystemExit(f"FAIL: unexpected activation review summary {activation_summary!r}.")
        if int((activation_summary.get("summary") or {}).get("shared_scene_blocked_count") or 0) < 3:
            raise SystemExit(f"FAIL: expected shared-scene blocked activation review families, got {activation_summary!r}.")
        activation_by_low32 = {
            str(row.get("sampled_low32") or "").lower(): row
            for row in activation_families
        }
        activation_payload_by_low32 = {
            str(row.get("sampled_low32") or "").lower(): row
            for row in (alternate_source_activation_review.get("families") or [])
        }
        for sampled_low32 in ("91887078", "6af0d9ca", "e0d4d0dc"):
            summary_row = activation_by_low32.get(sampled_low32)
            payload_row = activation_payload_by_low32.get(sampled_low32)
            if summary_row is None or payload_row is None:
                raise SystemExit(
                    f"FAIL: expected activation review to include {sampled_low32}, "
                    f"got summary={activation_summary!r} payload={alternate_source_activation_review!r}."
                )
            if summary_row.get("activation_status") != "shared-scene-source-backed-candidates":
                raise SystemExit(f"FAIL: unexpected activation summary row for {sampled_low32}: {summary_row!r}.")
            if payload_row.get("activation_status") != "shared-scene-source-backed-candidates":
                raise SystemExit(f"FAIL: unexpected activation payload row for {sampled_low32}: {payload_row!r}.")
    else:
        if activation_summary.get("json_path") or activation_summary.get("markdown_path") or (activation_summary.get("summary") or {}) or activation_families or alternate_source_activation_review:
            raise SystemExit(f"FAIL: unexpected alternate-source activation review payload without explicit alternate-source cache: {activation_summary!r} / {alternate_source_activation_review!r}.")
    if world_guard_present and "world" not in (cross_scene_summary.get("guard_labels") or []):
        raise SystemExit(f"FAIL: expected world guard label in cross-scene summary, got {cross_scene_summary!r}.")
    if expected_sampled_duplicate_keys > 0:
        if len(duplicate_reviews) < 1 or duplicate_reviews[0].get("recommendation") != "keep-runtime-winner-rule-and-defer-offline-dedupe":
            raise SystemExit(f"FAIL: unexpected duplicate review summary {duplicate_reviews!r}.")
    else:
        if duplicate_reviews:
            raise SystemExit(f"FAIL: expected duplicate review summary to be empty after duplicate elimination, got {duplicate_reviews!r}.")
    if pool_regression_summary.get("recommendation") != "keep-flat-runtime-binding":
        raise SystemExit(f"FAIL: unexpected pool regression summary {pool_regression_summary!r}.")
PY

echo "emu_conformance_paper_mario_selected_package_timeout_validation: PASS ($CACHE_PATH)"
