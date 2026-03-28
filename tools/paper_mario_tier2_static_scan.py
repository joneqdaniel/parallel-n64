#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class SourceRef:
    path: Path
    line: int

    def to_json(self) -> dict[str, Any]:
        return {"path": str(self.path), "line": self.line}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build a narrow Tier 2 static scan for Paper Mario title/file-select "
            "texrect paths and compare it against runtime hi-res evidence bundles."
        )
    )
    parser.add_argument(
        "--game-root",
        default="/home/auro/code/paper_mario/papermario",
        help="Path to the upstream Paper Mario checkout.",
    )
    parser.add_argument(
        "--bundle",
        action="append",
        default=[],
        help="Runtime evidence bundle to compare against. Can be passed multiple times.",
    )
    parser.add_argument("--output-json")
    parser.add_argument("--output-markdown")
    return parser.parse_args()


def read_lines(path: Path) -> list[str]:
    return path.read_text().splitlines()


def find_line(lines: list[str], needle: str) -> int:
    for idx, line in enumerate(lines, start=1):
        if needle in line:
            return idx
    raise ValueError(f"needle not found: {needle}")


def load_bundle(path: Path) -> dict[str, Any]:
    hires_path = path / "traces" / "hires-evidence.json"
    data = json.loads(hires_path.read_text())
    return {
        "bundle": str(path),
        "sampled_groups": data.get("sampled_object_probe", {}).get("groups", []) or [],
        "sampler_top_buckets": data.get("sampler_usage", {}).get("top_buckets", []) or [],
    }


def sampled_group_index(bundle_data: dict[str, Any]) -> dict[tuple[str, str, str, str], dict[str, Any]]:
    index: dict[tuple[str, str, str, str], dict[str, Any]] = {}
    for row in bundle_data["sampled_groups"]:
        key = (row["draw_class"], row["fmt"], row["siz"], row["wh"])
        index[key] = row
    return index


def sampler_bucket_index(bundle_data: dict[str, Any]) -> dict[tuple[str, str, str, str, str], dict[str, Any]]:
    index: dict[tuple[str, str, str, str, str], dict[str, Any]] = {}
    for row in bundle_data["sampler_top_buckets"]:
        fields = row["fields"]
        if not all(key in fields for key in ("draw_class", "cycle", "fmt", "siz", "texel0_w", "texel0_h")):
            continue
        key = (
            fields["draw_class"],
            fields["cycle"],
            fields["fmt"],
            fields["siz"],
            f"{fields['texel0_w']}x{fields['texel0_h']}",
        )
        index[key] = row
    return index


def static_findings(game_root: Path) -> list[dict[str, Any]]:
    gbi_path = game_root / "include" / "gbi_custom.h"
    filemenu_msg_path = game_root / "src" / "filemenu" / "filemenu_msg.c"
    filemenu_gfx_path = game_root / "src" / "filemenu" / "filemenu_gfx.c"
    title_path = game_root / "src" / "world" / "area_kmr" / "kmr_21" / "main.c"

    gbi_lines = read_lines(gbi_path)
    filemenu_msg_lines = read_lines(filemenu_msg_path)
    filemenu_gfx_lines = read_lines(filemenu_gfx_path)
    title_lines = read_lines(title_path)

    findings: list[dict[str, Any]] = []

    findings.append(
        {
            "id": "filemenu-msg-loadblock-4b-ci4",
            "category": "macro-to-runtime-bridge",
            "confidence": "high",
            "summary": (
                "The dominant `64x1 fs514` file-select miss is structurally explained by "
                "`gDPLoadTextureBlock_4b` in the filemenu message path: a 16x16 CI4 glyph "
                "uploads through `G_IM_SIZ_16b` + `LoadBlock`, then becomes a sampled 16x16 CI4 texrect object."
            ),
            "source_refs": [
                SourceRef(gbi_path, find_line(gbi_lines, "#define\tgDPScrollTextureBlock_4b")).to_json(),
                SourceRef(filemenu_msg_path, find_line(filemenu_msg_lines, "gDPLoadTextureBlock_4b(gMainGfxPos++, &raster[charRasterSize * c], G_IM_FMT_CI,")).to_json(),
                SourceRef(filemenu_msg_path, find_line(filemenu_msg_lines, "filemenu_draw_rect(x * 4, y * 4, (x + texSizeX) * 4, (y + texSizeY) * 4, 0, 0, 0, 0x400, 0x400);")).to_json(),
            ],
            "static_shape": {
                "load_kind": "LoadBlock",
                "upload_fmt": "CI",
                "upload_siz": "16b-for-4b-load",
                "sampled_fmt": "CI",
                "sampled_siz": "4b",
                "sampled_wh_example": "16x16",
                "sampled_stride_bytes_example": 8,
                "upload_words_16_example": 64,
                "raw_upload_shape_example": "64x1",
                "notes": [
                    "The macro explicitly uses `gDPSetTextureImage(... G_IM_SIZ_16b ...)` followed by `gDPLoadBlock`.",
                    "For a 16x16 CI4 glyph, `(((width * height) + 3) >> 2)` becomes `64`, which matches the dominant raw upload width seen in runtime bundles.",
                    "The same macro then rebinds the render tile as 4b CI with line/width derived from the sampled width.",
                ],
            },
            "expected_runtime_signatures": {
                "sampler_bucket": {
                    "draw_class": "texrect",
                    "cycle": "1cycle",
                    "fmt": "2",
                    "siz": "0",
                    "texel0_wh": "64x1",
                },
                "sampled_object": {
                    "draw_class": "texrect",
                    "fmt": "2",
                    "siz": "0",
                    "wh": "16x16",
                },
            },
        }
    )

    findings.append(
        {
            "id": "filemenu-msg-loadtile-4b-ci4",
            "category": "macro-to-runtime-bridge",
            "confidence": "high",
            "summary": (
                "The ambiguous `8x16 fs258` file-select family is structurally consistent with "
                "the `gDPLoadTextureTile_4b` branch in filemenu message rendering: it stays a tiled 4b CI load "
                "instead of collapsing through the `64x1` `LoadBlock` transport shape."
            ),
            "source_refs": [
                SourceRef(filemenu_msg_path, find_line(filemenu_msg_lines, "gDPLoadTextureTile_4b(gMainGfxPos++, &raster[charRasterSize * c], G_IM_FMT_CI,")).to_json(),
                SourceRef(filemenu_msg_path, find_line(filemenu_msg_lines, "filemenu_draw_rect(x * 4, y * 4, (x + texSizeX) * 4, (y + texSizeY) * 4, 0, 0, 0, 0x400, 0x400);")).to_json(),
            ],
            "static_shape": {
                "load_kind": "LoadTile",
                "upload_fmt": "CI",
                "upload_siz": "8b-for-4b-tile-load",
                "sampled_fmt": "CI",
                "sampled_siz": "4b",
                "sampled_wh_example": "8x16",
                "sampled_stride_bytes_example": 8,
                "notes": [
                    "This branch is taken when `texSizeX` is not a 16-aligned block-load candidate.",
                    "It preserves a tiled 4b CI interpretation instead of forcing the `LoadBlock` transport shape.",
                    "That matches the current runtime split between the `64x1 fs514` family and the smaller `8x16 fs258` CI family.",
                ],
            },
            "expected_runtime_signatures": {
                "sampler_bucket": {
                    "draw_class": "texrect",
                    "cycle": "2cycle",
                    "fmt": "2",
                    "siz": "0",
                    "texel0_wh": "8x16",
                }
            },
        }
    )

    findings.append(
        {
            "id": "title-kmr21-rgba32-strips",
            "category": "direct-static-match",
            "confidence": "high",
            "summary": (
                "The title-screen striped texrect path is directly authored in `kmr_21`: "
                "200x2 RGBA32 strips are loaded and drawn one texrect at a time."
            ),
            "source_refs": [
                SourceRef(title_path, find_line(title_lines, "gDPLoadTextureTile(gMainGfxPos++, &TitleImage[1600 * i], G_IM_FMT_RGBA, G_IM_SIZ_32b, 200, 112,")).to_json(),
                SourceRef(title_path, find_line(title_lines, "/* ulx */ 60 * 4,")).to_json(),
            ],
            "static_shape": {
                "load_kind": "LoadTile",
                "upload_fmt": "RGBA",
                "upload_siz": "32b",
                "sampled_fmt": "RGBA",
                "sampled_siz": "32b",
                "sampled_wh_example": "200x2",
                "sampled_stride_hint": 400,
                "notes": [
                    "Each loop iteration loads one 200x2 stripe from the decompressed title image and draws it as a texrect.",
                    "This directly matches the repeated title-screen texrect regime already seen in runtime bundles.",
                ],
            },
            "expected_runtime_signatures": {
                "sampler_bucket": {
                    "draw_class": "texrect",
                    "cycle": "1cycle",
                    "fmt": "0",
                    "siz": "3",
                    "texel0_wh": "200x2",
                }
            },
        }
    )

    findings.append(
        {
            "id": "filemenu-copyarrow-is-not-current-ci4-family",
            "category": "negative-static-match",
            "confidence": "high",
            "summary": (
                "The filemenu copy-arrow display list is a 64x16 IA4 texrect path, so it should not be conflated "
                "with the current CI4 sampled-object families under active investigation."
            ),
            "source_refs": [
                SourceRef(filemenu_gfx_path, find_line(filemenu_gfx_lines, "gsDPLoadTextureTile_4b(D_8024A200, G_IM_FMT_IA, 64, 16, 0, 0, 63, 15, 0, G_TX_NOMIRROR | G_TX_CLAMP, G_TX_MIRROR | G_TX_WRAP, 6, 4, G_TX_NOLOD, G_TX_NOLOD),")).to_json(),
            ],
            "static_shape": {
                "load_kind": "LoadTile",
                "upload_fmt": "IA",
                "upload_siz": "4b",
                "sampled_fmt": "IA",
                "sampled_siz": "4b",
                "sampled_wh_example": "64x16",
                "notes": [
                    "This path is still useful as a texrect/static reference, but its format class is IA, not CI.",
                    "That makes it a good negative control for the current CI/TLUT-focused work.",
                ],
            },
            "expected_runtime_signatures": {
                "sampler_bucket": {
                    "draw_class": "texrect",
                    "cycle": "2cycle",
                    "fmt": "3",
                    "siz": "0",
                    "texel0_wh": "64x16",
                }
            },
        }
    )

    return findings


def compare_against_runtime(findings: list[dict[str, Any]], bundles: list[dict[str, Any]]) -> None:
    for finding in findings:
        finding["runtime_links"] = []
        expected = finding.get("expected_runtime_signatures", {})
        for bundle_data in bundles:
            sampled_idx = sampled_group_index(bundle_data)
            sampler_idx = sampler_bucket_index(bundle_data)
            links = []
            sampler = expected.get("sampler_bucket")
            if sampler:
                sampler_key = (
                    sampler["draw_class"],
                    sampler["cycle"],
                    sampler["fmt"],
                    sampler["siz"],
                    sampler["texel0_wh"],
                )
                bucket = sampler_idx.get(sampler_key)
                if bucket:
                    links.append(
                        {
                            "kind": "sampler_bucket",
                            "signature": bucket["signature"],
                            "count": bucket["count"],
                            "sample_detail": bucket["sample_detail"],
                        }
                    )
            sampled = expected.get("sampled_object")
            if sampled:
                target_wh = sampled["wh"]
                for key, group in sampled_idx.items():
                    draw_class, fmt, siz, wh = key
                    if draw_class != sampled["draw_class"] or fmt != sampled["fmt"] or siz != sampled["siz"]:
                        continue
                    if wh == target_wh:
                        links.append(
                            {
                                "kind": "sampled_group",
                                "signature": (
                                    f"draw_class={group['draw_class']} fmt={group['fmt']} siz={group['siz']} "
                                    f"wh={group['wh']} sampled_low32={group['sampled_low32']}"
                                ),
                                "sample_detail": (
                                    f"upload_low32={group['upload_low32']} sampled_entry_pcrc={group['sampled_entry_pcrc']} "
                                    f"sampled_sparse_pcrc={group['sampled_sparse_pcrc']}"
                                ),
                            }
                        )
            if links:
                finding["runtime_links"].append({"bundle": bundle_data["bundle"], "links": links})


def render_markdown(report: dict[str, Any]) -> str:
    lines = [
        "# Paper Mario Tier 2 Static Scan",
        "",
        f"- Game root: `{report['game_root']}`",
        f"- Runtime bundles compared: `{len(report['runtime_bundles'])}`",
        f"- Findings: `{len(report['findings'])}`",
        "",
    ]
    for finding in report["findings"]:
        lines.extend(
            [
                f"## `{finding['id']}`",
                "",
                f"- Category: `{finding['category']}`",
                f"- Confidence: `{finding['confidence']}`",
                f"- Summary: {finding['summary']}",
                "",
                "### Source Refs",
                "",
            ]
        )
        for ref in finding["source_refs"]:
            lines.append(f"- `{ref['path']}:{ref['line']}`")
        lines.extend(["", "### Static Shape", ""])
        for key, value in finding["static_shape"].items():
            if isinstance(value, list):
                lines.append(f"- {key}:")
                for item in value:
                    lines.append(f"  - {item}")
            else:
                lines.append(f"- {key}: `{value}`")
        if finding.get("runtime_links"):
            lines.extend(["", "### Runtime Links", ""])
            for bundle in finding["runtime_links"]:
                lines.append(f"- Bundle: `{bundle['bundle']}`")
                for link in bundle["links"]:
                    suffix = f", count={link['count']}" if "count" in link else ""
                    lines.append(f"  - `{link['kind']}`: `{link['signature']}`{suffix}")
                    lines.append(f"    - {link['sample_detail']}")
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    game_root = Path(args.game_root)
    bundles = [load_bundle(Path(bundle)) for bundle in args.bundle]
    findings = static_findings(game_root)
    if bundles:
        compare_against_runtime(findings, bundles)
    report = {
        "game_root": str(game_root),
        "runtime_bundles": [bundle["bundle"] for bundle in bundles],
        "findings": findings,
    }
    markdown = render_markdown(report)
    if args.output_json:
        Path(args.output_json).write_text(json.dumps(report, indent=2) + "\n")
    if args.output_markdown:
        Path(args.output_markdown).write_text(markdown + "\n")
    print(markdown)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
