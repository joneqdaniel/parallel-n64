#!/usr/bin/env python3
import argparse
import json
import sys
from collections import Counter
from pathlib import Path

from hires_pack_common import build_family_summary, parse_bundle_families, parse_cache_entries


def build_migration_plan(entries, requested_pairs):
    families = [build_family_summary(entries, texture_crc, formatsize) for texture_crc, formatsize in requested_pairs]
    tier_counts = Counter(family["recommended_tier"] for family in families)

    plan = {
        "family_count": len(families),
        "tier_counts": dict(tier_counts),
        "families": families,
        "migration_guidance": {
            "exact-authoritative": "Preserve as exact identity in the imported index.",
            "compat-unique": "Safe candidate for an explicit compatibility alias in the imported index.",
            "compat-repl-dims-unique": "Candidate for constrained compatibility import if dimensions and fixture evidence stay stable.",
            "ambiguous-import-or-policy": "Do not auto-promote into runtime fallback. Require imported disambiguation or explicit policy fields.",
            "missing-active-pool": "No active exact/generic family available for requested formatsize.",
        },
    }
    return plan


def main():
    parser = argparse.ArgumentParser(description="Build a migration-oriented plan from a legacy hi-res pack.")
    parser.add_argument("--cache", required=True, help="Path to .hts or .htc pack.")
    parser.add_argument("--bundle", help="Optional strict bundle path; imports low32/fs pairs from ci_palette_probe.families.")
    parser.add_argument("--low32", action="append", default=[], help="Low32 texture CRC in hex.")
    parser.add_argument("--formatsize", action="append", type=int, default=[], help="Formatsize values paired with --low32 in order.")
    parser.add_argument("--output", help="Optional output JSON path.")
    args = parser.parse_args()

    cache_path = Path(args.cache)
    entries = parse_cache_entries(cache_path)

    requested_pairs = []
    if args.bundle:
        requested_pairs.extend(parse_bundle_families(Path(args.bundle)))

    if args.low32:
        formatsizes = args.formatsize or []
        if formatsizes and len(formatsizes) != len(args.low32):
            raise SystemExit("--formatsize must either be omitted or match the number of --low32 arguments.")
        for index, low32 in enumerate(args.low32):
            formatsize = formatsizes[index] if formatsizes else 0
            requested_pairs.append((int(low32, 16), formatsize))

    if not requested_pairs:
        raise SystemExit("No families requested. Use --bundle and/or --low32.")

    deduped_pairs = []
    seen = set()
    for pair in requested_pairs:
        if pair in seen:
            continue
        seen.add(pair)
        deduped_pairs.append(pair)

    plan = {
        "cache_path": str(cache_path),
        "entry_count": len(entries),
        "requested_family_count": len(deduped_pairs),
        "plan": build_migration_plan(entries, deduped_pairs),
    }

    serialized = json.dumps(plan, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(serialized)
    else:
        sys.stdout.write(serialized)


if __name__ == "__main__":
    main()
