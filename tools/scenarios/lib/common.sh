#!/usr/bin/env bash

scenario_source_runtime_env() {
  local runtime_env="$1"
  # Scenario runtime env files define both local shell vars and process env overrides.
  # Auto-export while sourcing so renderer/debug toggles reliably reach RetroArch/core children.
  set -a
  # shellcheck disable=SC1090
  source "$runtime_env"
  set +a
}

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

scenario_find_single_capture() {
  local bundle_dir="$1"
  find "$bundle_dir/captures" -maxdepth 1 -type f | sort
}

scenario_extract_hires_log_evidence() {
  local bundle_dir="$1"
  local output_path="$2"

  python - "$bundle_dir" "$output_path" <<'PY'
import json
import re
import sys
import gzip
import struct
from pathlib import Path

bundle_dir = Path(sys.argv[1])
output_path = Path(sys.argv[2])
log_path = bundle_dir / "logs" / "retroarch.log"
TXCACHE_FORMAT_VERSION = 0x08000000

result = {
    "available": False,
    "log_path": str(log_path),
    "cache_loaded": False,
    "cache_entries": None,
    "cache_path": None,
    "cache_load_failed": False,
    "missing_cache_path": False,
    "disabled_reason": None,
    "capabilities": None,
    "summary": None,
    "debug_line_counts": {
        "hit": 0,
        "miss": 0,
        "filtered": 0,
        "tlut_update": 0,
    },
    "bucket_summaries": {
        "hit": {
            "unique_bucket_count": 0,
            "top_buckets": [],
        },
        "miss": {
            "unique_bucket_count": 0,
            "top_buckets": [],
        },
        "filtered": {
            "unique_bucket_count": 0,
            "top_buckets": [],
        },
        "tlut_update": {
            "unique_bucket_count": 0,
            "top_buckets": [],
        },
    },
    "debug_filter": None,
    "pack_crosscheck": {
        "available": False,
        "cache_path": None,
        "miss_event_counts": {
            "checksum_absent": 0,
            "same_texture_crc_other_palette": 0,
            "other_formatsize_only": 0,
            "exact_or_generic_present": 0,
        },
        "unique_checksum_counts": {
            "checksum_absent": 0,
            "same_texture_crc_other_palette": 0,
            "other_formatsize_only": 0,
            "exact_or_generic_present": 0,
        },
        "top_absent_buckets": [],
        "top_same_texture_crc_other_palette_buckets": [],
        "top_other_formatsize_buckets": [],
        "top_exact_or_generic_present_buckets": [],
    },
    "sample_events": [],
}

if not log_path.is_file():
    output_path.write_text(json.dumps(result, indent=2) + "\n")
    raise SystemExit(0)

cache_loaded_re = re.compile(r"Hi-res replacement cache loaded: (\d+) entries from (.+)")
capability_re = re.compile(
    r"Hi-res capability check: descriptor_indexing=(\d+) runtime_descriptor_array=(\d+) sampled_image_array_non_uniform_indexing=(\d+) descriptor_binding_variable_descriptor_count=(\d+) descriptor_binding_partially_bound=(\d+) descriptor_binding_update_after_bind=(\d+) maxDescriptorSetUpdateAfterBindSampledImages=(\d+) cache_path=(.+)\."
)
disabled_re = re.compile(r"Hi-res textures requested, but disabled: (.+) \(maxDescriptorSetUpdateAfterBindSampledImages=(\d+), required>=(\d+)\)\.")
summary_re = re.compile(
    r"Hi-res keying summary: lookups=(\d+) hits=(\d+) misses=(\d+)(?: filtered=(\d+))?(?: block_probe_hits=(\d+))? provider=(on|off)\."
)
hit_miss_re = re.compile(r"Hi-res keying (hit|miss): (.+)")
filtered_re = re.compile(r"Hi-res keying filtered: reason=([^\s]+) (.+)")
tlut_re = re.compile(r"Hi-res keying TLUT update: (.+)")
filter_config_re = re.compile(r"Hi-res debug filter: allow_tile=(\d+) allow_block=(\d+) signature_count=(\d+)\.")
field_re = re.compile(r"(\w+)=([^\s]+)")

bucket_maps = {
    "hit": {},
    "miss": {},
    "filtered": {},
    "tlut_update": {},
}
miss_records = []

def parse_fields(detail):
    fields = {}
    for key, value in field_re.findall(detail):
        fields[key] = value.rstrip(".")
    return fields

def get_bucket_identity(kind, fields):
    if kind in ("hit", "miss"):
        return tuple((key, fields.get(key)) for key in ("mode", "fmt", "siz", "wh", "fs", "tile"))
    if kind == "filtered":
        return tuple((key, fields.get(key)) for key in ("reason", "mode", "fmt", "siz", "wh", "fs", "tile"))
    return tuple((key, fields.get(key)) for key in ("bytes", "tile"))

def update_bucket(kind, detail):
    fields = parse_fields(detail)
    identity = get_bucket_identity(kind, fields)
    bucket = bucket_maps[kind].setdefault(
        identity,
        {
            "count": 0,
            "sample_detail": detail,
            "fields": {key: value for key, value in identity},
            "unique_keys": set(),
            "unique_addrs": set(),
        },
    )
    bucket["count"] += 1
    key_value = fields.get("key")
    if key_value:
        bucket["unique_keys"].add(key_value)
    addr_value = fields.get("addr")
    if addr_value:
        bucket["unique_addrs"].add(addr_value)

def finalize_bucket_summary(kind):
    raw_buckets = []
    for bucket in bucket_maps[kind].values():
        raw_buckets.append(
            {
                "count": bucket["count"],
                "signature": " ".join(
                    f"{key}={value}"
                    for key, value in bucket["fields"].items()
                    if value is not None
                ),
                "fields": bucket["fields"],
                "sample_detail": bucket["sample_detail"],
                "unique_key_count": len(bucket["unique_keys"]),
                "unique_addr_count": len(bucket["unique_addrs"]),
            }
        )
    raw_buckets.sort(
        key=lambda item: (
            -item["count"],
            item["signature"],
        )
    )
    result["bucket_summaries"][kind] = {
        "unique_bucket_count": len(raw_buckets),
        "top_buckets": raw_buckets[:10],
    }

def parse_hts_cache_index(cache_path):
    data = cache_path.read_bytes()
    if len(data) < 16:
        return {}

    version = struct.unpack_from("<i", data, 0)[0]
    if version == TXCACHE_FORMAT_VERSION:
        storage_pos = struct.unpack_from("<q", data, 8)[0]
        old_version = False
    else:
        storage_pos = struct.unpack_from("<q", data, 4)[0]
        old_version = True

    if storage_pos <= 0 or storage_pos + 4 > len(data):
        return {}

    storage_size = struct.unpack_from("<i", data, storage_pos)[0]
    offset = storage_pos + 4
    entries = {}

    for _ in range(storage_size):
        if offset + 16 > len(data):
            break
        checksum64 = struct.unpack_from("<Q", data, offset)[0]
        packed = struct.unpack_from("<q", data, offset + 8)[0]
        offset += 16

        record_offset = packed & 0x0000ffffffffffff
        formatsize = (packed >> 48) & 0xffff
        if record_offset + 17 > len(data):
            continue

        pos = record_offset + 17
        if not old_version:
            if pos + 2 > len(data):
                continue
            record_formatsize = struct.unpack_from("<H", data, pos)[0]
            pos += 2
            if formatsize == 0:
                formatsize = record_formatsize

        entries.setdefault(checksum64, set()).add(formatsize)

    return entries

def parse_htc_cache_index(cache_path):
    entries = {}
    with gzip.open(cache_path, "rb") as fp:
        version_raw = fp.read(4)
        if len(version_raw) != 4:
            return entries
        version = struct.unpack("<i", version_raw)[0]
        old_version = version != TXCACHE_FORMAT_VERSION

        if not old_version:
            config_raw = fp.read(4)
            if len(config_raw) != 4:
                return entries

        while True:
            checksum_raw = fp.read(8)
            if not checksum_raw:
                break
            if len(checksum_raw) != 8:
                break
            checksum64 = struct.unpack("<Q", checksum_raw)[0]

            header = fp.read(4 + 4 + 4 + 2 + 2 + 1)
            if len(header) != 17:
                break

            formatsize = 0
            if not old_version:
                formatsize_raw = fp.read(2)
                if len(formatsize_raw) != 2:
                    break
                formatsize = struct.unpack("<H", formatsize_raw)[0]

            data_size_raw = fp.read(4)
            if len(data_size_raw) != 4:
                break
            data_size = struct.unpack("<I", data_size_raw)[0]
            if data_size < 0:
                break

            skipped = fp.read(data_size)
            if len(skipped) != data_size:
                break

            entries.setdefault(checksum64, set()).add(formatsize)

    return entries

def load_cache_index(cache_path_str):
    if not cache_path_str:
        return None

    cache_path = Path(cache_path_str)
    if not cache_path.is_file():
        return None

    suffix = cache_path.suffix.lower()
    if suffix == ".hts":
        return parse_hts_cache_index(cache_path)
    if suffix == ".htc":
        return parse_htc_cache_index(cache_path)
    return None

def finalize_pack_crosscheck():
    cache_entries = load_cache_index(result["cache_path"])
    if cache_entries is None:
        return

    result["pack_crosscheck"]["available"] = True
    result["pack_crosscheck"]["cache_path"] = result["cache_path"]

    category_buckets = {
        "checksum_absent": {},
        "same_texture_crc_other_palette": {},
        "other_formatsize_only": {},
        "exact_or_generic_present": {},
    }
    unique_checksums = {
        "checksum_absent": set(),
        "same_texture_crc_other_palette": set(),
        "other_formatsize_only": set(),
        "exact_or_generic_present": set(),
    }
    low32_index = {}
    for checksum64, formats in cache_entries.items():
        texture_crc = checksum64 & 0xffffffff
        low32_index.setdefault(texture_crc, set()).update(formats)

    for record in miss_records:
        checksum64 = record["checksum64"]
        formatsize = record["formatsize"]
        signature = record["signature"]

        available_formats = cache_entries.get(checksum64)
        texture_crc = checksum64 & 0xffffffff
        low32_formats = low32_index.get(texture_crc)
        if available_formats is None:
            if low32_formats is not None and (formatsize in low32_formats or 0 in low32_formats):
                category = "same_texture_crc_other_palette"
            else:
                category = "checksum_absent"
        elif formatsize in available_formats or 0 in available_formats:
            category = "exact_or_generic_present"
        else:
            category = "other_formatsize_only"

        result["pack_crosscheck"]["miss_event_counts"][category] += 1
        unique_checksums[category].add(checksum64)

        bucket = category_buckets[category].setdefault(
            signature,
            {
                "count": 0,
                "sample_detail": record["detail"],
            },
        )
        bucket["count"] += 1

    for category, values in unique_checksums.items():
        result["pack_crosscheck"]["unique_checksum_counts"][category] = len(values)

    def write_bucket_list(field_name, bucket_map):
        items = [
            {
                "signature": signature,
                "count": payload["count"],
                "sample_detail": payload["sample_detail"],
            }
            for signature, payload in bucket_map.items()
        ]
        items.sort(key=lambda item: (-item["count"], item["signature"]))
        result["pack_crosscheck"][field_name] = items[:10]

    write_bucket_list("top_absent_buckets", category_buckets["checksum_absent"])
    write_bucket_list("top_same_texture_crc_other_palette_buckets", category_buckets["same_texture_crc_other_palette"])
    write_bucket_list("top_other_formatsize_buckets", category_buckets["other_formatsize_only"])
    write_bucket_list("top_exact_or_generic_present_buckets", category_buckets["exact_or_generic_present"])

for line in log_path.read_text(errors="replace").splitlines():
    if "Hi-res replacement enabled, but cache path is empty." in line:
        result["available"] = True
        result["missing_cache_path"] = True
        continue

    m = capability_re.search(line)
    if m:
        result["available"] = True
        cache_path = m.group(8).strip()
        result["capabilities"] = {
            "descriptor_indexing": bool(int(m.group(1))),
            "runtime_descriptor_array": bool(int(m.group(2))),
            "sampled_image_array_non_uniform_indexing": bool(int(m.group(3))),
            "descriptor_binding_variable_descriptor_count": bool(int(m.group(4))),
            "descriptor_binding_partially_bound": bool(int(m.group(5))),
            "descriptor_binding_update_after_bind": bool(int(m.group(6))),
            "max_descriptor_set_update_after_bind_sampled_images": int(m.group(7)),
            "cache_path": None if cache_path == "<empty>" else cache_path,
        }
        if result["capabilities"]["cache_path"] is not None:
            result["cache_path"] = result["capabilities"]["cache_path"]
        continue

    m = disabled_re.search(line)
    if m:
        result["available"] = True
        result["disabled_reason"] = {
            "reason": m.group(1).strip(),
            "max_descriptor_set_update_after_bind_sampled_images": int(m.group(2)),
            "required_minimum": int(m.group(3)),
        }
        continue

    if "Hi-res replacement cache load failed for path:" in line:
        result["available"] = True
        result["cache_load_failed"] = True
        result["cache_path"] = line.rsplit(":", 1)[-1].strip()
        continue

    m = cache_loaded_re.search(line)
    if m:
        result["available"] = True
        result["cache_loaded"] = True
        result["cache_entries"] = int(m.group(1))
        result["cache_path"] = m.group(2).strip()
        continue

    m = summary_re.search(line)
    if m:
        result["available"] = True
        result["summary"] = {
            "lookups": int(m.group(1)),
            "hits": int(m.group(2)),
            "misses": int(m.group(3)),
            "filtered": int(m.group(4) or 0),
            "block_probe_hits": int(m.group(5) or 0),
            "provider": m.group(6),
        }
        continue

    m = filter_config_re.search(line)
    if m:
        result["available"] = True
        result["debug_filter"] = {
            "allow_tile": bool(int(m.group(1))),
            "allow_block": bool(int(m.group(2))),
            "signature_count": int(m.group(3)),
        }
        continue

    m = hit_miss_re.search(line)
    if m:
        result["available"] = True
        kind = m.group(1)
        detail = m.group(2).strip()
        result["debug_line_counts"][kind] += 1
        update_bucket(kind, detail)
        if kind == "miss":
            fields = parse_fields(detail)
            key_value = fields.get("key")
            formatsize_value = fields.get("fs")
            if key_value is not None and formatsize_value is not None:
                miss_records.append(
                    {
                        "checksum64": int(key_value, 16),
                        "formatsize": int(formatsize_value),
                        "signature": " ".join(
                            f"{key}={fields.get(key)}"
                            for key in ("mode", "fmt", "siz", "wh", "fs", "tile")
                            if fields.get(key) is not None
                        ),
                        "detail": detail,
                    }
                )
        if len(result["sample_events"]) < 20:
            result["sample_events"].append({
                "kind": kind,
                "detail": detail,
            })
        continue

    m = filtered_re.search(line)
    if m:
        result["available"] = True
        detail = f"reason={m.group(1)} {m.group(2).strip()}"
        result["debug_line_counts"]["filtered"] += 1
        update_bucket("filtered", detail)
        if len(result["sample_events"]) < 20:
            result["sample_events"].append({
                "kind": "filtered",
                "detail": detail,
            })
        continue

    m = tlut_re.search(line)
    if m:
        result["available"] = True
        detail = m.group(1).strip()
        result["debug_line_counts"]["tlut_update"] += 1
        update_bucket("tlut_update", detail)
        if len(result["sample_events"]) < 20:
            result["sample_events"].append({
                "kind": "tlut_update",
                "detail": detail,
            })

for kind in ("hit", "miss", "filtered", "tlut_update"):
    finalize_bucket_summary(kind)
finalize_pack_crosscheck()

output_path.write_text(json.dumps(result, indent=2) + "\n")
PY
}

scenario_verify_paper_mario_fixture() {
  local bundle_dir="$1"
  local output_path="$2"
  local fixture_id="$3"
  local expected_screenshot_sha256="$4"
  local expected_init_symbol="$5"
  local expected_step_symbol="$6"

  python - "$bundle_dir" "$output_path" "$fixture_id" "$expected_screenshot_sha256" "$expected_init_symbol" "$expected_step_symbol" <<'PY'
import json
import hashlib
import sys
from pathlib import Path

bundle_dir = Path(sys.argv[1])
output_path = Path(sys.argv[2])
fixture_id = sys.argv[3]
expected_screenshot_sha256 = sys.argv[4]
expected_init_symbol = sys.argv[5]
expected_step_symbol = sys.argv[6]

captures = sorted((bundle_dir / "captures").glob("*"))
semantic_path = bundle_dir / "traces" / "paper-mario-game-status.json"
hires_path = bundle_dir / "traces" / "hires-evidence.json"

result = {
    "fixture_id": fixture_id,
    "passed": True,
    "checks": {
        "single_capture": False,
        "screenshot_sha256": None,
        "screenshot_sha256_match": None,
        "semantic_trace_present": semantic_path.is_file(),
        "cur_game_mode_match": None,
        "hires_evidence_present": hires_path.is_file(),
    },
    "expected": {
        "screenshot_sha256": expected_screenshot_sha256 or None,
        "init_symbol": expected_init_symbol or None,
        "step_symbol": expected_step_symbol or None,
    },
    "actual": {
        "capture_path": None,
        "init_symbol": None,
        "step_symbol": None,
    },
    "failures": [],
}

if len(captures) != 1:
    result["passed"] = False
    result["failures"].append(f"Expected exactly 1 capture, found {len(captures)}.")
else:
    capture_path = captures[0]
    result["checks"]["single_capture"] = True
    result["actual"]["capture_path"] = str(capture_path)
    sha256 = hashlib.sha256(capture_path.read_bytes()).hexdigest()
    result["checks"]["screenshot_sha256"] = sha256
    if expected_screenshot_sha256:
        result["checks"]["screenshot_sha256_match"] = (sha256 == expected_screenshot_sha256)
        if sha256 != expected_screenshot_sha256:
            result["passed"] = False
            result["failures"].append(
                f"Capture hash mismatch: expected {expected_screenshot_sha256}, got {sha256}."
            )

if semantic_path.is_file():
    semantic = json.loads(semantic_path.read_text())
    cur_game_mode = semantic.get("paper_mario_us", {}).get("cur_game_mode", {})
    init_symbol = cur_game_mode.get("init_symbol")
    step_symbol = cur_game_mode.get("step_symbol")
    result["actual"]["init_symbol"] = init_symbol
    result["actual"]["step_symbol"] = step_symbol
    if expected_init_symbol or expected_step_symbol:
        matched = (
            (not expected_init_symbol or init_symbol == expected_init_symbol)
            and
            (not expected_step_symbol or step_symbol == expected_step_symbol)
        )
        result["checks"]["cur_game_mode_match"] = matched
        if not matched:
            result["passed"] = False
            result["failures"].append(
                "CurGameMode mismatch: "
                f"expected ({expected_init_symbol}, {expected_step_symbol}), "
                f"got ({init_symbol}, {step_symbol})."
            )
else:
    result["passed"] = False
    result["failures"].append("Missing Paper Mario semantic trace JSON.")

output_path.write_text(json.dumps(result, indent=2) + "\n")
if not result["passed"]:
    raise SystemExit(1)
PY
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
