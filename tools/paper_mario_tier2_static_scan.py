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


def compare_native_fields(static_shape: dict[str, Any], sampler_bucket: dict[str, Any]) -> dict[str, Any] | None:
    hints = static_shape.get("native_field_hints")
    if not isinstance(hints, dict):
        return None
    fields = sampler_bucket.get("fields", {})
    comparisons = []

    key_map = {
        "tmem_offset": "offset",
        "render_tile": "base_tile",
    }
    for static_key, runtime_key in key_map.items():
        if static_key in hints and runtime_key in fields:
            comparisons.append(
                {
                    "static_key": static_key,
                    "runtime_key": runtime_key,
                    "static_value": hints[static_key],
                    "runtime_value": int(fields[runtime_key]),
                    "match": hints[static_key] == int(fields[runtime_key]),
                }
            )

    tile_size = hints.get("tile_size_example")
    if isinstance(tile_size, dict):
        for coord_key in ("sl", "tl", "sh", "th"):
            if coord_key in tile_size and coord_key in fields:
                comparisons.append(
                    {
                        "static_key": f"tile_size_example.{coord_key}",
                        "runtime_key": coord_key,
                        "static_value": tile_size[coord_key],
                        "runtime_value": int(fields[coord_key]),
                        "match": tile_size[coord_key] == int(fields[coord_key]),
                    }
                )

    if not comparisons:
        return None
    return {
        "all_match": all(item["match"] for item in comparisons),
        "comparisons": comparisons,
    }


def static_findings(game_root: Path) -> list[dict[str, Any]]:
    gbi_path = game_root / "include" / "gbi_custom.h"
    filemenu_msg_path = game_root / "src" / "filemenu" / "filemenu_msg.c"
    filemenu_gfx_path = game_root / "src" / "filemenu" / "filemenu_gfx.c"
    filemenu_main_path = game_root / "src" / "filemenu" / "filemenu_main.c"
    filemenu_styles_path = game_root / "src" / "filemenu" / "filemenu_styles.c"
    menu_hud_scripts_path = game_root / "src" / "menu_hud_scripts.c"
    draw_img_util_path = game_root / "src" / "draw_img_util.c"
    msg_draw_path = game_root / "src" / "msg_draw.c"
    msg_data_path = game_root / "src" / "msg_data.c"
    title_path = game_root / "src" / "world" / "area_kmr" / "kmr_21" / "main.c"
    state_title_screen_path = game_root / "src" / "state_title_screen.c"

    gbi_lines = read_lines(gbi_path)
    filemenu_msg_lines = read_lines(filemenu_msg_path)
    filemenu_gfx_lines = read_lines(filemenu_gfx_path)
    filemenu_main_lines = read_lines(filemenu_main_path)
    filemenu_styles_lines = read_lines(filemenu_styles_path)
    menu_hud_scripts_lines = read_lines(menu_hud_scripts_path)
    draw_img_util_lines = read_lines(draw_img_util_path)
    msg_draw_lines = read_lines(msg_draw_path)
    msg_data_lines = read_lines(msg_data_path)
    title_lines = read_lines(title_path)
    state_title_screen_lines = read_lines(state_title_screen_path)

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
                "native_field_hints": {
                    "tmem_offset": 0,
                    "render_tile": 0,
                    "render_line_words64_expr": "((((width >> 1) + 7) >> 3))",
                    "render_line_words64_example": 1,
                    "tile_size_expr": "(0, 0) -> ((width - 1) << 2, (height - 1) << 2)",
                    "tile_size_example": {"sl": 0, "tl": 0, "sh": 60, "th": 60},
                    "load_count_expr": "(((width * height) + 3) >> 2) - 1",
                    "load_count_example": 63,
                },
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
            "confidence": "medium",
            "summary": (
                "The smaller active `8x16 fs258` file-select family still looks like a tiled CI4 path, but it is no longer a clean direct match to filemenu menu-font rendering. The broader strict-fixture `8x16` neighborhood is split between a small active `1cycle` bucket and a larger `2cycle` bucket where `texel0` is inactive and the live sample comes from `texel1`, and upstream menu-font data says the canonical filemenu glyph tile size is `16x16`, not `8x16`."
            ),
            "source_refs": [
                SourceRef(filemenu_msg_path, find_line(filemenu_msg_lines, "gDPLoadTextureTile_4b(gMainGfxPos++, &raster[charRasterSize * c], G_IM_FMT_CI,")).to_json(),
                SourceRef(filemenu_msg_path, find_line(filemenu_msg_lines, "filemenu_draw_rect(x * 4, y * 4, (x + texSizeX) * 4, (y + texSizeY) * 4, 0, 0, 0, 0x400, 0x400);")).to_json(),
                SourceRef(msg_data_path, find_line(msg_data_lines, "MessageCharset MsgCharsetMenu = {")).to_json(),
                SourceRef(msg_data_path, find_line(msg_data_lines, ".texSize = { 16, 16 },")).to_json(),
            ],
            "static_shape": {
                "load_kind": "LoadTile",
                "upload_fmt": "CI",
                "upload_siz": "8b-for-4b-tile-load",
                "sampled_fmt": "CI",
                "sampled_siz": "4b",
                "sampled_wh_example": "8x16",
                "sampled_stride_bytes_example": 8,
                "native_field_hints": {
                    "tmem_offset": 0,
                    "render_tile": 0,
                    "render_line_words64_expr": "((((((lrs - uls) + 1) >> 1) + 7) >> 3))",
                    "render_line_words64_example": 1,
                    "tile_size_expr": "((uls << 2), (ult << 2)) -> ((lrs << 2), (lrt << 2))",
                    "tile_size_example": {"sl": 0, "tl": 0, "sh": 28, "th": 60},
                    "load_size_expr": "G_IM_SIZ_8b with width >> 1 source stride",
                },
                "notes": [
                    "The filemenu message branch is still the right tiled-CI4 structural reference, but upstream `MsgCharsetMenu` says its canonical glyph tiles are `16x16`, not `8x16`.",
                    "That means the strict-runtime `8x16` family is unlikely to be a literal menu-font texSize; it is more likely a clipped/subrect transport view or a different tiled-CI4 path.",
                    "On the strict file-select fixture, the active `8x16` evidence is now split: a small `1cycle` bucket still samples texel0 directly, while the larger `2cycle` bucket logs the same texel0 family in an inactive slot next to an active texel1 hit.",
                    "That means the larger `2cycle` `8x16` bucket is a bookkeeping/disambiguation caution, not a clean canonical target on its own.",
                ],
            },
            "expected_runtime_signatures": {
                "sampler_buckets": [
                    {
                        "label": "sampler_bucket_active_texel0",
                        "draw_class": "texrect",
                        "cycle": "1cycle",
                        "fmt": "2",
                        "siz": "0",
                        "texel0_wh": "8x16",
                        "require_used_texel0": "1",
                    },
                    {
                        "label": "sampler_bucket_inactive_texel0",
                        "draw_class": "texrect",
                        "cycle": "2cycle",
                        "fmt": "2",
                        "siz": "0",
                        "texel0_wh": "8x16",
                        "require_used_texel0": "0",
                    },
                ]
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
                "native_field_hints": {
                    "tmem_offset": 0,
                    "render_tile": 0,
                    "load_rect_example": {"uls": 0, "ult": 0, "lrs": 199, "lrt": 1},
                    "tile_size_example": {"sl": 0, "tl": 0, "sh": 796, "th": 4},
                    "rect_step_example": {"dsdx": 1024, "dtdy": 1024},
                    "screen_rect_example": {"ulx": 240, "lrx": 1040},
                },
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
            "id": "title-screen-press-start-ia8-block",
            "category": "probable-static-match",
            "confidence": "high",
            "summary": (
                "The unresolved `128x32` IA8 title seam is now strongly source-backed too: "
                "the non-PAL `Press Start` path in `state_title_screen` loads a `128x32` IA8 "
                "texture through `gDPLoadTextureBlock`, which matches the runtime `128x32` "
                "sampled pair and the observed `sh=508`, `th=124` tile fields."
            ),
            "source_refs": [
                SourceRef(state_title_screen_path, find_line(state_title_screen_lines, "#define VAR_1 32")).to_json(),
                SourceRef(state_title_screen_path, find_line(state_title_screen_lines, "gDPLoadTextureBlock(gMainGfxPos++, TitleScreen_ImgList_PressStart, G_IM_FMT_IA, G_IM_SIZ_8b, 128, VAR_1, 0,")).to_json(),
                SourceRef(state_title_screen_path, find_line(state_title_screen_lines, "gSPTextureRectangle(gMainGfxPos++, 384, 548, 896, VAR_2, G_TX_RENDERTILE, 0, 0, 0x0400, 0x0400);")).to_json(),
            ],
            "static_shape": {
                "load_kind": "LoadBlock",
                "upload_fmt": "IA",
                "upload_siz": "8b",
                "source_chunk_dims": "128x32",
                "sampled_runtime_wh_candidates": ["128x32", "128x32"],
                "raw_upload_shape_hint": "2048x1",
                "native_field_hints": {
                    "tmem_offset": 0,
                    "render_tile": 0,
                    "tile_size_example": {"sl": 0, "tl": 0, "sh": 508, "th": 124},
                    "screen_rect_example": {"ulx": 384, "uly": 548, "lrx": 896, "lry": 676},
                },
                "notes": [
                    "The upstream non-PAL title menu uses `VAR_1 = 32`, so the `Press Start` texture is a direct `128x32 IA8` loadblock path.",
                    "Runtime exposes two unresolved `128x32 IA8` sampled objects, `049201f4` and `ce437230`, from one shared `2048x1` upload family `dfe97266`.",
                    "Unlike the copyright path, the recovered native tile fields already match exactly here, so the open problem is transport/import coverage rather than source attribution.",
                ],
            },
            "expected_runtime_signatures": {
                "sampler_bucket": {
                    "draw_class": "texrect",
                    "cycle": "1cycle",
                    "fmt": "3",
                    "siz": "1",
                    "texel0_wh": "2048x1",
                },
                "sampled_objects": [
                    {
                        "draw_class": "texrect",
                        "fmt": "3",
                        "siz": "1",
                        "wh": "128x32",
                    }
                ],
            },
        }
    )

    findings.append(
        {
            "id": "title-screen-copyright-ia8-chunks",
            "category": "probable-static-match",
            "confidence": "medium",
            "summary": (
                "The provisional `144x16` title-strip pair is now strongly source-backed: "
                "the non-JP copyright path in `state_title_screen` draws exactly two IA8 "
                "copyright chunks at `144x16`, and runtime exposes the same two `144x16` IA8 "
                "sampled objects as the current merge-safe lower-strip pair."
            ),
            "source_refs": [
                SourceRef(state_title_screen_path, find_line(state_title_screen_lines, "#define COPYRIGHT_WIDTH 144")).to_json(),
                SourceRef(state_title_screen_path, find_line(state_title_screen_lines, "#define COPYRIGHT_TEX_CHUNKS 2")).to_json(),
                SourceRef(state_title_screen_path, find_line(state_title_screen_lines, "#define LTT_LRT 15")).to_json(),
                SourceRef(state_title_screen_path, find_line(state_title_screen_lines, "gDPLoadTextureTile(gMainGfxPos++, COPYRIGHT_IMG(k, i), G_IM_FMT_IA, G_IM_SIZ_8b,")).to_json(),
                SourceRef(state_title_screen_path, find_line(state_title_screen_lines, "gSPTextureRectangle(gMainGfxPos++, 356, YL_BASE + (RECT_SIZE * i), 932, YH_BASE + (RECT_SIZE * i),")).to_json(),
            ],
            "static_shape": {
                "load_kind": "LoadTile",
                "upload_fmt": "IA",
                "upload_siz": "8b",
                "source_chunk_dims": "144x16",
                "source_chunk_count": 2,
                "sampled_runtime_wh_candidates": ["144x16", "144x16"],
                "native_field_hints": {
                    "tmem_offset": 0,
                    "render_tile": 0,
                    "tile_size_example": {"sl": 0, "tl": 0, "sh": 572, "th": 60},
                    "screen_rect_example": {"ulx": 356, "uly": 764, "lrx": 932, "lry": 828},
                },
                "notes": [
                    "The upstream non-JP path explicitly loops `COPYRIGHT_TEX_CHUNKS = 2`.",
                    "Each chunk is loaded as IA8 with `COPYRIGHT_WIDTH = 144` and `LTT_LRT = 15`, i.e. a 144x16 tile.",
                    "Runtime already exposes two matching 144x16 IA8 sampled objects, `0e89915a` and `1d234571`, which are the current provisional lower-strip pair.",
                    "The separate unresolved `128x32` IA8 seam from upload family `dfe97266` does not match this direct copyright tile shape and remains a distinct open problem.",
                ],
            },
            "expected_runtime_signatures": {
                "sampler_bucket": {
                    "draw_class": "texrect",
                    "cycle": "1cycle",
                    "fmt": "3",
                    "siz": "1",
                    "texel0_wh": "144x16",
                },
                "sampled_objects": [
                    {
                        "draw_class": "texrect",
                        "fmt": "3",
                        "siz": "1",
                        "wh": "144x16",
                    }
                ],
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
                "native_field_hints": {
                    "tmem_offset": 0,
                    "render_tile": 0,
                    "mask_s": 6,
                    "mask_t": 4,
                    "mirror_s": 0,
                    "mirror_t": 1,
                },
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

    findings.append(
        {
            "id": "filemenu-main-hud-assets-do-not-fit-active-8x16-gap",
            "category": "negative-static-match",
            "confidence": "medium",
            "summary": (
                "The active strict file-select main-menu HUD scripts are real CI assets, but the upstream sizes in use "
                "are `16x16`, `32x16`, and `64x16`, not the unresolved active `8x16` strict-runtime bucket. That makes "
                "them useful controls, not a clean direct explanation for the current CI4 gap."
            ),
            "source_refs": [
                SourceRef(filemenu_main_path, find_line(filemenu_main_lines, "HudScript* filemenu_main_hudScripts[][20] = {")).to_json(),
                SourceRef(menu_hud_scripts_path, find_line(menu_hud_scripts_lines, "HudScript HES_JpFile = HES_TEMPLATE_CI_CUSTOM_SIZE(ui_pause_label_jp_file, 32, 16);")).to_json(),
                SourceRef(menu_hud_scripts_path, find_line(menu_hud_scripts_lines, "HudScript HES_OptionMonoOn = HES_TEMPLATE_CI_CUSTOM_SIZE(ui_files_option_mono_on, 64, 16);")).to_json(),
                SourceRef(menu_hud_scripts_path, find_line(menu_hud_scripts_lines, "HudScript HES_Spirit1 = HES_TEMPLATE_CI_CUSTOM_SIZE(ui_files_eldstar, 16, 16);")).to_json(),
            ],
            "static_shape": {
                "active_main_menu_hud_sizes": ["16x16", "32x16", "64x16"],
                "notes": [
                    "The strict file-select authority uses `filemenu_main_hudScripts`, so these are the HUD assets that matter first for the main menu path.",
                    "Their upstream sizes align with other verified runtime families such as `16x16` and `32x16`, but they do not supply a direct `8x16` active-main-menu match.",
                    "This does not prove HUD elements are irrelevant globally; it narrows the current strict-main-menu `8x16` search away from the obvious HUD script set.",
                ],
            },
        }
    )

    findings.append(
        {
            "id": "filemenu-window-styles-are-ia-rgba-controls",
            "category": "negative-static-match",
            "confidence": "high",
            "summary": (
                "The active filemenu window-style corner assets explain some repeated texrect controls, especially `16x8` "
                "shapes, but the relevant upstream assets are IA8 or RGBA32 rather than CI4. They should be treated as "
                "format-class controls, not folded into the active CI/TLUT family under investigation."
            ),
            "source_refs": [
                SourceRef(filemenu_main_path, find_line(filemenu_main_lines, ".style = { .customStyle = &filemenu_windowStyles[4] }")).to_json(),
                SourceRef(filemenu_styles_path, find_line(filemenu_styles_lines, ".imgData = D_8024B400,")).to_json(),
                SourceRef(filemenu_styles_path, find_line(filemenu_styles_lines, ".size1 = { .x = 16, .y = 8},")).to_json(),
                SourceRef(filemenu_styles_path, find_line(filemenu_styles_lines, ".imgData = D_8024A400,")).to_json(),
                SourceRef(filemenu_styles_path, find_line(filemenu_styles_lines, ".bitDepth = G_IM_SIZ_32b,")).to_json(),
            ],
            "static_shape": {
                "window_corner_formats": ["IA8 16x8", "RGBA32 16x16"],
                "notes": [
                    "These styles are active on the file-select windows and explain why repeated `16x8` texrect controls appear in the broader evidence set.",
                    "Because the active corner assets are IA or RGBA, they are the wrong format class for the unresolved strict CI4 `8x16` family.",
                    "This is a guardrail against mixing window-style texrect evidence back into the CI/TLUT identity problem.",
                ],
            },
        }
    )

    findings.append(
        {
            "id": "clipped-ci-image-helper-is-not-a-filemenu-main-caller",
            "category": "negative-static-match",
            "confidence": "medium",
            "summary": (
                "The upstream clipped-image helper is still an important subrect-transport reference, but the current static "
                "scan only finds it in the message-system and document-style paths, not as an obvious strict file-select main-menu caller."
            ),
            "source_refs": [
                SourceRef(draw_img_util_path, find_line(draw_img_util_lines, "s32 draw_ci_image_with_clipping(IMG_PTR raster, s32 width, s32 height, s32 fmt, s32 bitDepth, PAL_PTR palette, s16 posX,")).to_json(),
                SourceRef(draw_img_util_path, find_line(draw_img_util_lines, "gDPLoadTextureTile_4b(gMainGfxPos++, raster, fmt, width, height,")).to_json(),
                SourceRef(msg_draw_path, find_line(msg_draw_lines, "draw_ci_image_with_clipping(ui_msg_sign_corner_topleft_png, 16, 16, G_IM_FMT_CI, G_IM_SIZ_4b, signPalette, 20 + MSG_SIGN_OFFSET_X,")).to_json(),
                SourceRef(msg_draw_path, find_line(msg_draw_lines, "draw_ci_image_with_clipping(printer->letterBackgroundImg, 150, 105, G_IM_FMT_CI, G_IM_SIZ_4b,")).to_json(),
            ],
            "static_shape": {
                "helper_chunking": ["64x32 tile chunks", "partial last-chunk clipping"],
                "notes": [
                    "This helper is still the best upstream reference for how a larger logical CI image can travel through smaller upload rectangles.",
                    "In the current upstream scan, its visible callers are message/sign/letter-style paths rather than the strict file-select main-menu path.",
                    "That makes it a good model for subrect transport, but not yet a source-backed explanation for the active strict `8x16` file-select gap.",
                ],
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
            sampler_specs = []
            if expected.get("sampler_bucket"):
                sampler_specs.append(expected["sampler_bucket"])
            sampler_specs.extend(expected.get("sampler_buckets", []))
            for sampler in sampler_specs:
                sampler_key = (
                    sampler["draw_class"],
                    sampler["cycle"],
                    sampler["fmt"],
                    sampler["siz"],
                    sampler["texel0_wh"],
                )
                bucket = sampler_idx.get(sampler_key)
                if not bucket:
                    continue
                sample_detail = bucket["sample_detail"]
                uses_texel0 = None
                if "uses_texel0=" in sample_detail:
                    uses_texel0 = sample_detail.split("uses_texel0=", 1)[1].split()[0]
                if "require_used_texel0" in sampler and uses_texel0 is not None and uses_texel0 != sampler["require_used_texel0"]:
                    continue
                link = {
                    "kind": sampler.get("label", "sampler_bucket"),
                    "signature": bucket["signature"],
                    "count": bucket["count"],
                    "sample_detail": sample_detail,
                }
                if uses_texel0 is not None:
                    link["uses_texel0"] = uses_texel0
                field_comparison = compare_native_fields(finding.get("static_shape", {}), bucket)
                if field_comparison is not None:
                    link["field_comparison"] = field_comparison
                links.append(link)
            sampled_specs = []
            if expected.get("sampled_object"):
                sampled_specs.append(expected["sampled_object"])
            sampled_specs.extend(expected.get("sampled_objects", []))
            for sampled in sampled_specs:
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
            elif isinstance(value, dict):
                lines.append(f"- {key}:")
                for sub_key, sub_value in value.items():
                    lines.append(f"  - {sub_key}: `{sub_value}`")
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
                    field_comparison = link.get("field_comparison")
                    if field_comparison is not None:
                        verdict = "match" if field_comparison["all_match"] else "mismatch"
                        lines.append(f"    - native-field comparison: `{verdict}`")
                        for item in field_comparison["comparisons"]:
                            state = "ok" if item["match"] else "diff"
                            lines.append(
                                f"      - `{item['static_key']}` -> `{item['runtime_key']}`: "
                                f"static=`{item['static_value']}` runtime=`{item['runtime_value']}` ({state})"
                            )
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
