#!/usr/bin/env python3
"""Generate and validate tiny hi-res replacement cache packs (.hts/.htc)."""

from __future__ import annotations

import argparse
import csv
import gzip
import json
import struct
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Sequence

TXCACHE_FORMAT_VERSION = 0x08000000
GL_TEXFMT_GZ = 0x80000000
GL_RGBA8 = 0x8058
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401


def _parse_u64(value: str) -> int:
    text = value.strip()
    if not text:
        raise ValueError("empty integer field")
    return int(text, 0)


def _parse_u16(value: str) -> int:
    parsed = _parse_u64(value)
    if not 0 <= parsed <= 0xFFFF:
        raise ValueError(f"value out of uint16 range: {value}")
    return parsed


def _parse_u32_optional(value: str) -> int | None:
    text = value.strip()
    if not text:
        return None
    parsed = int(text, 0)
    if not 0 <= parsed <= 0xFFFFFFFF:
        raise ValueError(f"value out of uint32 range: {value}")
    return parsed


def _signed_i64(value: int) -> int:
    value &= 0xFFFFFFFFFFFFFFFF
    if value >= (1 << 63):
        return value - (1 << 64)
    return value


def _stable_rgb(checksum64: int, formatsize: int) -> tuple[int, int, int]:
    seed = (checksum64 ^ ((formatsize & 0xFFFF) << 40) ^ 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF

    def next_byte() -> int:
        nonlocal seed
        seed = (seed * 6364136223846793005 + 1) & 0xFFFFFFFFFFFFFFFF
        return (seed >> 24) & 0xFF

    r = 56 + (next_byte() % 176)
    g = 56 + (next_byte() % 176)
    b = 56 + (next_byte() % 176)
    return r, g, b


def _pattern_rgba(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    r, g, b = rgb
    border = (255 - r, 255 - g, 255 - b)
    accent = (255, g, b)
    shade = (min(255, r // 2 + 64), min(255, g // 2 + 64), min(255, b // 2 + 64))
    pixels = bytearray(width * height * 4)

    stride = max(3, min(width, height) // 4)
    for y in range(height):
        for x in range(width):
            i = (y * width + x) * 4
            is_border = x == 0 or y == 0 or x == (width - 1) or y == (height - 1)
            is_diag = ((x + y) % stride) == 0
            is_checker = (((x // 4) + (y // 4)) & 1) == 1
            if is_border:
                pr, pg, pb = border
            elif is_diag:
                pr, pg, pb = accent
            elif is_checker:
                pr, pg, pb = shade
            else:
                pr, pg, pb = r, g, b
            pixels[i + 0] = pr
            pixels[i + 1] = pg
            pixels[i + 2] = pb
            pixels[i + 3] = 255

    return bytes(pixels)


@dataclass
class MiniPackEntry:
    checksum64: int
    formatsize: int
    orig_w: int
    orig_h: int
    repl_w: int
    repl_h: int
    color: tuple[int, int, int]
    rgba8: bytes


def _read_key_rows(keys_path: Path, scale: int, default_w: int, default_h: int) -> List[MiniPackEntry]:
    with keys_path.open("r", encoding="utf-8", newline="") as fp:
        reader = csv.DictReader(fp)
        fields = set(reader.fieldnames or [])
        required = {"checksum64", "formatsize"}
        missing = required - fields
        if missing:
            raise ValueError(f"missing required CSV columns: {', '.join(sorted(missing))}")

        entries: List[MiniPackEntry] = []
        for row_index, row in enumerate(reader, start=2):
            try:
                checksum64 = _parse_u64(row["checksum64"])
                formatsize = _parse_u16(row["formatsize"])
                orig_w = _parse_u32_optional(row.get("orig_w", "")) or 0
                orig_h = _parse_u32_optional(row.get("orig_h", "")) or 0
                repl_w = _parse_u32_optional(row.get("repl_w", ""))
                repl_h = _parse_u32_optional(row.get("repl_h", ""))
            except ValueError as exc:
                raise ValueError(f"{keys_path}:{row_index}: {exc}") from exc

            if repl_w is None:
                repl_w = max(1, (orig_w * scale) if orig_w else default_w)
            if repl_h is None:
                repl_h = max(1, (orig_h * scale) if orig_h else default_h)

            if repl_w <= 0 or repl_h <= 0:
                raise ValueError(f"{keys_path}:{row_index}: replacement dimensions must be > 0")

            color = _stable_rgb(checksum64, formatsize)
            rgba8 = _pattern_rgba(repl_w, repl_h, color)
            entries.append(
                MiniPackEntry(
                    checksum64=checksum64 & 0xFFFFFFFFFFFFFFFF,
                    formatsize=formatsize,
                    orig_w=orig_w,
                    orig_h=orig_h,
                    repl_w=repl_w,
                    repl_h=repl_h,
                    color=color,
                    rgba8=rgba8,
                )
            )

    if not entries:
        raise ValueError(f"{keys_path}: no data rows found")
    return entries


def _encoded_blob(entry: MiniPackEntry, compress: str) -> tuple[int, bytes]:
    if compress == "zlib":
        return GL_RGBA8 | GL_TEXFMT_GZ, zlib.compress(entry.rgba8, level=9)
    return GL_RGBA8, entry.rgba8


def _write_hts(path: Path, entries: Sequence[MiniPackEntry], compress: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as fp:
        fp.write(struct.pack("<i", TXCACHE_FORMAT_VERSION))
        fp.write(struct.pack("<i", 0))  # config
        fp.write(struct.pack("<q", 0))  # storage_pos placeholder

        offsets: List[int] = []
        for entry in entries:
            encoded_format, blob = _encoded_blob(entry, compress)
            offsets.append(fp.tell())
            fp.write(
                struct.pack(
                    "<IIIHHBHI",
                    entry.repl_w,
                    entry.repl_h,
                    encoded_format,
                    GL_RGBA,
                    GL_UNSIGNED_BYTE,
                    1,  # is_hires
                    entry.formatsize,
                    len(blob),
                )
            )
            fp.write(blob)

        storage_pos = fp.tell()
        fp.write(struct.pack("<i", len(entries)))
        for entry, offset in zip(entries, offsets):
            packed = ((entry.formatsize & 0xFFFF) << 48) | (offset & 0x0000FFFFFFFFFFFF)
            fp.write(struct.pack("<Qq", entry.checksum64, _signed_i64(packed)))

        fp.seek(8)
        fp.write(struct.pack("<q", storage_pos))


def _write_htc(path: Path, entries: Sequence[MiniPackEntry], compress: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(path, "wb") as fp:
        fp.write(struct.pack("<i", TXCACHE_FORMAT_VERSION))
        fp.write(struct.pack("<i", 0))  # config
        for entry in entries:
            encoded_format, blob = _encoded_blob(entry, compress)
            fp.write(
                struct.pack(
                    "<QIIIHHBHI",
                    entry.checksum64,
                    entry.repl_w,
                    entry.repl_h,
                    encoded_format,
                    GL_RGBA,
                    GL_UNSIGNED_BYTE,
                    1,  # is_hires
                    entry.formatsize,
                    len(blob),
                )
            )
            fp.write(blob)


def _validate_hts(path: Path) -> None:
    data = path.read_bytes()
    if len(data) < 12:
        raise ValueError(f"{path}: file too small for .hts")

    version = struct.unpack_from("<i", data, 0)[0]
    if version == TXCACHE_FORMAT_VERSION:
        if len(data) < 16:
            raise ValueError(f"{path}: truncated new-format .hts header")
        old_version = False
        storage_pos = struct.unpack_from("<q", data, 8)[0]
    else:
        old_version = True
        storage_pos = struct.unpack_from("<q", data, 4)[0]

    if storage_pos <= 0 or storage_pos >= len(data):
        raise ValueError(f"{path}: invalid storage_pos {storage_pos}")

    cursor = storage_pos
    if cursor + 4 > len(data):
        raise ValueError(f"{path}: truncated storage size")
    storage_size = struct.unpack_from("<i", data, cursor)[0]
    cursor += 4
    if storage_size <= 0:
        raise ValueError(f"{path}: invalid storage_size {storage_size}")

    index_bytes = storage_size * (8 + 8)
    if cursor + index_bytes > len(data):
        raise ValueError(f"{path}: truncated index table")

    min_record_header = 4 + 4 + 4 + 2 + 2 + 1 + (0 if old_version else 2) + 4
    for _ in range(storage_size):
        _checksum64 = struct.unpack_from("<Q", data, cursor)[0]
        packed = struct.unpack_from("<q", data, cursor + 8)[0] & 0xFFFFFFFFFFFFFFFF
        cursor += 16
        offset = packed & 0x0000FFFFFFFFFFFF

        if offset >= len(data):
            raise ValueError(f"{path}: index offset out of range: {offset}")
        if offset + min_record_header > len(data):
            raise ValueError(f"{path}: truncated record header at offset {offset}")

        ro = offset
        _width = struct.unpack_from("<I", data, ro)[0]
        _height = struct.unpack_from("<I", data, ro + 4)[0]
        _format = struct.unpack_from("<I", data, ro + 8)[0]
        _texture_format = struct.unpack_from("<H", data, ro + 12)[0]
        _pixel_type = struct.unpack_from("<H", data, ro + 14)[0]
        ro += 17  # includes is_hires byte
        if not old_version:
            _record_formatsize = struct.unpack_from("<H", data, ro)[0]
            ro += 2
        data_size = struct.unpack_from("<I", data, ro)[0]
        ro += 4
        if data_size == 0:
            raise ValueError(f"{path}: zero-sized record payload at offset {offset}")
        if ro + data_size > len(data):
            raise ValueError(f"{path}: payload overruns file at offset {offset}")


def _read_exact(data: bytes, offset: int, size: int) -> tuple[bytes, int]:
    end = offset + size
    if end > len(data):
        raise ValueError("truncated data")
    return data[offset:end], end


def _validate_htc(path: Path) -> None:
    data = gzip.decompress(path.read_bytes())
    if len(data) < 4:
        raise ValueError(f"{path}: file too small for .htc")

    version = struct.unpack_from("<i", data, 0)[0]
    old_version = version != TXCACHE_FORMAT_VERSION
    cursor = 4
    if not old_version:
        _config, cursor = _read_exact(data, cursor, 4)

    while cursor < len(data):
        _, cursor = _read_exact(data, cursor, 8)  # checksum64
        _, cursor = _read_exact(data, cursor, 4)  # width
        _, cursor = _read_exact(data, cursor, 4)  # height
        _, cursor = _read_exact(data, cursor, 4)  # format
        _, cursor = _read_exact(data, cursor, 2)  # texture_format
        _, cursor = _read_exact(data, cursor, 2)  # pixel_type
        _, cursor = _read_exact(data, cursor, 1)  # is_hires
        if not old_version:
            _, cursor = _read_exact(data, cursor, 2)  # formatsize
        data_size_raw, cursor = _read_exact(data, cursor, 4)
        data_size = struct.unpack("<I", data_size_raw)[0]
        if data_size == 0:
            raise ValueError(f"{path}: zero-sized payload in record")
        _, cursor = _read_exact(data, cursor, data_size)


def _parse_emit_list(value: str) -> List[str]:
    requested = []
    for token in (item.strip().lower() for item in value.split(",")):
        if not token:
            continue
        if token not in {"hts", "htc"}:
            raise ValueError(f"unsupported emit value: {token}")
        if token not in requested:
            requested.append(token)
    if not requested:
        raise ValueError("emit list is empty")
    return requested


def _run_from_keys(args: argparse.Namespace) -> int:
    entries = _read_key_rows(args.keys, args.scale, args.default_width, args.default_height)
    out_dir: Path = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    emitted_files: List[Path] = []
    if "hts" in args.emit:
        hts_path = out_dir / f"{args.name}.hts"
        _write_hts(hts_path, entries, args.compress)
        emitted_files.append(hts_path)
    if "htc" in args.emit:
        htc_path = out_dir / f"{args.name}.htc"
        _write_htc(htc_path, entries, args.compress)
        emitted_files.append(htc_path)

    manifest_path = out_dir / f"{args.name}_manifest.json"
    manifest = {
        "pack_name": args.name,
        "keys_file": str(args.keys),
        "compress": args.compress,
        "scale": args.scale,
        "entry_count": len(entries),
        "files": [str(path.name) for path in emitted_files],
        "entries": [
            {
                "checksum64": f"0x{entry.checksum64:016x}",
                "formatsize": f"0x{entry.formatsize:04x}",
                "orig": [entry.orig_w, entry.orig_h],
                "repl": [entry.repl_w, entry.repl_h],
                "format": "GL_RGBA8",
                "compressed": args.compress == "zlib",
                "color": [entry.color[0], entry.color[1], entry.color[2], 255],
            }
            for entry in entries
        ],
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    print(f"[minipack] generated {len(entries)} entries in {out_dir}")
    for file in emitted_files:
        print(f"[minipack] wrote {file}")
    print(f"[minipack] wrote {manifest_path}")
    return 0


def _iter_validate_targets(path: Path) -> Iterable[Path]:
    if path.is_file():
        yield path
        return
    if not path.is_dir():
        raise ValueError(f"not a file or directory: {path}")

    for candidate in sorted(path.iterdir()):
        suffix = candidate.suffix.lower()
        if suffix in {".hts", ".htc"} and candidate.is_file():
            yield candidate


def _run_validate(args: argparse.Namespace) -> int:
    targets = list(_iter_validate_targets(args.path))
    if not targets:
        raise ValueError(f"no .hts/.htc files found at {args.path}")

    for target in targets:
        suffix = target.suffix.lower()
        if suffix == ".hts":
            _validate_hts(target)
        elif suffix == ".htc":
            _validate_htc(target)
        else:
            raise ValueError(f"unsupported file extension: {target}")
        print(f"[minipack] valid: {target}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate tiny hi-res replacement cache packs for paraLLEl replacement debugging."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    from_keys = subparsers.add_parser("from-keys", help="Generate pack(s) from a CSV key list.")
    from_keys.add_argument("--keys", type=Path, required=True, help="Input CSV path.")
    from_keys.add_argument("--out-dir", type=Path, required=True, help="Output cache directory.")
    from_keys.add_argument("--name", default="MINIPACK", help="Pack file stem (default: MINIPACK).")
    from_keys.add_argument(
        "--emit",
        type=_parse_emit_list,
        default=["hts"],
        help="Comma-separated output formats: hts,htc (default: hts).",
    )
    from_keys.add_argument(
        "--compress",
        choices=["none", "zlib"],
        default="none",
        help="Payload compression mode (default: none).",
    )
    from_keys.add_argument("--scale", type=int, default=4, help="Replacement scale for orig_w/orig_h rows (default: 4).")
    from_keys.add_argument(
        "--default-width",
        type=int,
        default=64,
        help="Default replacement width when orig/repl width is absent (default: 64).",
    )
    from_keys.add_argument(
        "--default-height",
        type=int,
        default=64,
        help="Default replacement height when orig/repl height is absent (default: 64).",
    )
    from_keys.set_defaults(func=_run_from_keys)

    validate = subparsers.add_parser("validate", help="Validate .hts/.htc files or a cache directory.")
    validate.add_argument("--path", type=Path, required=True, help="File or directory to validate.")
    validate.set_defaults(func=_run_validate)

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except Exception as exc:  # noqa: BLE001
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
