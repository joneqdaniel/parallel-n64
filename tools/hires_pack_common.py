#!/usr/bin/env python3
import gzip
import json
import struct
from collections import Counter
from pathlib import Path

TXCACHE_FORMAT_VERSION = 0x08000000


def parse_hts_entries(cache_path: Path):
    data = cache_path.read_bytes()
    if len(data) < 16:
        return []

    version = struct.unpack_from("<i", data, 0)[0]
    if version == TXCACHE_FORMAT_VERSION:
        storage_pos = struct.unpack_from("<q", data, 8)[0]
        old_version = False
    else:
        storage_pos = struct.unpack_from("<q", data, 4)[0]
        old_version = True

    if storage_pos <= 0 or storage_pos + 4 > len(data):
        return []

    storage_size = struct.unpack_from("<i", data, storage_pos)[0]
    offset = storage_pos + 4
    entries = []

    for _ in range(storage_size):
        if offset + 16 > len(data):
            break
        checksum64 = struct.unpack_from("<Q", data, offset)[0]
        packed = struct.unpack_from("<q", data, offset + 8)[0]
        offset += 16

        record_offset = packed & 0x0000FFFFFFFFFFFF
        formatsize = (packed >> 48) & 0xFFFF
        if record_offset + 17 > len(data):
            continue

        pos = record_offset
        width, height, fmt, texture_format, pixel_type = struct.unpack_from("<IIIHH", data, pos)
        pos += struct.calcsize("<IIIHH")
        is_hires = struct.unpack_from("<B", data, pos)[0]
        pos += 1
        if not old_version:
            record_formatsize = struct.unpack_from("<H", data, pos)[0]
            pos += 2
            if formatsize == 0:
                formatsize = record_formatsize
        data_size = struct.unpack_from("<I", data, pos)[0]

        entries.append(
            {
                "checksum64": checksum64,
                "palette_crc": (checksum64 >> 32) & 0xFFFFFFFF,
                "texture_crc": checksum64 & 0xFFFFFFFF,
                "formatsize": formatsize,
                "width": width,
                "height": height,
                "format": fmt,
                "texture_format": texture_format,
                "pixel_type": pixel_type,
                "is_hires": bool(is_hires),
                "data_size": data_size,
                "source_path": str(cache_path),
                "storage": "hts",
            }
        )

    return entries


def parse_htc_entries(cache_path: Path):
    entries = []
    with gzip.open(cache_path, "rb") as fp:
        version_raw = fp.read(4)
        if len(version_raw) != 4:
            return []
        version = struct.unpack("<i", version_raw)[0]
        old_version = version != TXCACHE_FORMAT_VERSION
        if not old_version:
            if len(fp.read(4)) != 4:
                return []

        while True:
            checksum_raw = fp.read(8)
            if not checksum_raw:
                break
            if len(checksum_raw) != 8:
                break
            checksum64 = struct.unpack("<Q", checksum_raw)[0]

            header = fp.read(struct.calcsize("<IIIHHB"))
            if len(header) != struct.calcsize("<IIIHHB"):
                break
            width, height, fmt, texture_format, pixel_type, is_hires = struct.unpack("<IIIHHB", header)
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
            payload = fp.read(data_size)
            if len(payload) != data_size:
                break

            entries.append(
                {
                    "checksum64": checksum64,
                    "palette_crc": (checksum64 >> 32) & 0xFFFFFFFF,
                    "texture_crc": checksum64 & 0xFFFFFFFF,
                    "formatsize": formatsize,
                    "width": width,
                    "height": height,
                    "format": fmt,
                    "texture_format": texture_format,
                    "pixel_type": pixel_type,
                    "is_hires": bool(is_hires),
                    "data_size": data_size,
                    "source_path": str(cache_path),
                    "storage": "htc",
                }
            )

    return entries


def parse_cache_entries(cache_path: Path):
    suffix = cache_path.suffix.lower()
    if suffix == ".hts":
        return parse_hts_entries(cache_path)
    if suffix == ".htc":
        return parse_htc_entries(cache_path)
    raise ValueError(f"Unsupported cache format: {cache_path}")


def parse_bundle_families(bundle_path: Path):
    hires_path = bundle_path / "traces" / "hires-evidence.json"
    data = json.loads(hires_path.read_text())
    families = []
    for record in data.get("ci_palette_probe", {}).get("families", []):
        low32 = record.get("low32")
        formatsize = record.get("fs")
        if low32 is None or formatsize is None:
            continue
        families.append((int(low32, 16), int(formatsize)))
    return families


def parse_bundle_ci_context(bundle_path: Path):
    hires_path = bundle_path / "traces" / "hires-evidence.json"
    data = json.loads(hires_path.read_text())
    ci_probe = data.get("ci_palette_probe", {})

    usage_by_key = {}
    for record in ci_probe.get("usages", []):
        key = (
            record.get("mode"),
            record.get("wh"),
            int(record.get("fs", "0")),
        )
        usage_by_key[key] = {
            "used_count": int(record.get("used_count", "0")),
            "used_min": int(record.get("used_min", "0")),
            "used_max": int(record.get("used_max", "0")),
            "mask_crc": record.get("mask_crc"),
            "sparse_pcrc": record.get("sparse_pcrc"),
        }

    emulated_tmem_by_key = {}
    for record in ci_probe.get("emulated_tmem", []):
        key = (
            record.get("mode"),
            record.get("wh"),
            int(record.get("fs", "0")),
        )
        emulated_tmem_by_key[key] = {
            "entry_pcrc": record.get("entry_pcrc"),
            "sparse_pcrc": record.get("sparse_pcrc"),
        }

    context = {}
    for family in ci_probe.get("families", []):
        key = (
            int(family.get("low32"), 16),
            int(family.get("fs", "0")),
        )
        observation_key = (
            family.get("mode"),
            family.get("wh"),
            int(family.get("fs", "0")),
        )
        context[key] = {
            "mode": family.get("mode"),
            "runtime_address": family.get("addr"),
            "runtime_wh": family.get("wh"),
            "requested_formatsize": int(family.get("fs", "0")),
            "observed_runtime_pcrc": family.get("pcrc"),
            "active_pool": family.get("active_pool"),
            "preferred_palette_matches": int(family.get("preferred_palette_matches", "0")),
            "uniform_replacement_dims": family.get("uniform_repl_dims") == "1",
            "sample_replacement_dims": family.get("sample_repl"),
            "usage": usage_by_key.get(observation_key),
            "emulated_tmem": emulated_tmem_by_key.get(observation_key),
        }

    return context


def classify_family(summary):
    if summary["active_pool"] == "exact":
        return "exact-authoritative"
    if summary["active_entry_count"] == 0:
        return "missing-active-pool"
    if summary["active_unique_repl_dim_count"] == 1:
        if summary["active_unique_palette_count"] == 1:
            return "compat-unique"
        return "compat-repl-dims-unique"
    return "ambiguous-import-or-policy"


def build_family_summary(entries, texture_crc, formatsize):
    family_entries = collect_family_entries(entries, texture_crc)
    exact_entries = [entry for entry in family_entries if entry["formatsize"] == formatsize]
    generic_entries = [entry for entry in family_entries if entry["formatsize"] == 0]
    active_entries = exact_entries if exact_entries else generic_entries
    active_pool = "exact" if exact_entries else "generic"

    palette_counter = Counter(entry["palette_crc"] for entry in active_entries)
    dims_counter = Counter(f"{entry['width']}x{entry['height']}" for entry in active_entries)
    formatsize_counter = Counter(entry["formatsize"] for entry in family_entries)

    summary = {
        "low32": f"{texture_crc:08x}",
        "formatsize": formatsize,
        "family_entry_count": len(family_entries),
        "exact_formatsize_entries": len(exact_entries),
        "generic_formatsize_entries": len(generic_entries),
        "active_pool": active_pool,
        "active_entry_count": len(active_entries),
        "active_unique_checksum_count": len({entry["checksum64"] for entry in active_entries}),
        "active_unique_palette_count": len(palette_counter),
        "active_unique_repl_dim_count": len(dims_counter),
        "active_palette_crc_counts": [
            {"palette_crc": f"{palette_crc:08x}", "count": count}
            for palette_crc, count in palette_counter.most_common()
        ],
        "active_replacement_dims": [
            {"dims": dims, "count": count}
            for dims, count in dims_counter.most_common()
        ],
        "family_formatsizes": [
            {"formatsize": fs, "count": count}
            for fs, count in sorted(formatsize_counter.items(), key=lambda item: (item[0], item[1]))
        ],
        "sample_checksums": [
            f"{entry['checksum64']:016x}"
            for entry in active_entries[:10]
        ],
    }
    summary["recommended_tier"] = classify_family(summary)
    return summary


def collect_family_entries(entries, texture_crc):
    return [entry for entry in entries if entry["texture_crc"] == texture_crc]
