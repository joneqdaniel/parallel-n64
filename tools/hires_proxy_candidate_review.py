#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from dataclasses import dataclass
from itertools import combinations
from pathlib import Path
from typing import Any

from PIL import Image

from hires_pack_common import decode_entry_rgba8, find_cache_entry, parse_cache_entries


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Review sampled-proxy transport candidates by combining runtime bundle "
            "metrics, semantic state, and transported asset similarity."
        )
    )
    parser.add_argument("--baseline-bundle", required=True, help="Baseline runtime bundle.")
    parser.add_argument(
        "--candidate-bundle",
        action="append",
        default=[],
        help="Candidate runtime bundle. Can be passed multiple times.",
    )
    parser.add_argument(
        "--preview-root",
        required=True,
        help="Preview root containing per-candidate loader-manifest.json files.",
    )
    parser.add_argument("--output-json", help="Optional JSON output path.")
    parser.add_argument("--output-markdown", help="Optional markdown output path.")
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def first_capture_png(bundle_path: Path) -> Path:
    captures = sorted((bundle_path / "captures").glob("*.png"))
    if not captures:
        raise SystemExit(f"No capture found in {bundle_path}")
    return captures[0]


def image_rgba(path: Path) -> tuple[Image.Image, bytes]:
    image = Image.open(path).convert("RGBA")
    rgba = image.tobytes()
    return image, rgba


def compare_rgba(a: bytes, b: bytes) -> dict[str, Any]:
    if len(a) != len(b):
        raise SystemExit("Image byte sizes differ; cannot compare.")
    diff_sum = 0
    diff_sq_sum = 0
    for lhs, rhs in zip(a, b):
        delta = abs(lhs - rhs)
        diff_sum += delta
        diff_sq_sum += delta * delta
    count = len(a)
    rmse = math.sqrt(diff_sq_sum / count) if count else 0.0
    normalized_rmse = rmse / 255.0 if count else 0.0
    return {
        "ae": diff_sum,
        "rmse": rmse,
        "normalized_rmse": normalized_rmse,
    }


def bundle_key(bundle_path: Path) -> str:
    match = re.search(r"20260328-469bad6f-([0-9a-f]{8}__\d+x\d+)$", bundle_path.name)
    if match:
        return match.group(1)
    return bundle_path.name


def alpha_normalized_rgba(rgba: bytes) -> bytes:
    normalized = bytearray(rgba)
    for i in range(0, len(normalized), 4):
        normalized[i + 3] = 255
    return bytes(normalized)


def extract_asset(source_path: Path, checksum64: int, formatsize: int) -> tuple[bytes, int, int]:
    entries = parse_cache_entries(source_path)
    entry = find_cache_entry(entries, checksum64, formatsize)
    if entry is None:
        raise SystemExit(f"Asset not found in {source_path}: checksum={checksum64:016x} fs={formatsize}")
    payload = decode_entry_rgba8(source_path, entry)
    return payload, int(entry["width"]), int(entry["height"])


@dataclass
class BundleReview:
    label: str
    bundle_path: Path
    capture_path: Path
    screenshot_hash: str
    callbacks: tuple[str, str]
    sampled_exact_hit_count: int
    sampled_exact_hit_buckets: list[dict[str, Any]]
    transport_asset: dict[str, Any] | None
    asset_rgba_hash: str | None
    asset_alpha_rgba_hash: str | None
    image_rgba: bytes


def extract_transport_asset(preview_root: Path, label: str) -> tuple[dict[str, Any] | None, str | None, str | None]:
    preview_dir = preview_root / label
    manifest_path = preview_dir / "loader-manifest.json"
    if not manifest_path.exists():
        return None, None, None
    manifest = load_json(manifest_path)
    for record in manifest.get("records", []):
        if record.get("sampled_object_id") != "sampled-fmt2-siz0-off0-stride8-wh16x16-fs2-low327064585c":
            continue
        candidates = record.get("asset_candidates", [])
        if len(candidates) != 1:
            return None, None, None
        candidate = dict(candidates[0])
        rgba, width, height = extract_asset(
            Path(candidate["legacy_source_path"]),
            int(candidate["legacy_checksum64"], 16),
            int(candidate["legacy_formatsize"]),
        )
        candidate["width"] = width
        candidate["height"] = height
        rgba_hash = hashlib.sha256(rgba).hexdigest()
        alpha_hash = hashlib.sha256(alpha_normalized_rgba(rgba)).hexdigest()
        return candidate, rgba_hash, alpha_hash
    return None, None, None


def load_bundle_review(bundle_path: Path, preview_root: Path) -> BundleReview:
    capture_path = first_capture_png(bundle_path)
    _, rgba = image_rgba(capture_path)
    game_status = load_json(bundle_path / "traces" / "paper-mario-game-status.json")
    hires = load_json(bundle_path / "traces" / "hires-evidence.json")
    sampled = hires.get("sampled_object_probe", {})
    label = bundle_key(bundle_path)
    transport_asset, rgba_hash, alpha_hash = extract_transport_asset(preview_root, label)
    return BundleReview(
        label=label,
        bundle_path=bundle_path,
        capture_path=capture_path,
        screenshot_hash=hashlib.sha256(rgba).hexdigest(),
        callbacks=(
            game_status.get("curGameMode", {}).get("initCallbackName") or "unknown",
            game_status.get("curGameMode", {}).get("stepCallbackName") or "unknown",
        ),
        sampled_exact_hit_count=int(sampled.get("exact_hit_count") or 0),
        sampled_exact_hit_buckets=sampled.get("top_exact_hit_buckets", []) or [],
        transport_asset=transport_asset,
        asset_rgba_hash=rgba_hash,
        asset_alpha_rgba_hash=alpha_hash,
        image_rgba=rgba,
    )


def summarize_pairwise(items: list[BundleReview]) -> list[dict[str, Any]]:
    rows = []
    for lhs, rhs in combinations(items, 2):
        rows.append(
            {
                "lhs": lhs.label,
                "rhs": rhs.label,
                "image": compare_rgba(lhs.image_rgba, rhs.image_rgba),
                "same_hash": lhs.screenshot_hash == rhs.screenshot_hash,
                "same_asset_alpha_hash": lhs.asset_alpha_rgba_hash is not None
                and lhs.asset_alpha_rgba_hash == rhs.asset_alpha_rgba_hash,
            }
        )
    return rows


def build_report(baseline: BundleReview, candidates: list[BundleReview]) -> dict[str, Any]:
    report_candidates = []
    for candidate in candidates:
        report_candidates.append(
            {
                "label": candidate.label,
                "bundle_path": str(candidate.bundle_path),
                "capture_path": str(candidate.capture_path),
                "screenshot_hash": candidate.screenshot_hash,
                "callbacks": {
                    "init": candidate.callbacks[0],
                    "step": candidate.callbacks[1],
                },
                "sampled_exact_hit_count": candidate.sampled_exact_hit_count,
                "sampled_exact_hit_buckets": candidate.sampled_exact_hit_buckets,
                "vs_baseline": compare_rgba(candidate.image_rgba, baseline.image_rgba),
                "transport_asset": candidate.transport_asset,
                "asset_rgba_hash": candidate.asset_rgba_hash,
                "asset_alpha_rgba_hash": candidate.asset_alpha_rgba_hash,
            }
        )
    return {
        "baseline": {
            "label": baseline.label,
            "bundle_path": str(baseline.bundle_path),
            "capture_path": str(baseline.capture_path),
            "screenshot_hash": baseline.screenshot_hash,
            "callbacks": {
                "init": baseline.callbacks[0],
                "step": baseline.callbacks[1],
            },
            "sampled_exact_hit_count": baseline.sampled_exact_hit_count,
            "sampled_exact_hit_buckets": baseline.sampled_exact_hit_buckets,
        },
        "candidate_count": len(report_candidates),
        "candidates": sorted(
            report_candidates,
            key=lambda row: (
                row["vs_baseline"]["normalized_rmse"],
                row["vs_baseline"]["ae"],
                row["label"],
            ),
        ),
        "pairwise_candidate_comparisons": summarize_pairwise(candidates),
    }


def render_markdown(report: dict[str, Any]) -> str:
    lines = []
    baseline = report["baseline"]
    lines.append("# Hi-Res Proxy Candidate Review")
    lines.append("")
    lines.append(f"- Baseline bundle: `{baseline['bundle_path']}`")
    lines.append(f"- Baseline hash: `{baseline['screenshot_hash']}`")
    lines.append(
        f"- Baseline callbacks: `{baseline['callbacks']['init']}` / `{baseline['callbacks']['step']}`"
    )
    lines.append(f"- Candidate count: `{report['candidate_count']}`")
    lines.append("")
    lines.append("## Candidates")
    lines.append("")
    for row in report["candidates"]:
        metric = row["vs_baseline"]
        lines.append(f"- `{row['label']}`")
        lines.append(f"  - bundle: `{row['bundle_path']}`")
        lines.append(f"  - screenshot_hash: `{row['screenshot_hash']}`")
        lines.append(
            f"  - callbacks: `{row['callbacks']['init']}` / `{row['callbacks']['step']}`"
        )
        lines.append(f"  - sampled_exact_hit_count: `{row['sampled_exact_hit_count']}`")
        lines.append(
            f"  - vs_baseline: `AE={metric['ae']}` `RMSE={metric['rmse']:.6f}` `normalized={metric['normalized_rmse']:.7f}`"
        )
        asset = row.get("transport_asset")
        if asset:
            lines.append(
                f"  - asset: `{asset['replacement_id']}` dims=`{asset['width']}x{asset['height']}` palette=`{asset['legacy_palette_crc']}`"
            )
            lines.append(
                f"  - asset_hashes: `rgba={row['asset_rgba_hash']}` `alpha_normalized={row['asset_alpha_rgba_hash']}`"
            )
        top_buckets = row.get("sampled_exact_hit_buckets") or []
        if top_buckets:
            for bucket in top_buckets[:4]:
                lines.append(
                    "  - exact-hit bucket: "
                    f"`{bucket.get('signature')}` count=`{bucket.get('count')}`"
                )
    lines.append("")
    lines.append("## Pairwise Candidate Comparisons")
    lines.append("")
    for row in sorted(
        report["pairwise_candidate_comparisons"],
        key=lambda item: (
            item["image"]["normalized_rmse"],
            item["image"]["ae"],
            item["lhs"],
            item["rhs"],
        ),
    ):
        metric = row["image"]
        lines.append(
            f"- `{row['lhs']}` vs `{row['rhs']}`: `AE={metric['ae']}` `RMSE={metric['rmse']:.6f}` `normalized={metric['normalized_rmse']:.7f}`"
        )
        lines.append(
            f"  - same_screenshot_hash: `{int(bool(row['same_hash']))}` same_asset_alpha_hash: `{int(bool(row['same_asset_alpha_hash']))}`"
        )
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    preview_root = Path(args.preview_root)
    baseline = load_bundle_review(Path(args.baseline_bundle), preview_root)
    candidates = [load_bundle_review(Path(path), preview_root) for path in args.candidate_bundle]
    report = build_report(baseline, candidates)

    if args.output_json:
        Path(args.output_json).write_text(json.dumps(report, indent=2) + "\n")
    markdown = render_markdown(report)
    if args.output_markdown:
        Path(args.output_markdown).write_text(markdown + "\n")
    else:
        sys.stdout.write(markdown + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
