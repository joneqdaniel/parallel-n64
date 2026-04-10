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

scenario_default_paper_mario_hires_cache() {
  local repo_root="$1"
  local -a candidates=(
    "$repo_root/artifacts/hts2phrb-review/20260408-pm64-all-families-authority-context-abs-summary/package.phrb"
    "$repo_root/artifacts/hts2phrb-review/20260407-pm64-all-families-authority-context-root/package.phrb"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "No default Paper Mario PHRB runtime cache found. Generate one with hts2phrb or the full-cache refresh workflow before using the default authority scenarios." >&2
  return 1
}

scenario_configure_hires_runtime_env_for_cache() {
  local cache_path="$1"
  local suffix="${cache_path##*.}"
  suffix="${suffix,,}"

  if [[ "$suffix" == "phrb" ]]; then
    export PARALLEL_RDP_HIRES_SAMPLED_OBJECT_LOOKUP="${PARALLEL_RDP_HIRES_SAMPLED_OBJECT_LOOKUP:-1}"
    export PARALLEL_RDP_HIRES_SAMPLED_OBJECT_PROBE="${PARALLEL_RDP_HIRES_SAMPLED_OBJECT_PROBE:-1}"
  else
    export PARALLEL_RDP_HIRES_SAMPLED_OBJECT_LOOKUP="${PARALLEL_RDP_HIRES_SAMPLED_OBJECT_LOOKUP:-0}"
    export PARALLEL_RDP_HIRES_SAMPLED_OBJECT_PROBE="${PARALLEL_RDP_HIRES_SAMPLED_OBJECT_PROBE:-0}"
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
    "provenance": {
        "available": False,
        "line_count": 0,
        "outcome_counts": {},
        "source_class_counts": {},
        "provenance_class_counts": {},
        "top_buckets": [],
    },
    "draw_usage": {
        "available": False,
        "line_count": 0,
        "draw_class_counts": {},
        "copy_counts": {},
        "top_buckets": [],
    },
    "sampler_usage": {
        "available": False,
        "line_count": 0,
        "top_buckets": [],
    },
    "ci_palette_probe": {
        "families": [],
        "usages": [],
        "emulated_tmem": [],
        "logical_views": [],
    },
    "sampled_object_probe": {
        "available": False,
        "line_count": 0,
        "unique_group_count": 0,
        "groups": [],
        "top_groups": [],
        "exact_hit_count": 0,
        "unique_exact_hit_bucket_count": 0,
        "top_exact_hit_buckets": [],
        "exact_miss_count": 0,
        "unique_exact_miss_bucket_count": 0,
        "top_exact_miss_buckets": [],
        "exact_conflict_miss_count": 0,
        "unique_exact_conflict_miss_bucket_count": 0,
        "top_exact_conflict_miss_buckets": [],
        "exact_unresolved_miss_count": 0,
        "unique_exact_unresolved_miss_bucket_count": 0,
        "top_exact_unresolved_miss_buckets": [],
        "family_line_count": 0,
        "unique_exact_family_bucket_count": 0,
        "top_exact_family_buckets": [],
    },
    "sampled_pool_stream_probe": {
        "available": False,
        "line_count": 0,
        "unique_bucket_count": 0,
        "top_buckets": [],
        "family_count": 0,
        "top_families": [],
    },
    "sampled_duplicate_probe": {
        "available": False,
        "line_count": 0,
        "unique_bucket_count": 0,
        "top_buckets": [],
    },
}

if not log_path.is_file():
    output_path.write_text(json.dumps(result, indent=2) + "\n")
    raise SystemExit(0)

cache_loaded_re = re.compile(
    r"Hi-res replacement cache loaded: (\d+) entries from (.+?)(?: \(source mode ([^)]+)\))?$"
)
cache_failed_re = re.compile(
    r"Hi-res replacement cache load failed for path: (.+?)(?: \(source mode ([^)]+)\))?$"
)
capability_re = re.compile(
    r"Hi-res capability check: descriptor_indexing=(\d+) runtime_descriptor_array=(\d+) sampled_image_array_non_uniform_indexing=(\d+) descriptor_binding_variable_descriptor_count=(\d+) descriptor_binding_partially_bound=(\d+) descriptor_binding_update_after_bind=(\d+) maxDescriptorSetUpdateAfterBindSampledImages=(\d+) cache_path=(.+?)(?: source_mode=([^.]+))?\.$"
)
disabled_re = re.compile(r"Hi-res textures requested, but disabled: (.+) \(maxDescriptorSetUpdateAfterBindSampledImages=(\d+), required>=(\d+)\)\.")
summary_re = re.compile(
    r"Hi-res keying summary: lookups=(\d+) hits=(\d+) misses=(\d+)"
    r"(?: filtered=(\d+))?"
    r"(?: block_probe_hits=(\d+))?"
    r"(?: compat_draw_hits=(\d+))?"
    r" provider=(on|off)"
    r"(?: entries=(\d+) native_sampled=(\d+) compat=(\d+) sampled_index=(\d+)"
    r"(?: sampled_dupe_keys=(\d+) sampled_dupe_entries=(\d+))?"
    r" sampled_families=(\d+) compat_low32_families=(\d+) sources\(phrb=(\d+) hts=(\d+) htc=(\d+)\))?"
    r"(?: descriptor_paths\(sampled=(\d+) native_checksum=(\d+) generic=(\d+) compat=(\d+)\))?"
    r"(?: sampled_detail\(family_singleton=(\d+) ordered_surface_singleton=(\d+)(?: exact_selector=(\d+))?\))?"
    r"(?: generic_detail\(identity_assisted=(\d+) plain=(\d+)(?: native=(\d+) compat=(\d+) unknown=(\d+))?\))?"
    r"\."
)
native_checksum_detail_re = re.compile(
    r"Hi-res native checksum detail: exact=(\d+) identity_assisted=(\d+) generic_fallback=(\d+)\."
)
hit_miss_re = re.compile(r"Hi-res keying (hit|miss): (.+)")
filtered_re = re.compile(r"Hi-res keying filtered: reason=([^\s]+) (.+)")
tlut_re = re.compile(r"Hi-res keying TLUT update: (.+)")
filter_config_re = re.compile(r"Hi-res debug filter: allow_tile=(\d+) allow_block=(\d+) signature_count=(\d+)\.")
ci_family_re = re.compile(r"Hi-res CI palette probe family: (.+)")
ci_usage_re = re.compile(r"Hi-res CI palette probe usage: (.+)")
ci_emulated_tmem_re = re.compile(r"Hi-res CI palette probe emulated-tmem: (.+)")
ci_logical_view_re = re.compile(r"Hi-res CI palette probe logical-view: (.+)")
provenance_re = re.compile(r"Hi-res keying provenance: (.+)")
draw_usage_re = re.compile(r"Hi-res draw usage: (.+)")
sampled_object_re = re.compile(r"Hi-res sampled-object probe: (.+)")
sampled_object_exact_hit_re = re.compile(r"Hi-res sampled-object exact hit: (.+)")
sampled_object_exact_miss_re = re.compile(r"Hi-res sampled-object exact miss: (.+)")
sampled_object_family_re = re.compile(r"Hi-res sampled-object family: (.+)")
sampled_pool_stream_re = re.compile(r"Hi-res sampled pool stream: (.+)")
sampled_duplicate_re = re.compile(r"Hi-res sampled duplicate: (.+)")
field_re = re.compile(r"(\w+)=([^\s]+)")

bucket_maps = {
    "hit": {},
    "miss": {},
    "filtered": {},
    "tlut_update": {},
}
miss_records = []
provenance_buckets = {}
draw_usage_buckets = {}
sampler_usage_buckets = {}
sampled_object_buckets = {}
sampled_object_exact_hit_buckets = {}
sampled_object_exact_miss_buckets = {}
sampled_object_family_buckets = {}
sampled_pool_stream_buckets = {}
sampled_pool_stream_family_buckets = {}
sampled_duplicate_buckets = {}
resolution_reason_counts = {}

def parse_fields(detail):
    fields = {}
    for key, value in field_re.findall(detail):
        fields[key] = value.rstrip(".")
    return fields

def get_bucket_identity(kind, fields):
    if kind in ("hit", "miss"):
        return tuple((key, fields.get(key)) for key in ("mode", "fmt", "siz", "wh", "fs", "tile", "descriptor_path"))
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

def increment_counter(counter_map, key):
    if not key:
        return
    counter_map[key] = counter_map.get(key, 0) + 1

def classify_entry_class(native_sampled_entry_count, compat_entry_count):
    native_sampled_entry_count = int(native_sampled_entry_count or 0)
    compat_entry_count = int(compat_entry_count or 0)
    if native_sampled_entry_count > 0 and compat_entry_count == 0:
        return "native-sampled-only"
    if native_sampled_entry_count == 0 and compat_entry_count > 0:
        return "compat-only"
    if native_sampled_entry_count > 0 and compat_entry_count > 0:
        return "mixed-native-and-compat"
    return "none"

def classify_descriptor_path_class(descriptor_path_counts):
    descriptor_path_counts = descriptor_path_counts or {}
    active_paths = [
        key
        for key in ("sampled", "native_checksum", "generic", "compat")
        if int(descriptor_path_counts.get(key, 0) or 0) > 0
    ]
    if not active_paths:
        return "none"
    if len(active_paths) == 1:
        return f"{active_paths[0]}-only"
    return "mixed-" + "-".join(active_paths)

def finalize_provenance_summary():
    items = [
        {
            "signature": signature,
            "count": payload["count"],
            "fields": payload["fields"],
            "sample_detail": payload["sample_detail"],
        }
        for signature, payload in provenance_buckets.items()
    ]
    items.sort(key=lambda item: (-item["count"], item["signature"]))
    result["provenance"]["top_buckets"] = items[:10]

def finalize_draw_usage_summary():
    items = [
        {
            "signature": signature,
            "count": payload["count"],
            "fields": payload["fields"],
            "sample_detail": payload["sample_detail"],
        }
        for signature, payload in draw_usage_buckets.items()
    ]
    items.sort(key=lambda item: (-item["count"], item["signature"]))
    result["draw_usage"]["top_buckets"] = items[:10]

def finalize_sampler_usage_summary():
    items = [
        {
            "signature": signature,
            "count": payload["count"],
            "fields": payload["fields"],
            "sample_detail": payload["sample_detail"],
        }
        for signature, payload in sampler_usage_buckets.items()
    ]
    items.sort(key=lambda item: (-item["count"], item["signature"]))
    result["sampler_usage"]["top_buckets"] = items[:10]

def finalize_sampled_object_summary():
    items = []
    for signature, payload in sampled_object_buckets.items():
        items.append(
            {
                "signature": signature,
                "count": payload["count"],
                "fields": payload["fields"],
                "sample_detail": payload["sample_detail"],
                "upload_low32s": [
                    {"value": value, "count": count}
                    for value, count in sorted(payload["upload_low32s"].items(), key=lambda item: (-item[1], item[0]))
                ],
                "upload_pcrcs": [
                    {"value": value, "count": count}
                    for value, count in sorted(payload["upload_pcrcs"].items(), key=lambda item: (-item[1], item[0]))
                ],
            }
        )
    items.sort(key=lambda item: (-item["count"], item["signature"]))
    result["sampled_object_probe"]["unique_group_count"] = len(items)
    result["sampled_object_probe"]["groups"] = [item["fields"] for item in items[:20]]
    result["sampled_object_probe"]["top_groups"] = items[:10]

    exact_hit_items = [
        {
            "signature": signature,
            "count": payload["count"],
            "fields": payload["fields"],
            "sample_detail": payload["sample_detail"],
        }
        for signature, payload in sampled_object_exact_hit_buckets.items()
    ]
    exact_hit_items.sort(key=lambda item: (-item["count"], item["signature"]))
    result["sampled_object_probe"]["unique_exact_hit_bucket_count"] = len(exact_hit_items)
    result["sampled_object_probe"]["top_exact_hit_buckets"] = exact_hit_items[:10]

    exact_miss_items = [
        {
            "signature": signature,
            "count": payload["count"],
            "fields": payload["fields"],
            "sample_detail": payload["sample_detail"],
        }
        for signature, payload in sampled_object_exact_miss_buckets.items()
    ]
    exact_miss_items.sort(key=lambda item: (-item["count"], item["signature"]))
    result["sampled_object_probe"]["unique_exact_miss_bucket_count"] = len(exact_miss_items)
    result["sampled_object_probe"]["top_exact_miss_buckets"] = exact_miss_items[:10]

    def sampled_family_key(fields):
        return (
            fields.get("draw_class"),
            fields.get("cycle"),
            fields.get("tile"),
            fields.get("sampled_low32"),
            fields.get("fs"),
        )

    hit_palette_sets = {}
    for item in exact_hit_items:
        fields = item["fields"]
        key = sampled_family_key(fields)
        palette_set = hit_palette_sets.setdefault(key, set())
        entry_pcrc = fields.get("sampled_entry_pcrc")
        sparse_pcrc = fields.get("sampled_sparse_pcrc")
        if entry_pcrc is not None:
            palette_set.add(entry_pcrc)
        if sparse_pcrc is not None:
            palette_set.add(sparse_pcrc)

    exact_conflict_items = []
    exact_unresolved_items = []
    for item in exact_miss_items:
        fields = item["fields"]
        key = sampled_family_key(fields)
        palette_crc = fields.get("palette_crc")
        hit_palettes = hit_palette_sets.get(key, set())
        if palette_crc is not None and palette_crc in hit_palettes:
            exact_conflict_items.append(item)
        else:
            exact_unresolved_items.append(item)

    result["sampled_object_probe"]["exact_conflict_miss_count"] = sum(item["count"] for item in exact_conflict_items)
    result["sampled_object_probe"]["unique_exact_conflict_miss_bucket_count"] = len(exact_conflict_items)
    result["sampled_object_probe"]["top_exact_conflict_miss_buckets"] = exact_conflict_items[:10]
    result["sampled_object_probe"]["exact_unresolved_miss_count"] = sum(item["count"] for item in exact_unresolved_items)
    result["sampled_object_probe"]["unique_exact_unresolved_miss_bucket_count"] = len(exact_unresolved_items)
    result["sampled_object_probe"]["top_exact_unresolved_miss_buckets"] = exact_unresolved_items[:10]

    family_items = [
        {
            "signature": signature,
            "count": payload["count"],
            "fields": payload["fields"],
            "sample_detail": payload["sample_detail"],
        }
        for signature, payload in sampled_object_family_buckets.items()
    ]
    family_items.sort(key=lambda item: (-item["count"], item["signature"]))
    result["sampled_object_probe"]["unique_exact_family_bucket_count"] = len(family_items)
    result["sampled_object_probe"]["top_exact_family_buckets"] = family_items[:10]

def finalize_sampled_duplicate_summary():
    items = [
        {
            "signature": signature,
            "count": payload["count"],
            "fields": payload["fields"],
            "sample_detail": payload["sample_detail"],
        }
        for signature, payload in sampled_duplicate_buckets.items()
    ]
    items.sort(key=lambda item: (-item["count"], item["signature"]))
    result["sampled_duplicate_probe"]["unique_bucket_count"] = len(items)
    result["sampled_duplicate_probe"]["top_buckets"] = items[:10]

def finalize_sampled_pool_stream_summary():
    items = [
        {
            "signature": signature,
            "count": payload["count"],
            "fields": payload["fields"],
            "sample_detail": payload["sample_detail"],
        }
        for signature, payload in sampled_pool_stream_buckets.items()
    ]
    items.sort(key=lambda item: (-item["count"], item["signature"]))
    result["sampled_pool_stream_probe"]["unique_bucket_count"] = len(items)
    result["sampled_pool_stream_probe"]["top_buckets"] = items[:10]

    family_items = [
        {
            "signature": signature,
            "count": payload["count"],
            "fields": payload["fields"],
            "sample_detail": payload["sample_detail"],
        }
        for signature, payload in sampled_pool_stream_family_buckets.items()
    ]
    family_items.sort(key=lambda item: (-item["count"], item["signature"]))
    result["sampled_pool_stream_probe"]["family_count"] = len(family_items)
    result["sampled_pool_stream_probe"]["top_families"] = family_items[:10]

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
        if m.group(9) is not None and result.get("source_policy") is None:
            result["source_policy"] = m.group(9).strip()
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

    m = cache_failed_re.search(line)
    if m:
        result["available"] = True
        result["cache_load_failed"] = True
        result["cache_path"] = m.group(1).strip()
        if m.group(2) is not None:
            result["source_policy"] = m.group(2).strip()
        continue

    m = cache_loaded_re.search(line)
    if m:
        result["available"] = True
        result["cache_loaded"] = True
        result["cache_entries"] = int(m.group(1))
        result["cache_path"] = m.group(2).strip()
        if m.group(3) is not None:
            result["source_policy"] = m.group(3).strip()
        continue

    m = summary_re.search(line)
    if m:
        result["available"] = True
        summary = {
            "lookups": int(m.group(1)),
            "hits": int(m.group(2)),
            "misses": int(m.group(3)),
            "filtered": int(m.group(4) or 0),
            "block_probe_hits": int(m.group(5) or 0),
            "compat_draw_hits": int(m.group(6) or 0),
            "provider": m.group(7),
        }
        if m.group(8) is not None:
            source_counts = {
                "phrb": int(m.group(16)),
                "hts": int(m.group(17)),
                "htc": int(m.group(18)),
            }
            summary["entry_count"] = int(m.group(8))
            summary["native_sampled_entry_count"] = int(m.group(9))
            summary["compat_entry_count"] = int(m.group(10))
            summary["sampled_index_count"] = int(m.group(11))
            summary["sampled_duplicate_key_count"] = int(m.group(12) or 0)
            summary["sampled_duplicate_entry_count"] = int(m.group(13) or 0)
            summary["sampled_family_count"] = int(m.group(14))
            summary["compat_low32_family_count"] = int(m.group(15))
            summary["source_counts"] = source_counts
            if m.group(19) is not None:
                summary["descriptor_path_counts"] = {
                    "sampled": int(m.group(19)),
                    "native_checksum": int(m.group(20)),
                    "generic": int(m.group(21)),
                    "compat": int(m.group(22)),
                }
            if m.group(23) is not None:
                sampled_detail = {
                    "sampled_family_singleton": int(m.group(23)),
                    "sampled_ordered_surface_singleton": int(m.group(24)),
                }
                if m.group(25) is not None:
                    sampled_detail["sampled_exact_selector"] = int(m.group(25))
                summary["descriptor_path_detail_counts"] = sampled_detail
            if m.group(26) is not None:
                detail_counts = summary.get("descriptor_path_detail_counts") or {}
                detail_counts.update({
                    "generic_identity_assisted": int(m.group(26)),
                    "generic_plain": int(m.group(27)),
                })
                if m.group(28) is not None:
                    detail_counts.update({
                        "generic_native_plain": int(m.group(28)),
                        "generic_compat_plain": int(m.group(29)),
                        "generic_unknown_plain": int(m.group(30)),
                    })
                summary["descriptor_path_detail_counts"] = detail_counts
            if source_counts["phrb"] > 0 and source_counts["hts"] == 0 and source_counts["htc"] == 0:
                summary["source_mode"] = "phrb-only"
            elif source_counts["phrb"] == 0 and (source_counts["hts"] > 0 or source_counts["htc"] > 0):
                summary["source_mode"] = "legacy-only"
            elif source_counts["phrb"] > 0 and (source_counts["hts"] > 0 or source_counts["htc"] > 0):
                summary["source_mode"] = "mixed"
            else:
                summary["source_mode"] = "unknown"
            if result.get("source_policy") is not None:
                summary["source_policy"] = result.get("source_policy")
            summary["entry_class"] = classify_entry_class(
                summary.get("native_sampled_entry_count"),
                summary.get("compat_entry_count"),
            )
            summary["descriptor_path_class"] = classify_descriptor_path_class(
                summary.get("descriptor_path_counts"),
            )
        result["summary"] = summary
        continue

    m = native_checksum_detail_re.search(line)
    if m:
        result["available"] = True
        summary = result.get("summary") or {}
        detail_counts = summary.get("descriptor_path_detail_counts") or {}
        detail_counts["native_checksum_exact"] = int(m.group(1))
        detail_counts["native_checksum_identity_assisted"] = int(m.group(2))
        detail_counts["native_checksum_generic_fallback"] = int(m.group(3))
        summary["descriptor_path_detail_counts"] = detail_counts
        summary["descriptor_path_class"] = classify_descriptor_path_class(
            summary.get("descriptor_path_counts"),
        )
        result["summary"] = summary
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

    m = ci_family_re.search(line)
    if m:
        result["available"] = True
        fields = parse_fields(m.group(1).strip())
        if len(result["ci_palette_probe"]["families"]) < 20:
            result["ci_palette_probe"]["families"].append(fields)
        continue

    m = ci_usage_re.search(line)
    if m:
        result["available"] = True
        fields = parse_fields(m.group(1).strip())
        if len(result["ci_palette_probe"]["usages"]) < 20:
            result["ci_palette_probe"]["usages"].append(fields)
        continue

    m = ci_emulated_tmem_re.search(line)
    if m:
        result["available"] = True
        fields = parse_fields(m.group(1).strip())
        if len(result["ci_palette_probe"]["emulated_tmem"]) < 20:
            result["ci_palette_probe"]["emulated_tmem"].append(fields)
        continue

    m = ci_logical_view_re.search(line)
    if m:
        result["available"] = True
        fields = parse_fields(m.group(1).strip())
        if len(result["ci_palette_probe"]["logical_views"]) < 20:
            result["ci_palette_probe"]["logical_views"].append(fields)
        continue

    m = sampled_object_re.search(line)
    if m:
        result["available"] = True
        result["sampled_object_probe"]["available"] = True
        result["sampled_object_probe"]["line_count"] += 1
        detail = m.group(1).strip()
        fields = parse_fields(detail)
        if len(result["sampled_object_probe"]["groups"]) < 20:
            result["sampled_object_probe"]["groups"].append(fields)
        signature = " ".join(
            f"{key}={fields.get(key)}"
            for key in (
                "draw_class",
                "cycle",
                "fmt",
                "siz",
                "off",
                "stride",
                "wh",
                "fs",
                "sampled_low32",
                "sampled_sparse_pcrc",
            )
            if fields.get(key) is not None
        )
        bucket = sampled_object_buckets.setdefault(
            signature,
            {
                "count": 0,
                "fields": {
                    key: fields.get(key)
                    for key in (
                        "draw_class",
                        "cycle",
                        "tile",
                        "fmt",
                        "siz",
                        "pal",
                        "off",
                        "stride",
                        "wh",
                        "fs",
                        "sampled_low32",
                        "sampled_entry_pcrc",
                        "sampled_sparse_pcrc",
                        "sampled_entry_count",
                        "sampled_used_count",
                        "entry_hit",
                        "sparse_hit",
                        "family",
                        "unique_repl_dims",
                        "sample_repl",
                    )
                    if fields.get(key) is not None
                },
                "sample_detail": detail,
                "upload_low32s": {},
                "upload_pcrcs": {},
            },
        )
        bucket["count"] += 1
        upload_low32 = fields.get("upload_low32")
        if upload_low32 is not None:
            bucket["upload_low32s"][upload_low32] = bucket["upload_low32s"].get(upload_low32, 0) + 1
        upload_pcrc = fields.get("upload_pcrc")
        if upload_pcrc is not None:
            bucket["upload_pcrcs"][upload_pcrc] = bucket["upload_pcrcs"].get(upload_pcrc, 0) + 1
        continue

    m = sampled_object_exact_hit_re.search(line)
    if m:
        result["available"] = True
        result["sampled_object_probe"]["available"] = True
        result["sampled_object_probe"]["exact_hit_count"] += 1
        detail = m.group(1).strip()
        fields = parse_fields(detail)
        signature = " ".join(
            f"{key}={fields.get(key)}"
            for key in (
                "draw_class",
                "cycle",
                "tile",
                "reason",
                "sampled_low32",
                "sampled_entry_pcrc",
                "sampled_sparse_pcrc",
                "fs",
                "repl",
            )
            if fields.get(key) is not None
        )
        bucket = sampled_object_exact_hit_buckets.setdefault(
            signature,
            {
                "count": 0,
                "fields": {
                    key: fields.get(key)
                    for key in (
                        "draw_class",
                        "cycle",
                        "tile",
                        "reason",
                        "sampled_low32",
                        "sampled_entry_pcrc",
                        "sampled_sparse_pcrc",
                        "fs",
                        "key",
                        "repl",
                    )
                    if fields.get(key) is not None
                },
                "sample_detail": detail,
            },
        )
        bucket["count"] += 1
        continue

    m = sampled_object_exact_miss_re.search(line)
    if m:
        result["available"] = True
        result["sampled_object_probe"]["available"] = True
        result["sampled_object_probe"]["exact_miss_count"] += 1
        detail = m.group(1).strip()
        fields = parse_fields(detail)
        signature = " ".join(
            f"{key}={fields.get(key)}"
            for key in (
                "reason",
                "draw_class",
                "cycle",
                "tile",
                "sampled_low32",
                "palette_crc",
                "fs",
                "selector",
                "repl",
            )
            if fields.get(key) is not None
        )
        bucket = sampled_object_exact_miss_buckets.setdefault(
            signature,
            {
                "count": 0,
                "fields": {
                    key: fields.get(key)
                    for key in (
                        "reason",
                        "draw_class",
                        "cycle",
                        "tile",
                        "sampled_low32",
                        "palette_crc",
                        "fs",
                        "selector",
                        "provider_enabled",
                        "provider_entries",
                        "repl",
                    )
                    if fields.get(key) is not None
                },
                "sample_detail": detail,
            },
        )
        bucket["count"] += 1
        continue

    m = sampled_object_family_re.search(line)
    if m:
        result["available"] = True
        result["sampled_object_probe"]["available"] = True
        result["sampled_object_probe"]["family_line_count"] += 1
        detail = m.group(1).strip()
        fields = parse_fields(detail)
        signature = " ".join(
            f"{key}={fields.get(key)}"
            for key in (
                "available",
                "draw_class",
                "cycle",
                "tile",
                "sampled_low32",
                "palette_crc",
                "fs",
                "selector",
                "active_is_pool",
                "sample_policy",
                "sample_replacement_id",
                "sampled_object",
            )
            if fields.get(key) is not None
        )
        bucket = sampled_object_family_buckets.setdefault(
            signature,
            {
                "count": 0,
                "fields": {
                    key: fields.get(key)
                    for key in (
                        "available",
                        "draw_class",
                        "cycle",
                        "tile",
                        "sampled_low32",
                        "palette_crc",
                        "fs",
                        "selector",
                        "prefer_exact_fs",
                        "exact_entries",
                        "generic_entries",
                        "active_entries",
                        "unique_checksums",
                        "unique_selectors",
                        "zero_selectors",
                        "matching_selectors",
                        "ordered_selectors",
                        "repl_dims",
                        "uniform_repl_dims",
                        "sample_repl",
                        "active_is_pool",
                        "sample_policy",
                        "sample_replacement_id",
                        "sampled_object",
                    )
                    if fields.get(key) is not None
                },
                "sample_detail": detail,
            },
        )
        bucket["count"] += 1
        continue

    m = sampled_pool_stream_re.search(line)
    if m:
        result["available"] = True
        result["sampled_pool_stream_probe"]["available"] = True
        result["sampled_pool_stream_probe"]["line_count"] += 1
        detail = m.group(1).strip()
        fields = parse_fields(detail)
        signature = " ".join(
            f"{key}={fields.get(key)}"
            for key in (
                "sampled_low32",
                "palette_crc",
                "fs",
                "observed_selector",
                "observed_selector_source",
                "sample_policy",
                "sampled_object",
            )
            if fields.get(key) is not None
        )
        bucket = sampled_pool_stream_buckets.setdefault(
            signature,
            {
                "count": 0,
                "fields": {
                    key: fields.get(key)
                    for key in (
                        "draw_class",
                        "cycle",
                        "tile",
                        "sampled_low32",
                        "palette_crc",
                        "fs",
                        "selector",
                        "observed_selector",
                        "observed_selector_source",
                        "observed_count",
                        "unique_observed_selectors",
                        "transition_count",
                        "repeat_count",
                        "current_run",
                        "max_run",
                        "active_entries",
                        "runtime_unique_selectors",
                        "ordered_selectors",
                        "sample_policy",
                        "sample_replacement_id",
                        "sampled_object",
                    )
                    if fields.get(key) is not None
                },
                "sample_detail": detail,
            },
        )
        bucket["count"] += 1

        family_signature = " ".join(
            f"{key}={fields.get(key)}"
            for key in (
                "sampled_low32",
                "palette_crc",
                "fs",
                "sample_policy",
                "sampled_object",
            )
            if fields.get(key) is not None
        )
        family_bucket = sampled_pool_stream_family_buckets.setdefault(
            family_signature,
            {
                "count": 0,
                "fields": {
                    key: fields.get(key)
                    for key in (
                        "draw_class",
                        "cycle",
                        "tile",
                        "sampled_low32",
                        "palette_crc",
                        "fs",
                        "selector",
                        "observed_selector",
                        "observed_selector_source",
                        "observed_count",
                        "unique_observed_selectors",
                        "transition_count",
                        "repeat_count",
                        "current_run",
                        "max_run",
                        "active_entries",
                        "runtime_unique_selectors",
                        "ordered_selectors",
                        "sample_policy",
                        "sample_replacement_id",
                        "sampled_object",
                    )
                    if fields.get(key) is not None
                },
                "sample_detail": detail,
            },
        )
        family_bucket["count"] += 1
        family_bucket["sample_detail"] = detail
        for key in (
            "selector",
            "observed_selector",
            "observed_selector_source",
            "observed_count",
            "unique_observed_selectors",
            "transition_count",
            "repeat_count",
            "current_run",
            "max_run",
            "active_entries",
            "runtime_unique_selectors",
            "ordered_selectors",
            "sample_replacement_id",
        ):
            if fields.get(key) is not None:
                family_bucket["fields"][key] = fields.get(key)
        continue

    m = sampled_duplicate_re.search(line)
    if m:
        result["available"] = True
        result["sampled_duplicate_probe"]["available"] = True
        result["sampled_duplicate_probe"]["line_count"] += 1
        detail = m.group(1).strip()
        fields = parse_fields(detail)
        signature = " ".join(
            f"{key}={fields.get(key)}"
            for key in (
                "sampled_low32",
                "palette_crc",
                "fs",
                "selector",
                "policy",
                "replacement_id",
                "sampled_object",
            )
            if fields.get(key) is not None
        )
        bucket = sampled_duplicate_buckets.setdefault(
            signature,
            {
                "count": 0,
                "fields": {
                    key: fields.get(key)
                    for key in (
                        "sampled_fmt",
                        "sampled_siz",
                        "tex_offset",
                        "stride",
                        "wh",
                        "sampled_low32",
                        "palette_crc",
                        "fs",
                        "selector",
                        "total_entries",
                        "duplicate_entries",
                        "active_checksum",
                        "repl",
                        "policy",
                        "replacement_id",
                        "sampled_object",
                        "source",
                    )
                    if fields.get(key) is not None
                },
                "sample_detail": detail,
            },
        )
        bucket["count"] += 1
        continue

    m = provenance_re.search(line)
    if m:
        result["available"] = True
        result["provenance"]["available"] = True
        result["provenance"]["line_count"] += 1
        detail = m.group(1).strip()
        fields = parse_fields(detail)
        increment_counter(result["provenance"]["outcome_counts"], fields.get("outcome"))
        increment_counter(result["provenance"]["source_class_counts"], fields.get("source_class"))
        increment_counter(result["provenance"]["provenance_class_counts"], fields.get("provenance_class"))
        signature = " ".join(
            f"{key}={fields.get(key)}"
            for key in (
                "outcome",
                "source_class",
                "provenance_class",
                "mode",
                "fmt",
                "siz",
                "wh",
                "fs",
                "cycle",
                "copy",
                "tlut",
                "tlut_type",
                "framebuffer",
            )
            if fields.get(key) is not None
        )
        bucket = provenance_buckets.setdefault(
            signature,
            {
                "count": 0,
                "fields": {
                    key: fields.get(key)
                    for key in (
                        "outcome",
                        "source_class",
                        "provenance_class",
                        "mode",
                        "fmt",
                        "siz",
                        "wh",
                        "fs",
                        "cycle",
                        "copy",
                        "tlut",
                        "tlut_type",
                        "framebuffer",
                        "color_fb",
                        "depth_fb",
                        "upload",
                    )
                    if fields.get(key) is not None
                },
                "sample_detail": detail,
            },
        )
        bucket["count"] += 1
        continue

    m = draw_usage_re.search(line)
    if m:
        result["available"] = True
        result["draw_usage"]["available"] = True
        result["draw_usage"]["line_count"] += 1
        result["sampler_usage"]["available"] = True
        result["sampler_usage"]["line_count"] += 1
        detail = m.group(1).strip()
        fields = parse_fields(detail)
        increment_counter(result["draw_usage"]["draw_class_counts"], fields.get("draw_class"))
        increment_counter(result["draw_usage"]["copy_counts"], fields.get("copy"))
        signature = " ".join(
            f"{key}={fields.get(key)}"
            for key in ("draw_class", "cycle", "copy", "base_tile", "texel0_hit", "texel1_hit")
            if fields.get(key) is not None
        )
        bucket = draw_usage_buckets.setdefault(
            signature,
            {
                "count": 0,
                "fields": {
                    key: fields.get(key)
                    for key in ("draw_class", "cycle", "copy", "base_tile", "uses_texel0", "uses_texel1", "texel0_hit", "texel1_hit")
                    if fields.get(key) is not None
                },
                "sample_detail": detail,
            },
        )
        bucket["count"] += 1

        sampler_signature = " ".join(
            f"{key}={fields.get(key)}"
            for key in (
                "draw_class",
                "cycle",
                "copy",
                "fmt",
                "siz",
                "pal",
                "offset",
                "stride",
                "sl",
                "tl",
                "sh",
                "th",
                "mask_s",
                "shift_s",
                "mask_t",
                "shift_t",
                "clamp_s",
                "mirror_s",
                "clamp_t",
                "mirror_t",
                "texel0_fs",
                "texel0_w",
                "texel0_h",
                "texel1_fs",
                "texel1_w",
                "texel1_h",
                "texel0_hit",
                "texel1_hit",
            )
            if fields.get(key) is not None
        )
        sampler_bucket = sampler_usage_buckets.setdefault(
            sampler_signature,
            {
                "count": 0,
                "fields": {
                    key: fields.get(key)
                    for key in (
                        "draw_class",
                        "cycle",
                        "copy",
                        "base_tile",
                        "fmt",
                        "siz",
                        "pal",
                        "offset",
                        "stride",
                        "sl",
                        "tl",
                        "sh",
                        "th",
                        "mask_s",
                        "shift_s",
                        "mask_t",
                        "shift_t",
                        "clamp_s",
                        "mirror_s",
                        "clamp_t",
                        "mirror_t",
                        "texel0_fs",
                        "texel0_w",
                        "texel0_h",
                        "texel1_fs",
                        "texel1_w",
                        "texel1_h",
                        "texel0_hit",
                        "texel1_hit",
                    )
                    if fields.get(key) is not None
                },
                "sample_detail": detail,
            },
        )
        sampler_bucket["count"] += 1
        continue

    m = hit_miss_re.search(line)
    if m:
        result["available"] = True
        kind = m.group(1)
        detail = m.group(2).strip()
        result["debug_line_counts"][kind] += 1
        fields = parse_fields(detail)
        if kind == "hit":
            increment_counter(resolution_reason_counts, fields.get("resolution_reason"))
        update_bucket(kind, detail)
        if kind == "miss":
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
finalize_provenance_summary()
finalize_draw_usage_summary()
finalize_sampler_usage_summary()
finalize_sampled_object_summary()
finalize_sampled_pool_stream_summary()
finalize_sampled_duplicate_summary()
finalize_pack_crosscheck()
if result.get("summary") is not None and resolution_reason_counts:
    result["summary"]["resolution_reason_counts"] = dict(
        sorted(resolution_reason_counts.items(), key=lambda item: (-item[1], item[0]))
    )

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
import os
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
bundle_meta_path = bundle_dir / "bundle.json"

mode = None
if bundle_meta_path.is_file():
    try:
        mode = json.loads(bundle_meta_path.read_text()).get("mode")
    except Exception:
        mode = None

def get_mode_expected(name: str):
    if mode:
        mode_key = f"{name}_{mode.upper()}"
        if mode_key in os.environ:
            return os.environ[mode_key]
    return os.environ.get(name)

def parse_expected_bool(name: str):
    value = get_mode_expected(name)
    if value is None or value == "":
        return None
    normalized = value.strip().lower()
    if normalized in ("1", "true", "yes", "on"):
        return True
    if normalized in ("0", "false", "no", "off"):
        return False
    raise ValueError(f"{name} must be a boolean-like value, got {value!r}.")

def parse_expected_int(name: str):
    value = get_mode_expected(name)
    if value is None or value == "":
        return None
    return int(value)

def parse_expected_list(name: str):
    value = get_mode_expected(name)
    if value is None or value.strip() == "":
        return []
    return [item.strip() for item in value.split(",") if item.strip()]

expected_hires_provider = get_mode_expected("EXPECTED_HIRES_SUMMARY_PROVIDER")
expected_hires_source_mode = get_mode_expected("EXPECTED_HIRES_SUMMARY_SOURCE_MODE")
expected_hires_source_policy = get_mode_expected("EXPECTED_HIRES_SUMMARY_SOURCE_POLICY")
expected_min_summary_entry_count = parse_expected_int("EXPECTED_HIRES_MIN_SUMMARY_ENTRY_COUNT")
expected_min_summary_native_sampled_entry_count = parse_expected_int("EXPECTED_HIRES_MIN_SUMMARY_NATIVE_SAMPLED_ENTRY_COUNT")
expected_min_summary_source_phrb_count = parse_expected_int("EXPECTED_HIRES_MIN_SUMMARY_SOURCE_PHRB_COUNT")
expected_provenance_available = parse_expected_bool("EXPECTED_HIRES_PROVENANCE_AVAILABLE")
expected_draw_usage_available = parse_expected_bool("EXPECTED_HIRES_DRAW_USAGE_AVAILABLE")
expected_sampler_usage_available = parse_expected_bool("EXPECTED_HIRES_SAMPLER_USAGE_AVAILABLE")
expected_sampled_object_available = parse_expected_bool("EXPECTED_HIRES_SAMPLED_OBJECT_AVAILABLE")
expected_source_classes = parse_expected_list("EXPECTED_HIRES_SOURCE_CLASS_PRESENT")
expected_provenance_classes = parse_expected_list("EXPECTED_HIRES_PROVENANCE_CLASS_PRESENT")
expected_draw_classes = parse_expected_list("EXPECTED_HIRES_DRAW_CLASS_PRESENT")
expected_min_exact_hit_count = parse_expected_int("EXPECTED_HIRES_MIN_EXACT_HIT_COUNT")
expected_min_exact_conflict_miss_count = parse_expected_int("EXPECTED_HIRES_MIN_EXACT_CONFLICT_MISS_COUNT")
expected_min_exact_unresolved_miss_count = parse_expected_int("EXPECTED_HIRES_MIN_EXACT_UNRESOLVED_MISS_COUNT")

requires_hires_assertions = any([
    expected_hires_provider is not None,
    expected_hires_source_mode is not None,
    expected_hires_source_policy is not None,
    expected_min_summary_entry_count is not None,
    expected_min_summary_native_sampled_entry_count is not None,
    expected_min_summary_source_phrb_count is not None,
    expected_provenance_available is not None,
    expected_draw_usage_available is not None,
    expected_sampler_usage_available is not None,
    expected_sampled_object_available is not None,
    bool(expected_source_classes),
    bool(expected_provenance_classes),
    bool(expected_draw_classes),
    expected_min_exact_hit_count is not None,
    expected_min_exact_conflict_miss_count is not None,
    expected_min_exact_unresolved_miss_count is not None,
])

result = {
    "fixture_id": fixture_id,
    "mode": mode,
    "passed": True,
    "checks": {
        "single_capture": False,
        "screenshot_sha256": None,
        "screenshot_sha256_match": None,
        "semantic_trace_present": semantic_path.is_file(),
        "cur_game_mode_match": None,
        "hires_evidence_present": hires_path.is_file(),
        "hires_summary_provider_match": None,
        "hires_summary_source_mode_match": None,
        "hires_summary_source_policy_match": None,
        "hires_min_summary_entry_count_match": None,
        "hires_min_summary_native_sampled_entry_count_match": None,
        "hires_min_summary_source_phrb_count_match": None,
        "hires_provenance_available_match": None,
        "hires_draw_usage_available_match": None,
        "hires_sampler_usage_available_match": None,
        "hires_sampled_object_available_match": None,
        "hires_source_class_presence": {},
        "hires_provenance_class_presence": {},
        "hires_draw_class_presence": {},
        "hires_exact_hit_count_match": None,
        "hires_exact_conflict_miss_count_match": None,
        "hires_exact_unresolved_miss_count_match": None,
    },
    "expected": {
        "screenshot_sha256": expected_screenshot_sha256 or None,
        "init_symbol": expected_init_symbol or None,
        "step_symbol": expected_step_symbol or None,
        "hires_summary_provider": expected_hires_provider,
        "hires_summary_source_mode": expected_hires_source_mode,
        "hires_summary_source_policy": expected_hires_source_policy,
        "hires_min_summary_entry_count": expected_min_summary_entry_count,
        "hires_min_summary_native_sampled_entry_count": expected_min_summary_native_sampled_entry_count,
        "hires_min_summary_source_phrb_count": expected_min_summary_source_phrb_count,
        "hires_provenance_available": expected_provenance_available,
        "hires_draw_usage_available": expected_draw_usage_available,
        "hires_sampler_usage_available": expected_sampler_usage_available,
        "hires_sampled_object_available": expected_sampled_object_available,
        "hires_source_classes": expected_source_classes,
        "hires_provenance_classes": expected_provenance_classes,
        "hires_draw_classes": expected_draw_classes,
        "hires_min_exact_hit_count": expected_min_exact_hit_count,
        "hires_min_exact_conflict_miss_count": expected_min_exact_conflict_miss_count,
        "hires_min_exact_unresolved_miss_count": expected_min_exact_unresolved_miss_count,
    },
    "actual": {
        "capture_path": None,
        "init_symbol": None,
        "step_symbol": None,
        "hires_summary_provider": None,
        "hires_summary_source_mode": None,
        "hires_summary_source_policy": None,
        "hires_summary_entry_count": None,
        "hires_summary_native_sampled_entry_count": None,
        "hires_summary_source_phrb_count": None,
        "hires_provenance_available": None,
        "hires_draw_usage_available": None,
        "hires_sampler_usage_available": None,
        "hires_sampled_object_available": None,
        "hires_source_class_counts": {},
        "hires_provenance_class_counts": {},
        "hires_draw_class_counts": {},
        "hires_exact_hit_count": None,
        "hires_exact_conflict_miss_count": None,
        "hires_exact_unresolved_miss_count": None,
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

if hires_path.is_file():
    try:
        hires = json.loads(hires_path.read_text())
    except Exception as exc:
        result["passed"] = False
        result["failures"].append(f"Failed to parse hi-res evidence JSON: {exc}.")
        hires = None

    if hires is not None:
        summary = hires.get("summary") or {}
        provenance = hires.get("provenance") or {}
        draw_usage = hires.get("draw_usage") or {}
        sampler_usage = hires.get("sampler_usage") or {}
        sampled_object = hires.get("sampled_object_probe") or {}

        result["actual"]["hires_summary_provider"] = summary.get("provider")
        result["actual"]["hires_summary_source_mode"] = summary.get("source_mode")
        result["actual"]["hires_summary_source_policy"] = summary.get("source_policy")
        result["actual"]["hires_summary_entry_count"] = summary.get("entry_count")
        result["actual"]["hires_summary_native_sampled_entry_count"] = summary.get("native_sampled_entry_count")
        result["actual"]["hires_summary_compat_entry_count"] = summary.get("compat_entry_count")
        result["actual"]["hires_summary_entry_class"] = summary.get("entry_class")
        result["actual"]["hires_summary_descriptor_path_class"] = summary.get("descriptor_path_class")
        result["actual"]["hires_summary_source_phrb_count"] = (summary.get("source_counts") or {}).get("phrb")
        result["actual"]["hires_provenance_available"] = bool(provenance.get("available"))
        result["actual"]["hires_draw_usage_available"] = bool(draw_usage.get("available"))
        result["actual"]["hires_sampler_usage_available"] = bool(sampler_usage.get("available"))
        result["actual"]["hires_sampled_object_available"] = bool(sampled_object.get("available"))
        result["actual"]["hires_source_class_counts"] = provenance.get("source_class_counts") or {}
        result["actual"]["hires_provenance_class_counts"] = provenance.get("provenance_class_counts") or {}
        result["actual"]["hires_draw_class_counts"] = draw_usage.get("draw_class_counts") or {}
        result["actual"]["hires_exact_hit_count"] = sampled_object.get("exact_hit_count")
        result["actual"]["hires_exact_conflict_miss_count"] = sampled_object.get("exact_conflict_miss_count")
        result["actual"]["hires_exact_unresolved_miss_count"] = sampled_object.get("exact_unresolved_miss_count")

        if expected_hires_provider is not None:
            matched = summary.get("provider") == expected_hires_provider
            result["checks"]["hires_summary_provider_match"] = matched
            if not matched:
                result["passed"] = False
                result["failures"].append(
                    f"Hi-res summary provider mismatch: expected {expected_hires_provider}, got {summary.get('provider')}."
                )

        if expected_hires_source_mode is not None:
            matched = summary.get("source_mode") == expected_hires_source_mode
            result["checks"]["hires_summary_source_mode_match"] = matched
            if not matched:
                result["passed"] = False
                result["failures"].append(
                    f"Hi-res summary source_mode mismatch: expected {expected_hires_source_mode}, got {summary.get('source_mode')}."
                )

        if expected_hires_source_policy is not None:
            matched = summary.get("source_policy") == expected_hires_source_policy
            result["checks"]["hires_summary_source_policy_match"] = matched
            if not matched:
                result["passed"] = False
                result["failures"].append(
                    f"Hi-res summary source_policy mismatch: expected {expected_hires_source_policy}, got {summary.get('source_policy')}."
                )

        if expected_min_summary_entry_count is not None:
            actual_value = summary.get("entry_count")
            matched = actual_value is not None and actual_value >= expected_min_summary_entry_count
            result["checks"]["hires_min_summary_entry_count_match"] = matched
            if not matched:
                result["passed"] = False
                result["failures"].append(
                    f"Hi-res summary entry_count below minimum: expected >= {expected_min_summary_entry_count}, got {actual_value}."
                )

        if expected_min_summary_native_sampled_entry_count is not None:
            actual_value = summary.get("native_sampled_entry_count")
            matched = actual_value is not None and actual_value >= expected_min_summary_native_sampled_entry_count
            result["checks"]["hires_min_summary_native_sampled_entry_count_match"] = matched
            if not matched:
                result["passed"] = False
                result["failures"].append(
                    f"Hi-res summary native_sampled_entry_count below minimum: expected >= {expected_min_summary_native_sampled_entry_count}, got {actual_value}."
                )

        if expected_min_summary_source_phrb_count is not None:
            actual_value = (summary.get("source_counts") or {}).get("phrb")
            matched = actual_value is not None and actual_value >= expected_min_summary_source_phrb_count
            result["checks"]["hires_min_summary_source_phrb_count_match"] = matched
            if not matched:
                result["passed"] = False
                result["failures"].append(
                    f"Hi-res summary source_counts.phrb below minimum: expected >= {expected_min_summary_source_phrb_count}, got {actual_value}."
                )

        if expected_provenance_available is not None:
            actual = bool(provenance.get("available"))
            matched = actual == expected_provenance_available
            result["checks"]["hires_provenance_available_match"] = matched
            if not matched:
                result["passed"] = False
                result["failures"].append(
                    f"Hi-res provenance availability mismatch: expected {expected_provenance_available}, got {actual}."
                )

        if expected_draw_usage_available is not None:
            actual = bool(draw_usage.get("available"))
            matched = actual == expected_draw_usage_available
            result["checks"]["hires_draw_usage_available_match"] = matched
            if not matched:
                result["passed"] = False
                result["failures"].append(
                    f"Hi-res draw-usage availability mismatch: expected {expected_draw_usage_available}, got {actual}."
                )

        if expected_sampler_usage_available is not None:
            actual = bool(sampler_usage.get("available"))
            matched = actual == expected_sampler_usage_available
            result["checks"]["hires_sampler_usage_available_match"] = matched
            if not matched:
                result["passed"] = False
                result["failures"].append(
                    f"Hi-res sampler-usage availability mismatch: expected {expected_sampler_usage_available}, got {actual}."
                )

        if expected_sampled_object_available is not None:
            actual = bool(sampled_object.get("available"))
            matched = actual == expected_sampled_object_available
            result["checks"]["hires_sampled_object_available_match"] = matched
            if not matched:
                result["passed"] = False
                result["failures"].append(
                    f"Hi-res sampled-object availability mismatch: expected {expected_sampled_object_available}, got {actual}."
                )

        source_class_counts = provenance.get("source_class_counts") or {}
        for expected_class in expected_source_classes:
            present = int(source_class_counts.get(expected_class, 0)) > 0
            result["checks"]["hires_source_class_presence"][expected_class] = present
            if not present:
                result["passed"] = False
                result["failures"].append(
                    f"Hi-res source class '{expected_class}' was not present in evidence."
                )

        provenance_class_counts = provenance.get("provenance_class_counts") or {}
        for expected_class in expected_provenance_classes:
            present = int(provenance_class_counts.get(expected_class, 0)) > 0
            result["checks"]["hires_provenance_class_presence"][expected_class] = present
            if not present:
                result["passed"] = False
                result["failures"].append(
                    f"Hi-res provenance class '{expected_class}' was not present in evidence."
                )

        draw_class_counts = draw_usage.get("draw_class_counts") or {}
        for expected_class in expected_draw_classes:
            present = int(draw_class_counts.get(expected_class, 0)) > 0
            result["checks"]["hires_draw_class_presence"][expected_class] = present
            if not present:
                result["passed"] = False
                result["failures"].append(
                    f"Hi-res draw class '{expected_class}' was not present in evidence."
                )

        if expected_min_exact_hit_count is not None:
            actual = int(sampled_object.get("exact_hit_count") or 0)
            matched = actual >= expected_min_exact_hit_count
            result["checks"]["hires_exact_hit_count_match"] = matched
            if not matched:
                result["passed"] = False
                result["failures"].append(
                    f"Hi-res exact-hit count too low: expected >= {expected_min_exact_hit_count}, got {actual}."
                )

        if expected_min_exact_conflict_miss_count is not None:
            actual = int(sampled_object.get("exact_conflict_miss_count") or 0)
            matched = actual >= expected_min_exact_conflict_miss_count
            result["checks"]["hires_exact_conflict_miss_count_match"] = matched
            if not matched:
                result["passed"] = False
                result["failures"].append(
                    f"Hi-res exact-conflict miss count too low: expected >= {expected_min_exact_conflict_miss_count}, got {actual}."
                )

        if expected_min_exact_unresolved_miss_count is not None:
            actual = int(sampled_object.get("exact_unresolved_miss_count") or 0)
            matched = actual >= expected_min_exact_unresolved_miss_count
            result["checks"]["hires_exact_unresolved_miss_count_match"] = matched
            if not matched:
                result["passed"] = False
                result["failures"].append(
                    f"Hi-res exact-unresolved miss count too low: expected >= {expected_min_exact_unresolved_miss_count}, got {actual}."
                )
elif requires_hires_assertions:
    result["passed"] = False
    result["failures"].append("Missing hi-res evidence JSON required for semantic assertions.")

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
    (0x800338D0, 0x800338E4): "battle_callbacks",
    (0x80035058, 0x800354EC): "file_select_callbacks",
    (0x80035660, 0x80035B40): "exit_file_select_callbacks",
    (0x80035E00, 0x80035EEC): "enter_demo_callbacks",
    (0x80035E24, 0x80035EEC): "enter_world_callbacks",
    (0x80035D30, 0x80035D54): "world_callbacks",
    (0x80036650, 0x80036854): "intro_callbacks",
    (0x80036DF0, 0x800370B4): "title_screen_callbacks",
}
CUR_GAME_MODE_POINTER_NAMES = {
    0x800338D0: "state_init_battle",
    0x800338E4: "state_step_battle",
    0x80033B54: "state_drawUI_battle",
    0x80033E70: "state_init_logos",
    0x800340A4: "state_step_logos",
    0x80035058: "state_init_file_select",
    0x800354EC: "state_step_file_select",
    0x80035660: "state_init_exit_file_select",
    0x80035B40: "state_step_exit_file_select",
    0x80035D30: "state_init_world",
    0x80035D54: "state_step_world",
    0x80035E00: "state_init_enter_demo",
    0x80035E24: "state_init_enter_world",
    0x80035EEC: "state_step_enter_world",
    0x800360FC: "state_drawUI_enter_world",
    0x80036650: "state_init_intro",
    0x80036854: "state_step_intro",
    0x80036DF0: "state_init_title_screen",
    0x800370B4: "state_step_title_screen",
}
FILE_MENU_NAMES = {
    0: "FILE_MENU_MAIN",
    1: "FILE_MENU_CONFIRM",
    2: "FILE_MENU_MESSAGE",
    3: "FILE_MENU_INPUT_NAME",
}
FILE_MENU_MAIN_STATE_NAMES = {
    0: "FM_MAIN_SELECT_FILE",
    1: "FM_MAIN_SELECT_DELETE",
    2: "FM_MAIN_SELECT_LANG_DUMMY",
    3: "FM_MAIN_SELECT_COPY_FROM",
    4: "FM_MAIN_SELECT_COPY_TO",
}
FILE_MENU_MAIN_SELECTED_NAMES = {
    0: "FM_MAIN_OPT_FILE_1",
    1: "FM_MAIN_OPT_FILE_2",
    2: "FM_MAIN_OPT_FILE_3",
    3: "FM_MAIN_OPT_FILE_4",
    4: "FM_MAIN_OPT_DELETE",
    5: "FM_MAIN_OPT_COPY",
    6: "FM_MAIN_OPT_CANCEL",
}
FILE_MENU_CONFIRM_STATE_NAMES = {
    0: "FM_CONFIRM_DELETE",
    1: "FM_CONFIRM_DUMMY",
    2: "FM_CONFIRM_CREATE",
    3: "FM_CONFIRM_COPY",
    4: "FM_CONFIRM_START",
}
FILE_MENU_CONFIRM_SELECTED_NAMES = {
    0: "YES",
    1: "NO",
}
FILE_MENU_EXIT_MODE_NAMES = {
    0: "stay_file_select",
    1: "selected_file",
    2: "confirm_start_yes",
}
WINDOW_FLAG_NAMES = {
    0x01: "WINDOW_FLAG_INITIALIZED",
    0x02: "WINDOW_FLAG_FPUPDATE_CHANGED",
    0x04: "WINDOW_FLAG_HIDDEN",
    0x08: "WINDOW_FLAG_INITIAL_ANIMATION",
    0x10: "WINDOW_FLAG_HAS_CHILDREN",
    0x20: "WINDOW_FLAG_DISABLED",
    0x40: "WINDOW_FLAG_40",
}
WINDOW_UPDATE_VALUE_NAMES = {
    0x00000000: "WINDOW_UPDATE_NONE",
    0x00000001: "WINDOW_UPDATE_SHOW",
    0x00000002: "WINDOW_UPDATE_HIDE",
    0x00000003: "WINDOW_UPDATE_HIER_UPDATE",
    0x00000004: "WINDOW_UPDATE_DARKENED",
    0x00000005: "WINDOW_UPDATE_TRANSPARENT",
    0x00000006: "WINDOW_UPDATE_OPAQUE",
    0x00000007: "WINDOW_UPDATE_SHOW_TRANSPARENT",
    0x00000008: "WINDOW_UPDATE_SHOW_DARKENED",
    0x00000009: "WINDOW_UPDATE_9",
    0x80147650: "main_menu_window_update",
    0x80243380: "filemenu_update_show_name_input",
    0x802433F4: "filemenu_update_show_options_left",
    0x80243468: "filemenu_update_show_options_right",
    0x802434DC: "filemenu_update_show_options_bottom",
    0x80243550: "filemenu_update_show_title",
    0x80243628: "filemenu_update_hidden_name_input",
    0x8024381C: "filemenu_update_show_with_rotation",
    0x80243898: "filemenu_update_hidden_with_rotation",
    0x80243CCC: "filemenu_update_show_name_confirm",
    0x80243EEC: "filemenu_update_hidden_name_confirm",
    0x80248170: "filemenu_update_change_layout",
}
FILE_MENU_WINDOW_IDS = {
    "title": 45,
    "confirm_prompt": 46,
    "message": 47,
    "input_field": 48,
    "input_keyboard": 49,
    "confirm_options": 50,
    "slot2_body": 57,
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
filemenu_current_menu_trace_path = bundle_dir / "traces" / "paper-mario-filemenu-current-menu.core-memory.txt"
filemenu_current_menu_expected_base = 0x8024C098
filemenu_current_menu_expected_size = 0x01
filemenu_menus_trace_path = bundle_dir / "traces" / "paper-mario-filemenu-menus.core-memory.txt"
filemenu_menus_expected_base = 0x80249B84
filemenu_menus_expected_size = 0x08
filemenu_main_panel_trace_path = bundle_dir / "traces" / "paper-mario-filemenu-main-panel.core-memory.txt"
filemenu_main_panel_expected_base = None
filemenu_main_panel_expected_size = 0x1C
filemenu_confirm_panel_trace_path = bundle_dir / "traces" / "paper-mario-filemenu-confirm-panel.core-memory.txt"
filemenu_confirm_panel_expected_base = None
filemenu_confirm_panel_expected_size = 0x1C
filemenu_pressed_buttons_trace_path = bundle_dir / "traces" / "paper-mario-filemenu-pressed-buttons.core-memory.txt"
filemenu_pressed_buttons_expected_base = 0x8024C084
filemenu_pressed_buttons_expected_size = 0x04
filemenu_held_buttons_trace_path = bundle_dir / "traces" / "paper-mario-filemenu-held-buttons.core-memory.txt"
filemenu_held_buttons_expected_base = 0x8024C08C
filemenu_held_buttons_expected_size = 0x04
save_slot_has_data_trace_path = bundle_dir / "traces" / "paper-mario-save-slot-has-data.core-memory.txt"
save_slot_has_data_expected_base = 0x80077A24
save_slot_has_data_expected_size = 0x04
window_trace_specs = [
    ("title", bundle_dir / "traces" / "paper-mario-window-files-title.core-memory.txt", 0x80159D50 + 45 * 0x20),
    ("confirm_prompt", bundle_dir / "traces" / "paper-mario-window-files-confirm-prompt.core-memory.txt", 0x80159D50 + 46 * 0x20),
    ("message", bundle_dir / "traces" / "paper-mario-window-files-message.core-memory.txt", 0x80159D50 + 47 * 0x20),
    ("input_field", bundle_dir / "traces" / "paper-mario-window-files-input-field.core-memory.txt", 0x80159D50 + 48 * 0x20),
    ("input_keyboard", bundle_dir / "traces" / "paper-mario-window-files-input-keyboard.core-memory.txt", 0x80159D50 + 49 * 0x20),
    ("confirm_options", bundle_dir / "traces" / "paper-mario-window-files-confirm-options.core-memory.txt", 0x80159D50 + 50 * 0x20),
    ("slot2_body", bundle_dir / "traces" / "paper-mario-window-files-slot2-body.core-memory.txt", 0x80159D50 + 57 * 0x20),
]
window_expected_size = 0x20

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

def ensure_trace_layout(trace, expected_base, expected_size, trace_name):
    if trace is None:
        return
    if expected_base is not None and trace["base_address"] != expected_base:
        raise SystemExit(
            f"Unexpected base address for {trace_name}: "
            f"0x{trace['base_address']:08x} != 0x{expected_base:08x}"
        )
    if len(trace["data"]) < expected_size:
        raise SystemExit(
            f"Snapshot too short for {trace_name}: "
            f"{len(trace['data'])} < {expected_size}"
        )

def decode_menu_panel(buf, *, state_names, selected_names=None):
    selected = u8(buf, 0x03)
    state = s8(buf, 0x04)
    return {
        "initialized": bool(u8(buf, 0x00)),
        "col": s8(buf, 0x01),
        "row": s8(buf, 0x02),
        "selected": selected,
        "selected_name": None if selected_names is None else selected_names.get(selected),
        "state": state,
        "state_name": state_names.get(state),
        "num_cols": s8(buf, 0x05),
        "num_rows": s8(buf, 0x06),
        "num_pages": s8(buf, 0x07),
        "grid_data_ptr": f"0x{u32le(buf, 0x08):08x}",
        "handle_input_ptr": f"0x{u32le(buf, 0x10):08x}",
        "update_ptr": f"0x{u32le(buf, 0x14):08x}",
    }

def decode_window_flags(flags):
    return [name for bit, name in WINDOW_FLAG_NAMES.items() if flags & bit]

def decode_window_update(value):
    return WINDOW_UPDATE_VALUE_NAMES.get(value)

def decode_window(buf):
    flags = u8(buf, 0x00)
    fp_update = u32le(buf, 0x04)
    fp_pending = u32le(buf, 0x08)
    return {
        "flags": flags,
        "flag_names": decode_window_flags(flags),
        "priority": u8(buf, 0x01),
        "original_priority": u8(buf, 0x02),
        "parent": s8(buf, 0x03),
        "fp_update": f"0x{fp_update:08x}",
        "fp_update_name": decode_window_update(fp_update),
        "fp_pending": f"0x{fp_pending:08x}",
        "fp_pending_name": decode_window_update(fp_pending),
        "pos": {
            "x": s16le(buf, 0x0C),
            "y": s16le(buf, 0x0E),
        },
        "width": s16le(buf, 0x10),
        "height": s16le(buf, 0x12),
        "draw_contents_ptr": f"0x{u32le(buf, 0x14):08x}",
        "draw_contents_arg0_ptr": f"0x{u32le(buf, 0x18):08x}",
        "update_counter": u8(buf, 0x1C),
    }

trace = load_trace(trace_path)
if trace is None:
    raise SystemExit("Paper Mario gamestatus snapshot not found in bundle traces.")
ensure_trace_layout(trace, expected_base, expected_size, trace_path.name)

gamestatus = trace["data"]
window_sha256 = hashlib.sha256(gamestatus).hexdigest()
area_id = s16le(gamestatus, 0x00)
map_id = s16le(gamestatus, 0x06)
map_name_candidates = AREA_MAP_NAMES.get(area_id, [])
map_name_candidate = None
if 0 <= map_id < len(map_name_candidates):
    map_name_candidate = map_name_candidates[map_id]

cur_game_mode_trace = load_trace(cur_game_mode_trace_path)
ensure_trace_layout(
    cur_game_mode_trace,
    cur_game_mode_expected_base,
    cur_game_mode_expected_size,
    cur_game_mode_trace_path.name,
)

transition_trace = load_trace(transition_trace_path)
ensure_trace_layout(
    transition_trace,
    transition_expected_base,
    transition_expected_size,
    transition_trace_path.name,
)
filemenu_current_menu_trace = load_trace(filemenu_current_menu_trace_path)
ensure_trace_layout(
    filemenu_current_menu_trace,
    filemenu_current_menu_expected_base,
    filemenu_current_menu_expected_size,
    filemenu_current_menu_trace_path.name,
)
filemenu_menus_trace = load_trace(filemenu_menus_trace_path)
ensure_trace_layout(
    filemenu_menus_trace,
    filemenu_menus_expected_base,
    filemenu_menus_expected_size,
    filemenu_menus_trace_path.name,
)
filemenu_main_panel_trace = load_trace(filemenu_main_panel_trace_path)
ensure_trace_layout(
    filemenu_main_panel_trace,
    filemenu_main_panel_expected_base,
    filemenu_main_panel_expected_size,
    filemenu_main_panel_trace_path.name,
)
filemenu_confirm_panel_trace = load_trace(filemenu_confirm_panel_trace_path)
ensure_trace_layout(
    filemenu_confirm_panel_trace,
    filemenu_confirm_panel_expected_base,
    filemenu_confirm_panel_expected_size,
    filemenu_confirm_panel_trace_path.name,
)
filemenu_pressed_buttons_trace = load_trace(filemenu_pressed_buttons_trace_path)
ensure_trace_layout(
    filemenu_pressed_buttons_trace,
    filemenu_pressed_buttons_expected_base,
    filemenu_pressed_buttons_expected_size,
    filemenu_pressed_buttons_trace_path.name,
)
filemenu_held_buttons_trace = load_trace(filemenu_held_buttons_trace_path)
ensure_trace_layout(
    filemenu_held_buttons_trace,
    filemenu_held_buttons_expected_base,
    filemenu_held_buttons_expected_size,
    filemenu_held_buttons_trace_path.name,
)
save_slot_has_data_trace = load_trace(save_slot_has_data_trace_path)
ensure_trace_layout(
    save_slot_has_data_trace,
    save_slot_has_data_expected_base,
    save_slot_has_data_expected_size,
    save_slot_has_data_trace_path.name,
)
window_traces = {}
for window_name, window_path, window_expected_base in window_trace_specs:
    window_trace = load_trace(window_path)
    ensure_trace_layout(
        window_trace,
        window_expected_base,
        window_expected_size,
        window_path.name,
    )
    if window_trace is not None:
        window_traces[window_name] = window_trace

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

if any(
    trace is not None
    for trace in (
        filemenu_current_menu_trace,
        filemenu_main_panel_trace,
        filemenu_confirm_panel_trace,
        filemenu_pressed_buttons_trace,
        filemenu_held_buttons_trace,
    )
):
    result["sources"]["filemenu_runtime"] = {}
    filemenu_result = result["paper_mario_us"].setdefault("filemenu", {})

    if filemenu_current_menu_trace is not None:
        filemenu_current_menu = s8(filemenu_current_menu_trace["data"], 0x00)
        result["sources"]["filemenu_runtime"]["current_menu"] = {
            "path": filemenu_current_menu_trace["path"],
            "base_address": f"0x{filemenu_current_menu_trace['base_address']:08x}",
            "window_size_bytes": len(filemenu_current_menu_trace["data"]),
        }
        filemenu_result["current_menu"] = filemenu_current_menu
        filemenu_result["current_menu_name"] = FILE_MENU_NAMES.get(filemenu_current_menu)

    if filemenu_menus_trace is not None:
        main_panel_ptr = u32le(filemenu_menus_trace["data"], 0x00)
        confirm_panel_ptr = u32le(filemenu_menus_trace["data"], 0x04)
        result["sources"]["filemenu_runtime"]["menus"] = {
            "path": filemenu_menus_trace["path"],
            "base_address": f"0x{filemenu_menus_trace['base_address']:08x}",
            "window_size_bytes": len(filemenu_menus_trace["data"]),
        }
        filemenu_result["menus"] = {
            "main_panel_ptr": f"0x{main_panel_ptr:08x}",
            "confirm_panel_ptr": f"0x{confirm_panel_ptr:08x}",
        }

    if filemenu_main_panel_trace is not None:
        main_panel = filemenu_main_panel_trace["data"]
        result["sources"]["filemenu_runtime"]["main_panel"] = {
            "path": filemenu_main_panel_trace["path"],
            "base_address": f"0x{filemenu_main_panel_trace['base_address']:08x}",
            "window_size_bytes": len(main_panel),
            "window_sha256": hashlib.sha256(main_panel).hexdigest(),
        }
        filemenu_result["main_panel"] = decode_menu_panel(
            main_panel,
            state_names=FILE_MENU_MAIN_STATE_NAMES,
            selected_names=FILE_MENU_MAIN_SELECTED_NAMES,
        )

    if filemenu_confirm_panel_trace is not None:
        confirm_panel = filemenu_confirm_panel_trace["data"]
        result["sources"]["filemenu_runtime"]["confirm_panel"] = {
            "path": filemenu_confirm_panel_trace["path"],
            "base_address": f"0x{filemenu_confirm_panel_trace['base_address']:08x}",
            "window_size_bytes": len(confirm_panel),
            "window_sha256": hashlib.sha256(confirm_panel).hexdigest(),
        }
        filemenu_result["confirm_panel"] = decode_menu_panel(
            confirm_panel,
            state_names=FILE_MENU_CONFIRM_STATE_NAMES,
            selected_names=FILE_MENU_CONFIRM_SELECTED_NAMES,
        )

    if filemenu_pressed_buttons_trace is not None:
        pressed_buttons = u32le(filemenu_pressed_buttons_trace["data"], 0x00)
        result["sources"]["filemenu_runtime"]["pressed_buttons"] = {
            "path": filemenu_pressed_buttons_trace["path"],
            "base_address": f"0x{filemenu_pressed_buttons_trace['base_address']:08x}",
            "window_size_bytes": len(filemenu_pressed_buttons_trace["data"]),
        }
        filemenu_result["pressed_buttons"] = {
            "raw": pressed_buttons,
            "raw_hex": f"0x{pressed_buttons:08x}",
        }

    if filemenu_held_buttons_trace is not None:
        held_buttons = u32le(filemenu_held_buttons_trace["data"], 0x00)
        result["sources"]["filemenu_runtime"]["held_buttons"] = {
            "path": filemenu_held_buttons_trace["path"],
            "base_address": f"0x{filemenu_held_buttons_trace['base_address']:08x}",
            "window_size_bytes": len(filemenu_held_buttons_trace["data"]),
        }
        filemenu_result["held_buttons"] = {
            "raw": held_buttons,
            "raw_hex": f"0x{held_buttons:08x}",
        }

    if save_slot_has_data_trace is not None:
        save_slot_has_data = [bool(u8(save_slot_has_data_trace["data"], i)) for i in range(4)]
        result["sources"]["filemenu_runtime"]["save_slot_has_data"] = {
            "path": save_slot_has_data_trace["path"],
            "base_address": f"0x{save_slot_has_data_trace['base_address']:08x}",
            "window_size_bytes": len(save_slot_has_data_trace["data"]),
        }
        filemenu_result["save_slot_has_data"] = save_slot_has_data

    main_panel_result = filemenu_result.get("main_panel")
    confirm_panel_result = filemenu_result.get("confirm_panel")
    current_menu = filemenu_result.get("current_menu")
    panel_snapshots_valid = True
    if main_panel_result is not None and confirm_panel_result is not None:
        panel_snapshots_valid = not (
            main_panel_result["grid_data_ptr"] == "0x00000000"
            and main_panel_result["handle_input_ptr"] == "0x00000000"
            and main_panel_result["update_ptr"] == "0x00000000"
            and confirm_panel_result["grid_data_ptr"] == "0x00000000"
            and confirm_panel_result["handle_input_ptr"] == "0x00000000"
            and confirm_panel_result["update_ptr"] == "0x00000000"
        )
    filemenu_result["panel_snapshots_valid"] = panel_snapshots_valid
    if not panel_snapshots_valid:
        filemenu_result["warning"] = (
            "Current filemenu panel snapshots did not resolve to live menu structs. "
            "Treat these panel fields as non-authoritative."
        )
    elif main_panel_result is not None and confirm_panel_result is not None and current_menu is not None:
        exit_mode_guess = 0
        if (
            main_panel_result["state"] == 0
            and current_menu == 1
            and confirm_panel_result["selected"] == 0
        ):
            exit_mode_guess = 2
        elif (
            main_panel_result["state"] == 0
            and main_panel_result["selected"] <= 3
        ):
            exit_mode_guess = 1
        filemenu_result["exit_mode_guess"] = exit_mode_guess
        filemenu_result["exit_mode_guess_name"] = FILE_MENU_EXIT_MODE_NAMES.get(exit_mode_guess)
        selected_slot = main_panel_result["selected"]
        if (
            filemenu_result.get("save_slot_has_data") is not None
            and isinstance(selected_slot, int)
            and 0 <= selected_slot < len(filemenu_result["save_slot_has_data"])
        ):
            filemenu_result["selected_slot_has_data"] = filemenu_result["save_slot_has_data"][selected_slot]

if window_traces:
    result["sources"]["filemenu_windows"] = {}
    windows_result = result["paper_mario_us"].setdefault("windows", {})
    for window_name, window_trace in window_traces.items():
        window_data = window_trace["data"]
        result["sources"]["filemenu_windows"][window_name] = {
            "path": window_trace["path"],
            "base_address": f"0x{window_trace['base_address']:08x}",
            "window_size_bytes": len(window_data),
            "window_sha256": hashlib.sha256(window_data).hexdigest(),
            "window_id": FILE_MENU_WINDOW_IDS[window_name],
        }
        windows_result[window_name] = decode_window(window_data)

output_path.write_text(json.dumps(result, indent=2) + "\n")
PY
}
