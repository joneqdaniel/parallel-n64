#!/usr/bin/env python3
import gzip
import json
import re
import struct
import zlib
from collections import Counter
from pathlib import Path

TXCACHE_FORMAT_VERSION = 0x08000000
REPO_ROOT = Path(__file__).resolve().parent.parent
LEGACY_CACHE_SUFFIXES = (".htc", ".hts")
LEGACY_CACHE_ARCHIVAL_MARKERS = (".pre-", ".bak", ".old", ".orig", ".disabled")
FIELD_RE = re.compile(r"(\w+)=([^\s]+)")
PROVENANCE_LINE_RE = re.compile(
    r"Hi-res keying provenance: "
    r"outcome=(?P<outcome>\w+) "
    r"source_class=(?P<source_class>[\w-]+) "
    r"provenance_class=(?P<provenance_class>[\w-]+) "
    r"mode=(?P<mode>\w+) "
    r"addr=0x(?P<addr>[0-9a-f]+) "
    r"tile=(?P<tile>\d+) "
    r"fmt=(?P<fmt>\d+) "
    r"siz=(?P<siz>\d+) "
    r"pal=(?P<pal>\d+) "
    r"wh=(?P<width>\d+)x(?P<height>\d+) "
    r"key=(?P<key>[0-9a-f]+) "
    r"pcrc=(?P<pcrc>[0-9a-f]+) "
    r"fs=(?P<formatsize>\d+) "
    r"upload=(?P<upload>\w+) "
    r"cycle=(?P<cycle>[\w-]+) "
    r"copy=(?P<copy>\d+) "
    r"tlut=(?P<tlut>\d+) "
    r"tlut_type=(?P<tlut_type>\d+) "
    r"framebuffer=(?P<framebuffer>\d+) "
    r"color_fb=(?P<color_fb>\d+) "
    r"depth_fb=(?P<depth_fb>\d+) "
    r"tmem=0x(?P<tmem>[0-9a-f]+) "
    r"line=(?P<line>\d+) "
    r"key_xy=(?P<key_x>\d+)x(?P<key_y>\d+)",
    re.IGNORECASE,
)


def _legacy_cache_archival_rank(cache_path: Path):
    name = cache_path.name.lower()
    return 1 if any(marker in name for marker in LEGACY_CACHE_ARCHIVAL_MARKERS) else 0


def _legacy_cache_sort_key(cache_path: Path):
    suffix_priority = 0 if cache_path.suffix.lower() == ".htc" else 1
    return (
        _legacy_cache_archival_rank(cache_path),
        suffix_priority,
        len(cache_path.name),
        cache_path.name.lower(),
    )


def resolve_legacy_cache_path(cache_input_path: Path):
    if cache_input_path.is_file():
        if cache_input_path.suffix.lower() not in LEGACY_CACHE_SUFFIXES:
            raise ValueError(f"Unsupported cache format: {cache_input_path}")
        return {
            "input_path": str(cache_input_path),
            "input_kind": "file",
            "resolved_path": str(cache_input_path),
            "resolved_storage": cache_input_path.suffix.lower().lstrip("."),
            "selection_reason": "direct-file",
            "candidate_count": 1,
            "candidate_paths": [str(cache_input_path)],
        }

    if cache_input_path.is_dir():
        candidates = sorted(
            (
                path
                for path in cache_input_path.iterdir()
                if path.is_file() and path.suffix.lower() in LEGACY_CACHE_SUFFIXES
            ),
            key=_legacy_cache_sort_key,
        )
        if not candidates:
            raise ValueError(f"No legacy .hts/.htc cache files found in directory: {cache_input_path}")

        resolved_path = candidates[0]
        return {
            "input_path": str(cache_input_path),
            "input_kind": "directory",
            "resolved_path": str(resolved_path),
            "resolved_storage": resolved_path.suffix.lower().lstrip("."),
            "selection_reason": "directory-singleton" if len(candidates) == 1 else "directory-ranked-current-first",
            "candidate_count": len(candidates),
            "candidate_paths": [str(path) for path in candidates],
        }

    raise ValueError(f"Legacy cache input does not exist or is not supported: {cache_input_path}")


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
                "data_offset": pos + 4,
                "source_path": str(cache_path),
                "storage": "hts",
                "inline_blob": False,
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
                    "inline_blob": True,
                    "blob": payload,
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


def resolve_summary_bundle_reference(summary_path: Path, bundle_reference: str):
    raw_path = Path(bundle_reference)
    candidates = []
    if raw_path.is_absolute():
        candidates.append(("absolute", raw_path))
    else:
        candidates.append(("summary-relative", (summary_path.parent / raw_path).resolve()))
        repo_root_relative = (REPO_ROOT / raw_path).resolve()
        if repo_root_relative not in {candidate_path for _, candidate_path in candidates}:
            candidates.append(("repo-root-relative", repo_root_relative))
        cwd_relative = raw_path.resolve()
        if cwd_relative not in {candidate_path for _, candidate_path in candidates}:
            candidates.append(("cwd-relative", cwd_relative))

    for reference_mode, candidate_path in candidates:
        hires_candidate = candidate_path / "traces" / "hires-evidence.json"
        if hires_candidate.is_file():
            return candidate_path, hires_candidate, reference_mode

    resolved_bundle_path = candidates[0][1]
    hires_path = resolved_bundle_path / "traces" / "hires-evidence.json"
    return resolved_bundle_path, hires_path, candidates[0][0]


def parse_detail_fields(detail: str):
    fields = {}
    for key, value in FIELD_RE.findall(detail):
        fields[key] = value.rstrip(".")
    return fields


def parse_int_field(value, default=0):
    if value is None:
        return default
    try:
        return int(str(value), 0)
    except ValueError:
        return default


def resolve_artifact_path(bundle_path: Path, raw_path: str | None):
    if not raw_path:
        return None
    candidate = Path(raw_path)
    if candidate.is_absolute():
        return candidate if candidate.exists() else None
    for resolved in (
        candidate,
        (REPO_ROOT / candidate),
        (bundle_path / candidate),
        (bundle_path.parent / candidate),
    ):
        if resolved.exists():
            return resolved
    return None


def resolve_bundle_input_path(bundle_input_path: Path, step_frames=None, mode="on"):

    if bundle_input_path.is_dir():
        hires_path = bundle_input_path / "traces" / "hires-evidence.json"
        if hires_path.is_file():
            return {
                "input_path": str(bundle_input_path),
                "input_kind": "bundle-dir",
                "resolved_bundle_path": str(bundle_input_path),
                "resolved_hires_path": str(hires_path),
                "selection_reason": "direct-bundle-dir",
            }
        if bundle_input_path.name == "traces":
            hires_path = bundle_input_path / "hires-evidence.json"
            if hires_path.is_file():
                return {
                    "input_path": str(bundle_input_path),
                    "input_kind": "traces-dir",
                    "resolved_bundle_path": str(bundle_input_path.parent),
                    "resolved_hires_path": str(hires_path),
                    "selection_reason": "traces-dir-parent-bundle",
                }
        raise ValueError(f"Bundle directory does not contain traces/hires-evidence.json: {bundle_input_path}")

    if not bundle_input_path.is_file():
        raise ValueError(f"Bundle input does not exist: {bundle_input_path}")

    if bundle_input_path.name == "hires-evidence.json":
        traces_dir = bundle_input_path.parent
        bundle_dir = traces_dir.parent if traces_dir.name == "traces" else traces_dir
        return {
            "input_path": str(bundle_input_path),
            "input_kind": "hires-evidence-json",
            "resolved_bundle_path": str(bundle_dir),
            "resolved_hires_path": str(bundle_input_path),
            "selection_reason": "direct-hires-evidence",
        }

    summary_path = bundle_input_path
    if bundle_input_path.name == "validation-summary.md":
        sibling_json = bundle_input_path.with_suffix(".json")
        if not sibling_json.is_file():
            raise ValueError(f"Validation summary markdown has no sibling JSON: {bundle_input_path}")
        summary_path = sibling_json

    if summary_path.name == "validation-summary.json":
        data = json.loads(summary_path.read_text())
        steps = data.get("steps", [])
        if not steps:
            raise ValueError(f"Validation summary contains no steps: {summary_path}")

        selected_step = None
        selection_reason = "validation-summary-single-step"
        if step_frames is not None:
            for step in steps:
                if int(step.get("step_frames", -1)) == int(step_frames):
                    selected_step = step
                    selection_reason = "validation-summary-step-match"
                    break
            if selected_step is None:
                raise ValueError(f"Validation summary does not contain step {step_frames}: {summary_path}")
        elif len(steps) == 1:
            selected_step = steps[0]
        else:
            selected_step = steps[0]
            selection_reason = "validation-summary-first-step"

        bundle_key = f"{mode}_bundle"
        resolved_bundle = selected_step.get(bundle_key)
        if not resolved_bundle:
            raise ValueError(f"Validation summary step has no {bundle_key}: {summary_path}")
        resolved_bundle_path, hires_path, bundle_reference_mode = resolve_summary_bundle_reference(summary_path, resolved_bundle)
        if not hires_path.is_file():
            raise ValueError(f"Resolved validation bundle has no hires-evidence.json: {resolved_bundle_path}")
        result = {
            "input_path": str(bundle_input_path),
            "input_kind": "validation-summary",
            "resolved_bundle_path": str(resolved_bundle_path),
            "resolved_hires_path": str(hires_path),
            "bundle_reference_mode": bundle_reference_mode,
            "selection_reason": selection_reason,
            "selected_step_frames": int(selected_step.get("step_frames", 0)),
            "selected_bundle_mode": mode,
            "available_step_frames": [int(step.get("step_frames", 0)) for step in steps],
        }
        return result

    raise ValueError(f"Unsupported bundle input: {bundle_input_path}")


def resolve_context_bundle_input_paths(bundle_input_path: Path, step_frames=None, mode="on"):
    if bundle_input_path.is_dir():
        hires_path = bundle_input_path / "traces" / "hires-evidence.json"
        if hires_path.is_file():
            return [resolve_bundle_input_path(bundle_input_path, step_frames=step_frames, mode=mode)]

        summary_json = bundle_input_path / "validation-summary.json"
        summary_md = bundle_input_path / "validation-summary.md"
        if summary_json.is_file():
            bundle_input_path = summary_json
        elif summary_md.is_file():
            bundle_input_path = summary_md
        else:
            raise ValueError(
                f"Context bundle directory must contain traces/hires-evidence.json or validation-summary.json: {bundle_input_path}"
            )

    if bundle_input_path.is_file():
        summary_path = bundle_input_path
        if bundle_input_path.name == "validation-summary.md":
            sibling_json = bundle_input_path.with_suffix(".json")
            if not sibling_json.is_file():
                raise ValueError(f"Validation summary markdown has no sibling JSON: {bundle_input_path}")
            summary_path = sibling_json

        if summary_path.name == "validation-summary.json":
            data = json.loads(summary_path.read_text())
            fixtures = data.get("fixtures", [])
            if fixtures:
                resolutions = []
                for fixture in fixtures:
                    resolved_bundle = fixture.get("bundle_dir")
                    if not resolved_bundle:
                        raise ValueError(f"Fixture validation summary has no bundle_dir: {summary_path}")
                    resolved_bundle_path, hires_path, bundle_reference_mode = resolve_summary_bundle_reference(
                        summary_path, resolved_bundle
                    )
                    if not hires_path.is_file():
                        raise ValueError(f"Resolved fixture bundle has no hires-evidence.json: {resolved_bundle_path}")
                    resolutions.append(
                        {
                            "input_path": str(bundle_input_path),
                            "input_kind": "fixture-validation-summary",
                            "resolved_bundle_path": str(resolved_bundle_path),
                            "resolved_hires_path": str(hires_path),
                            "bundle_reference_mode": bundle_reference_mode,
                            "selection_reason": "validation-summary-fixtures",
                            "fixture_label": fixture.get("label"),
                            "fixture_id": fixture.get("fixture_id"),
                        }
                    )
                return resolutions

    return [resolve_bundle_input_path(bundle_input_path, step_frames=step_frames, mode=mode)]


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
    if families:
        return families

    seen = set()
    for group in data.get("sampled_object_probe", {}).get("top_groups", []):
        fields = group.get("fields", {})
        low32 = fields.get("sampled_low32")
        formatsize = fields.get("fs")
        if low32 is None or formatsize is None:
            continue
        pair = (int(low32, 16), int(formatsize))
        if pair in seen:
            continue
        seen.add(pair)
        families.append(pair)
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

    family_probe_path = bundle_path / "traces" / "hires-tile-family-report.json"
    if family_probe_path.exists():
        report = json.loads(family_probe_path.read_text())
        family = report.get("family", {})
        formatsize = int(family.get("formatsize", 0))
        runtime_wh = f"{family.get('width')}x{family.get('height')}"
        for item in report.get("rows", []):
            upload_low32 = item.get("key")
            if not upload_low32:
                continue
            key = (int(upload_low32, 16), formatsize)
            context.setdefault(
                key,
                {
                    "mode": family.get("mode"),
                    "runtime_address": item.get("addr"),
                    "runtime_wh": runtime_wh,
                    "requested_formatsize": formatsize,
                    "observed_runtime_pcrc": None,
                    "active_pool": None,
                    "preferred_palette_matches": 0,
                    "uniform_replacement_dims": False,
                    "sample_replacement_dims": None,
                    "usage": None,
                    "emulated_tmem": None,
                },
            )

    return context



def parse_bundle_sampled_object_context(bundle_path: Path):
    hires_path = bundle_path / "traces" / "hires-evidence.json"
    data = json.loads(hires_path.read_text())
    sampled_probe = data.get("sampled_object_probe", {})

    context = {}
    runtime_sampled_objects = []
    runtime_sampled_ids = set()
    runtime_sampled_by_id = {}

    def ingest_sampled_object(sampled_object):
        sampled_object_id = sampled_object.get("sampled_object_id")
        if not sampled_object_id:
            return
        formatsize = int(sampled_object.get("formatsize") or 0)
        if sampled_object_id in runtime_sampled_ids:
            existing = runtime_sampled_by_id[sampled_object_id]
            existing_low32s = {
                item.get("value")
                for item in existing.get("upload_low32s", [])
                if item.get("value")
            }
            for upload in sampled_object.get("upload_low32s", []) or []:
                value = upload.get("value")
                if value and value not in existing_low32s:
                    existing.setdefault("upload_low32s", []).append(upload)
                    existing_low32s.add(value)
            existing_pcrcs = {
                item.get("value")
                for item in existing.get("upload_pcrcs", [])
                if item.get("value")
            }
            for upload in sampled_object.get("upload_pcrcs", []) or []:
                value = upload.get("value")
                if value and value not in existing_pcrcs:
                    existing.setdefault("upload_pcrcs", []).append(upload)
                    existing_pcrcs.add(value)
            existing["runtime_ready"] = bool(existing.get("runtime_ready") or sampled_object.get("runtime_ready"))
            target_sampled_object = existing
        else:
            runtime_sampled_ids.add(sampled_object_id)
            runtime_sampled_by_id[sampled_object_id] = sampled_object
            runtime_sampled_objects.append(sampled_object)
            target_sampled_object = sampled_object

        for upload in target_sampled_object.get("upload_low32s", []):
            value = upload.get("value")
            if not value:
                continue
            key = (int(value, 16), formatsize)
            existing = context.setdefault(key, [])
            if not any(obj.get("sampled_object_id") == target_sampled_object["sampled_object_id"] for obj in existing):
                existing.append(target_sampled_object)

    def ingest_runtime_sampled_probe(sampled_probe_payload):
        raw_groups = []
        raw_groups.extend(sampled_probe_payload.get("groups") or [])
        raw_groups.extend(sampled_probe_payload.get("top_groups") or [])
        for group in raw_groups:
            fields = group.get("fields", group)
            family_available = fields.get("family") == "1"
            unique_repl_dims = parse_int_field(fields.get("unique_repl_dims"), 0)
            sample_repl = fields.get("sample_repl")
            draw_class = (fields.get("draw_class") or "").lower()
            has_concrete_family_signal = (
                family_available or
                unique_repl_dims > 0 or
                (sample_repl is not None and sample_repl != "0x0")
            )
            if draw_class == "triangle" and not has_concrete_family_signal:
                continue
            upload_low32s = group.get("upload_low32s")
            if upload_low32s is None:
                upload_low32 = fields.get("upload_low32")
                upload_low32s = [{"value": upload_low32}] if upload_low32 else []
            upload_pcrcs = group.get("upload_pcrcs")
            if upload_pcrcs is None:
                upload_pcrc = fields.get("upload_pcrc")
                upload_pcrcs = [{"value": upload_pcrc}] if upload_pcrc else []
            formatsize = int(fields.get("fs", "0"))
            sampled_object = {
                "sampled_object_id": (
                    f"sampled-fmt{fields.get('fmt')}-siz{fields.get('siz')}-"
                    f"off{fields.get('off')}-stride{fields.get('stride')}-"
                    f"wh{fields.get('wh')}-fs{fields.get('fs')}-low32{fields.get('sampled_low32')}"
                ),
                "candidate_origin": "runtime-sampled-probe",
                "evidence_authority": "runtime-sampled-probe",
                "draw_class": fields.get("draw_class"),
                "cycle": fields.get("cycle"),
                "fmt": fields.get("fmt"),
                "siz": fields.get("siz"),
                "off": fields.get("off"),
                "stride": fields.get("stride"),
                "wh": fields.get("wh"),
                "formatsize": formatsize,
                "sampled_low32": fields.get("sampled_low32"),
                "sampled_entry_pcrc": fields.get("sampled_entry_pcrc"),
                "sampled_sparse_pcrc": fields.get("sampled_sparse_pcrc"),
                "sampled_entry_count": fields.get("sampled_entry_count"),
                "sampled_used_count": fields.get("sampled_used_count"),
                "runtime_ready": bool(fields.get("sampled_entry_pcrc") or fields.get("sampled_sparse_pcrc")),
                "pack_exact_entry_hit": fields.get("entry_hit") == "1",
                "pack_exact_sparse_hit": fields.get("sparse_hit") == "1",
                "pack_family_available": family_available,
                "unique_replacement_dims": unique_repl_dims,
                "sample_replacement_dims": sample_repl,
                "upload_low32s": upload_low32s,
                "upload_pcrcs": upload_pcrcs,
            }
            ingest_sampled_object(sampled_object)

    ingest_runtime_sampled_probe(sampled_probe)

    def ingest_runtime_provenance_log(log_path_value):
        log_path = resolve_artifact_path(bundle_path, log_path_value)
        if log_path is None or not log_path.exists():
            return
        for line in log_path.read_text(errors="replace").splitlines():
            match = PROVENANCE_LINE_RE.search(line)
            if not match:
                continue
            row = match.groupdict()
            if row.get("outcome") != "hit":
                continue
            sampled_low32 = (row.get("key") or "")[-8:].lower()
            if not sampled_low32:
                continue
            pcrc = (row.get("pcrc") or "").lower()
            upload_pcrcs = []
            if pcrc and pcrc != "00000000":
                upload_pcrcs.append({"value": pcrc})
            sampled_object = {
                "sampled_object_id": (
                    f"sampled-fmt{int(row.get('fmt', 0))}-siz{int(row.get('siz', 0))}-"
                    f"off{int(row.get('tmem', '0'), 16)}-stride{int(row.get('line', 0))}-"
                    f"wh{row.get('width')}x{row.get('height')}-fs{int(row.get('formatsize', 0))}-low32{sampled_low32}"
                ),
                "candidate_origin": "runtime-provenance-hit",
                "transport_hint": None,
                "evidence_authority": "runtime-provenance-hit",
                "draw_class": None,
                "cycle": row.get("cycle"),
                "fmt": int(row.get("fmt", 0)),
                "siz": int(row.get("siz", 0)),
                "off": int(row.get("tmem", "0"), 16),
                "stride": int(row.get("line", 0)),
                "wh": f"{row.get('width')}x{row.get('height')}",
                "formatsize": int(row.get("formatsize", 0)),
                "sampled_low32": sampled_low32,
                "sampled_entry_pcrc": pcrc,
                "sampled_sparse_pcrc": pcrc,
                "sampled_entry_count": None,
                "sampled_used_count": None,
                "runtime_ready": True,
                "pack_exact_entry_hit": True,
                "pack_exact_sparse_hit": True,
                "pack_family_available": True,
                "unique_replacement_dims": None,
                "sample_replacement_dims": None,
                "upload_low32s": [{"value": sampled_low32}],
                "upload_pcrcs": upload_pcrcs,
            }
            ingest_sampled_object(sampled_object)

    ingest_runtime_provenance_log(data.get("log_path"))

    def ingest_runtime_provenance_hits(provenance_payload):
        for bucket in provenance_payload.get("top_buckets") or []:
            fields = bucket.get("fields") or {}
            if fields.get("outcome") != "hit":
                continue
            sample_detail = bucket.get("sample_detail") or ""
            detail_fields = parse_detail_fields(sample_detail)
            key_value = detail_fields.get("key")
            if not key_value:
                continue
            sampled_low32 = key_value[-8:].lower()
            formatsize = parse_int_field(detail_fields.get("fs", fields.get("fs")), 0)
            fmt = parse_int_field(detail_fields.get("fmt", fields.get("fmt")), 0)
            siz = parse_int_field(detail_fields.get("siz", fields.get("siz")), 0)
            wh = detail_fields.get("wh", fields.get("wh")) or "0x0"
            off = parse_int_field(detail_fields.get("tmem"), 0)
            stride = parse_int_field(detail_fields.get("line"), 0)
            pcrc = detail_fields.get("pcrc")
            upload_pcrcs = []
            if pcrc and pcrc != "00000000":
                upload_pcrcs.append({"value": pcrc.lower()})
            sampled_object = {
                "sampled_object_id": (
                    f"sampled-fmt{fmt}-siz{siz}-"
                    f"off{off}-stride{stride}-"
                    f"wh{wh}-fs{formatsize}-low32{sampled_low32}"
                ),
                "candidate_origin": "runtime-provenance-hit",
                "transport_hint": None,
                "evidence_authority": "runtime-provenance-hit",
                "draw_class": None,
                "cycle": fields.get("cycle") or detail_fields.get("cycle"),
                "fmt": fmt,
                "siz": siz,
                "off": off,
                "stride": stride,
                "wh": wh,
                "formatsize": formatsize,
                "sampled_low32": sampled_low32,
                "sampled_entry_pcrc": pcrc,
                "sampled_sparse_pcrc": pcrc,
                "sampled_entry_count": None,
                "sampled_used_count": None,
                "runtime_ready": True,
                "pack_exact_entry_hit": True,
                "pack_exact_sparse_hit": True,
                "pack_family_available": True,
                "unique_replacement_dims": None,
                "sample_replacement_dims": None,
                "upload_low32s": [{"value": sampled_low32}],
                "upload_pcrcs": upload_pcrcs,
            }
            ingest_sampled_object(sampled_object)

    ingest_runtime_provenance_hits(data.get("provenance", {}))

    def matching_runtime_proxies(fmt, siz, stride, wh):
        proxies = []
        for proxy in runtime_sampled_objects:
            if str(proxy.get("fmt")) != str(fmt):
                continue
            if str(proxy.get("siz")) != str(siz):
                continue
            if str(proxy.get("stride")) != str(stride):
                continue
            if proxy.get("wh") != wh:
                continue
            proxies.append(
                {
                    "sampled_object_id": proxy.get("sampled_object_id"),
                    "candidate_origin": proxy.get("candidate_origin"),
                    "evidence_authority": proxy.get("evidence_authority"),
                    "draw_class": proxy.get("draw_class"),
                    "cycle": proxy.get("cycle"),
                    "fmt": proxy.get("fmt"),
                    "siz": proxy.get("siz"),
                    "off": proxy.get("off"),
                    "stride": proxy.get("stride"),
                    "wh": proxy.get("wh"),
                    "formatsize": proxy.get("formatsize"),
                    "sampled_low32": proxy.get("sampled_low32"),
                    "sampled_entry_pcrc": proxy.get("sampled_entry_pcrc"),
                    "sampled_sparse_pcrc": proxy.get("sampled_sparse_pcrc"),
                    "runtime_ready": proxy.get("runtime_ready"),
                }
            )
        return proxies

    family_probe_path = bundle_path / "traces" / "hires-tile-family-report.json"
    if family_probe_path.exists():
        report = json.loads(family_probe_path.read_text())
        plan_source_bundle = report.get("plan_source_bundle")
        if plan_source_bundle:
            source_hires_path = Path(plan_source_bundle) / "traces" / "hires-evidence.json"
            if source_hires_path.exists():
                source_data = json.loads(source_hires_path.read_text())
                ingest_runtime_sampled_probe(source_data.get("sampled_object_probe", {}))
        family = report.get("family", {})
        formatsize = int(family.get("formatsize", 0))
        observed_fmt = int(family.get("observed_fmt", 0))
        row_bytes = int(family.get("row_bytes", 0))
        top_draw = None
        if report.get("draw_usage_summary"):
            top_draw = report["draw_usage_summary"][0].get("sample", {})
        for item in report.get("parent_surface_checks", []):
            upload_low32 = item.get("upload_key")
            if not upload_low32:
                continue
            for variant in item.get("variants", []):
                if int(variant.get("delta", 0)) != 0:
                    continue
                sampled_size = int(variant.get("sampled_size", 0))
                if sampled_size >= int(family.get("observed_siz", sampled_size)):
                    continue
                sampled_wh = f"{variant.get('sampled_width')}x{variant.get('sampled_height')}"
                runtime_proxies = matching_runtime_proxies(
                    observed_fmt,
                    sampled_size,
                    row_bytes,
                    sampled_wh,
                )
                sampled_object = {
                    "sampled_object_id": (
                        f"sampled-fmt{observed_fmt}-siz{sampled_size}-"
                        f"off0-stride{row_bytes}-wh{sampled_wh}-fs{formatsize}-low32{variant.get('low32')}"
                    ),
                    "candidate_origin": "tile-family-parent-surface",
                    "transport_hint": "same-start-parent-surface",
                    "evidence_authority": "transport-hint-only",
                    "draw_class": top_draw.get("draw_class") if top_draw else None,
                    "cycle": top_draw.get("cycle") if top_draw else None,
                    "fmt": observed_fmt,
                    "siz": sampled_size,
                    "off": 0,
                    "stride": row_bytes,
                    "wh": sampled_wh,
                    "formatsize": formatsize,
                    "sampled_low32": variant.get("low32"),
                    "sampled_entry_pcrc": None,
                    "sampled_sparse_pcrc": None,
                    "sampled_entry_count": None,
                    "sampled_used_count": None,
                    "runtime_ready": False,
                    "pack_exact_entry_hit": False,
                    "pack_exact_sparse_hit": False,
                    "pack_family_available": int(variant.get("family_entry_count", 0)) > 0,
                    "unique_replacement_dims": len(variant.get("active_replacement_dims", [])),
                    "sample_replacement_dims": (variant.get("active_replacement_dims") or [{}])[0].get("dims"),
                    "runtime_proxy_candidates": runtime_proxies,
                    "runtime_proxy_count": len(runtime_proxies),
                    "runtime_proxy_unique": len(runtime_proxies) == 1,
                    "runtime_proxy_identity_mismatch": any(
                        proxy.get("sampled_low32") != variant.get("low32")
                        for proxy in runtime_proxies
                    ),
                    "upload_low32s": [{"value": upload_low32}],
                    "upload_pcrcs": [],
                }
                key = (int(upload_low32, 16), formatsize)
                existing = context.setdefault(key, [])
                if not any(obj.get("sampled_object_id") == sampled_object["sampled_object_id"] for obj in existing):
                    existing.append(sampled_object)

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
    if isinstance(entries, dict):
        return list(entries.get(texture_crc, []))
    return [entry for entry in entries if entry["texture_crc"] == texture_crc]


def index_entries_by_texture_crc(entries):
    indexed = {}
    for entry in entries:
        indexed.setdefault(int(entry["texture_crc"]), []).append(entry)
    return indexed


GL_TEXFMT_GZ = 0x80000000
GL_RGB = 0x1907
GL_RGBA = 0x1908
GL_LUMINANCE = 0x1909
GL_UNSIGNED_BYTE = 0x1401
GL_UNSIGNED_SHORT_4_4_4_4 = 0x8033
GL_UNSIGNED_SHORT_5_5_5_1 = 0x8034
GL_UNSIGNED_SHORT_5_6_5 = 0x8363
GL_RGB8 = 0x8051
GL_RGBA8 = 0x8058


def _expand_4_to_8(value):
    return ((value & 0xF) << 4) | (value & 0xF)


def _expand_5_to_8(value):
    value &= 0x1F
    return ((value << 3) | (value >> 2)) & 0xFF


def _expand_6_to_8(value):
    value &= 0x3F
    return ((value << 2) | (value >> 4)) & 0xFF


def expected_decoded_size(entry):
    fmt = entry.get("texture_format")
    pixel_type = entry.get("pixel_type")
    internal_format = entry.get("format")
    width = int(entry.get("width", 0))
    height = int(entry.get("height", 0))
    if width <= 0 or height <= 0:
        return 0
    bpp = 0
    if fmt == GL_RGBA and pixel_type == GL_UNSIGNED_BYTE:
        bpp = 4
    elif fmt == GL_RGB and pixel_type == GL_UNSIGNED_BYTE:
        bpp = 3
    elif fmt == GL_RGB and pixel_type == GL_UNSIGNED_SHORT_5_6_5:
        bpp = 2
    elif fmt == GL_RGBA and pixel_type in (GL_UNSIGNED_SHORT_4_4_4_4, GL_UNSIGNED_SHORT_5_5_5_1):
        bpp = 2
    elif fmt == GL_LUMINANCE and pixel_type == GL_UNSIGNED_BYTE:
        bpp = 1
    elif internal_format == GL_RGBA8:
        bpp = 4
    elif internal_format == GL_RGB8:
        bpp = 3
    return width * height * bpp if bpp else 0


def read_entry_blob(cache_path: Path, entry, cache_bytes=None):
    if entry.get("inline_blob"):
        return entry.get("blob", b"")
    data_offset = entry.get("data_offset")
    data_size = entry.get("data_size")
    if data_offset is None or data_size is None:
        raise ValueError("Entry is missing blob location metadata.")
    if cache_bytes is not None:
        blob = cache_bytes[int(data_offset):int(data_offset) + int(data_size)]
        if len(blob) != int(data_size):
            raise ValueError("Failed to read full entry blob from cached bytes.")
        return blob
    with cache_path.open("rb") as fp:
        fp.seek(int(data_offset))
        blob = fp.read(int(data_size))
    if len(blob) != int(data_size):
        raise ValueError("Failed to read full entry blob.")
    return blob


def decompress_entry_blob(entry, blob):
    if (int(entry.get("format", 0)) & GL_TEXFMT_GZ) == 0:
        return blob
    expected_size = expected_decoded_size(entry)
    if expected_size == 0:
        raise ValueError("Unsupported compressed entry format.")
    pixel_data = zlib.decompress(blob)
    if len(pixel_data) != expected_size:
        return pixel_data
    return pixel_data


def decode_pixels_rgba8(entry, pixel_data):
    width = int(entry.get("width", 0))
    height = int(entry.get("height", 0))
    pixel_count = width * height
    fmt = int(entry.get("texture_format", 0))
    pixel_type = int(entry.get("pixel_type", 0))
    internal_format = int(entry.get("format", 0))
    rgba = bytearray(pixel_count * 4)

    if fmt == GL_RGBA and pixel_type == GL_UNSIGNED_BYTE:
        if len(pixel_data) < len(rgba):
            raise ValueError("RGBA8 pixel payload too small.")
        return bytes(pixel_data[:len(rgba)])

    if fmt == GL_RGB and pixel_type == GL_UNSIGNED_BYTE:
        if len(pixel_data) < pixel_count * 3:
            raise ValueError("RGB8 pixel payload too small.")
        for i in range(pixel_count):
            rgba[4 * i + 0] = pixel_data[3 * i + 0]
            rgba[4 * i + 1] = pixel_data[3 * i + 1]
            rgba[4 * i + 2] = pixel_data[3 * i + 2]
            rgba[4 * i + 3] = 255
        return bytes(rgba)

    if fmt == GL_RGB and pixel_type == GL_UNSIGNED_SHORT_5_6_5:
        if len(pixel_data) < pixel_count * 2:
            raise ValueError("RGB565 pixel payload too small.")
        for i in range(pixel_count):
            value = pixel_data[2 * i + 0] | (pixel_data[2 * i + 1] << 8)
            rgba[4 * i + 0] = _expand_5_to_8((value >> 11) & 0x1F)
            rgba[4 * i + 1] = _expand_6_to_8((value >> 5) & 0x3F)
            rgba[4 * i + 2] = _expand_5_to_8(value & 0x1F)
            rgba[4 * i + 3] = 255
        return bytes(rgba)

    if fmt == GL_RGBA and pixel_type == GL_UNSIGNED_SHORT_5_5_5_1:
        if len(pixel_data) < pixel_count * 2:
            raise ValueError("RGBA5551 pixel payload too small.")
        for i in range(pixel_count):
            value = pixel_data[2 * i + 0] | (pixel_data[2 * i + 1] << 8)
            rgba[4 * i + 0] = _expand_5_to_8((value >> 11) & 0x1F)
            rgba[4 * i + 1] = _expand_5_to_8((value >> 6) & 0x1F)
            rgba[4 * i + 2] = _expand_5_to_8((value >> 1) & 0x1F)
            rgba[4 * i + 3] = 255 if (value & 1) else 0
        return bytes(rgba)

    if fmt == GL_RGBA and pixel_type == GL_UNSIGNED_SHORT_4_4_4_4:
        if len(pixel_data) < pixel_count * 2:
            raise ValueError("RGBA4444 pixel payload too small.")
        for i in range(pixel_count):
            value = pixel_data[2 * i + 0] | (pixel_data[2 * i + 1] << 8)
            rgba[4 * i + 0] = _expand_4_to_8((value >> 12) & 0xF)
            rgba[4 * i + 1] = _expand_4_to_8((value >> 8) & 0xF)
            rgba[4 * i + 2] = _expand_4_to_8((value >> 4) & 0xF)
            rgba[4 * i + 3] = _expand_4_to_8(value & 0xF)
        return bytes(rgba)

    if fmt == GL_LUMINANCE and pixel_type == GL_UNSIGNED_BYTE:
        if len(pixel_data) < pixel_count:
            raise ValueError("L8 pixel payload too small.")
        for i in range(pixel_count):
            value = pixel_data[i]
            rgba[4 * i + 0] = value
            rgba[4 * i + 1] = value
            rgba[4 * i + 2] = value
            rgba[4 * i + 3] = 255
        return bytes(rgba)

    if internal_format == GL_RGBA8 and len(pixel_data) >= len(rgba):
        return bytes(pixel_data[:len(rgba)])

    raise ValueError("Unsupported pixel format for RGBA8 decode.")


def find_cache_entry(entries, checksum64, formatsize):
    exact = None
    generic = None
    for entry in entries:
        if int(entry.get("checksum64", 0)) != int(checksum64):
            continue
        entry_formatsize = int(entry.get("formatsize", 0))
        if entry_formatsize == int(formatsize):
            exact = entry
        elif entry_formatsize == 0:
            generic = entry
    return exact or generic


def decode_entry_rgba8(cache_path: Path, entry, cache_bytes=None):
    blob = read_entry_blob(cache_path, entry, cache_bytes=cache_bytes)
    pixel_data = decompress_entry_blob(entry, blob)
    return decode_pixels_rgba8(entry, pixel_data)
