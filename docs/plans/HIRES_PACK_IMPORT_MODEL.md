# Hi-Res Pack Import Model

## Why This Exists

- The current inherited Glide-era pack format appears to collapse multiple semantic variants into the same runtime family
- Some CI families are suitable for constrained compatibility handling
- Other CI families are fundamentally ambiguous under the legacy format and should not be promoted into permissive runtime fallback

## Core Rule

- Legacy pack format is an input format
- Internal imported format is the authoritative working format for future ParaLLEl hi-res work

## Import Goals

- Preserve exact replacement identity separately from compatibility aliases
- Make ambiguous legacy families explicit during import instead of hiding them at runtime
- Keep runtime lookup simple, diagnosable, and conservative
- Allow migration from old packs without forcing artists to rebuild everything by hand

## Proposed Imported Record Shape

- `replacement_id`
  - stable imported identifier
- `source`
  - legacy checksum64
  - source pack path
  - source storage type
- `match`
  - exact texture identity fields
  - exact palette identity fields
  - formatsize / texture class
  - optional scene or policy qualifiers if needed later
- `compatibility`
  - zero or more explicit alias records
  - each alias must declare why it exists
  - examples:
    - `repl_dims_unique`
    - `legacy_low32_family`
    - future constrained CI policy tags
- `replacement_asset`
  - decoded dimensions
  - asset path or blob reference
  - color space / mip metadata
- `diagnostics`
  - import warnings
  - ambiguity class
  - family statistics from the legacy source

## Import Classification Tiers

- `exact-authoritative`
  - keep as exact imported identity
- `compat-unique`
  - exact source is weak, but compatibility alias is likely safe
- `compat-repl-dims-unique`
  - candidate for constrained compatibility alias
- `ambiguous-import-or-policy`
  - do not auto-promote into runtime compatibility
  - require explicit imported disambiguation or manual policy
- `missing-active-pool`
  - no usable active family in the legacy pack for the requested formatsize

## Runtime Policy Direction

- Runtime exact lookup stays authoritative
- Compatibility lookup is explicit and tiered
- Runtime should never infer broad Glide-style ambiguity on the fly if import can make it explicit earlier

## Migration Utility Requirements

- Read legacy `.hts` / `.htc`
- Classify low32 families and exact/generic pools
- Emit a machine-readable migration plan
- Support importing a full pack into a cleaner internal index later
- Preserve enough provenance that imported records can be traced back to legacy checksums and assets

## Current Utility Scaffolding

- [`tools/hires_pack_family_report.py`](/home/auro/code/parallel-n64/tools/hires_pack_family_report.py)
  - family-level report for selected low32/fs pairs
- [`tools/hires_pack_migrate.py`](/home/auro/code/parallel-n64/tools/hires_pack_migrate.py)
  - migration-oriented tier summary for selected families
  - now also emits the first imported-index scaffold with:
    - `records`
    - `compatibility_aliases`
    - `unresolved_families`
    - explicit `variant_groups` inside compatibility and unresolved family output
- [`tools/hires_pack_import_policy.json`](/home/auro/code/parallel-n64/tools/hires_pack_import_policy.json)
  - first explicit import-policy layer for legacy family decisions and review-required suggestions
- [`tools/hires_pack_review.py`](/home/auro/code/parallel-n64/tools/hires_pack_review.py)
  - emits a review artifact for a bundle-backed import slice so we can inspect selector state, variant groups, and applied policy without treating the imported index as final format
- [`tools/hires_pack_emit_subset.py`](/home/auro/code/parallel-n64/tools/hires_pack_emit_subset.py)
  - emits a tiny imported subset for selected family policy keys so we can inspect a concrete ParaLLEl-owned slice without committing to the full format
- [`tools/hires_pack_compare_subsets.py`](/home/auro/code/parallel-n64/tools/hires_pack_compare_subsets.py)
  - compares multiple review-only subset artifacts so candidate imported-family choices can be summarized side by side

## Imported Index v1

- `schema_version`
- `source`
  - legacy cache path
  - legacy entry count
- `policy_source`
  - optional attached policy path and schema version
- `records`
  - one imported record per active legacy entry in the selected family set
  - preserves legacy checksum provenance and decoded asset metadata
- `compatibility_aliases`
  - explicit aliases for constrained compatibility tiers only
  - currently intended for `compat-unique` and `compat-repl-dims-unique`
  - now also carries:
    - `observed_runtime_context`
    - `selector_policy`
    - `policy_key`
    - `candidate_variant_group_ids`
    - `diagnostics.variant_groups`
- `unresolved_families`
  - explicit ambiguous legacy families that should not become runtime fallback automatically
  - now grouped into explicit dimension-led `variant_groups` so import-time policy can reason about concrete ambiguous clusters instead of a flat legacy family
  - now also carries `observed_runtime_context` from the strict bundle that surfaced the family
  - now also carries `selector_policy`, even when that policy is only “manual disambiguation required”
  - now also carries `policy_key`

## Variant Groups

- `variant_group_id`
  - stable imported grouping key for one low32/requested-formatsize/dimension cluster
- `dims`
  - replacement width and height for the group
- `requested_formatsize`
  - the runtime formatsize that selected this legacy family
- `active_pool`
  - whether the group came from an exact or generic legacy pool
- `candidate_replacement_ids`
  - imported records belonging to the group
- `legacy_palette_crcs`
  - source legacy palette CRCs represented inside the group

The point of `variant_groups` is to make ambiguous Glide-era families importable without pretending they are already resolved. A family like the strict file-select `42779bdd/fs258` case now lands as three explicit variant groups (`64x64`, `120x120`, `144x144`) instead of a single opaque unresolved blob.

## Observed Runtime Context

- `mode`
  - current runtime load mode that produced the family in the strict bundle
- `runtime_address`
  - observed TMEM/RDRAM-side address for the tracked upload
- `runtime_wh`
  - observed runtime texture dimensions before replacement
- `requested_formatsize`
  - runtime formatsize that selected the family
- `observed_runtime_pcrc`
  - current exact palette CRC seen by the runtime path
- `usage`
  - bundle-backed sparse palette usage data:
    - used count
    - used min/max
    - used-mask CRC
    - sparse palette CRC
- `emulated_tmem`
  - bundle-backed TLUT/TMEM-derived palette view for the same runtime event

The point of `observed_runtime_context` is not to turn runtime guesses back on. It is to give import-time policy and future tooling a concrete record of the exact strict-fixture event that exposed the ambiguous family.

## Selector Policy

- `status`
  - `deterministic` when import can select one variant group safely
  - `manual-disambiguation-required` when the family still needs an explicit import decision
- `selector_basis`
  - stable runtime-facing fields import can key from:
    - `texture_crc`
    - `requested_formatsize`
    - current runtime `mode`
    - current runtime `wh`
- `candidate_variant_group_ids`
  - the concrete variant groups eligible under that selector basis
- `disambiguation_inputs`
  - additional recorded fields available to a future importer or manual policy step
- `selected_variant_group_id`
  - present only when the selector policy is deterministic
- `selection_reason`
  - explains why the current selector is deterministic or why it remains unresolved
- `applied_policy`
  - optional policy file entry attached by `--policy`

The current strict file-select result shows both cases:
- `2a1be0a4/fs258` now has a deterministic selector policy that lands on `legacy-low32-2a1be0a4-fs258-640x160`
- `42779bdd/fs258` now has a manual selector policy with three candidate variant groups and explicit disambiguation inputs instead of a flat ambiguous blob

## Policy Layer

- Use [`tools/hires_pack_import_policy.json`](/home/auro/code/parallel-n64/tools/hires_pack_import_policy.json) to record explicit import decisions or non-binding suggestions.
- Pass it with `--policy` when emitting an imported index.
- The policy file can also carry explicit reasoning notes, including why a suggested candidate currently looks stronger and why other variant groups are weaker.
- The policy file can also carry explicit overturn conditions, so a non-binding suggestion states what new evidence would cause us to change it.
- Current examples:
  - `legacy-low32-2a1be0a4-fs258`
    - explicit selected variant group: `legacy-low32-2a1be0a4-fs258-640x160`
  - `legacy-low32-42779bdd-fs258`
    - manual-review-required
    - suggested variant group: `legacy-low32-42779bdd-fs258-120x120`
    - suggestion is intentionally non-binding until validated

## Review Artifact

- Use [`tools/hires_pack_review.py`](/home/auro/code/parallel-n64/tools/hires_pack_review.py) when the goal is understanding rather than committing to a format.
- It consumes:
  - cache path
  - strict bundle
  - optional policy file
- It emits:
  - summary counts
  - compatibility vs unresolved family review
  - current selector state
  - current runtime context
  - current variant-group breakdown
  - simple review scores and notes for each variant group based on current observed runtime context and attached policy
  - any applied policy entries
- Use `--focus-policy-key` when you want a side-by-side decision sheet for one family.

This is the preferred inspection path while the import format is still evolving.

## Imported Subset Artifact

- Use [`tools/hires_pack_emit_subset.py`](/home/auro/code/parallel-n64/tools/hires_pack_emit_subset.py) when you want a concrete imported slice for one or more family policy keys.
- This is still a review artifact, not a commitment to final format.
- Use `--variant-selection policy_key=variant_group_id` when you want a review-only subset that materializes one ambiguous candidate as if it were selected.
- It is useful for inspecting:
  - selected family entries
  - attached selector policy
  - attached runtime context
  - the exact replacement records that would travel with that slice

## Imported Subset Comparison

- Use [`tools/hires_pack_compare_subsets.py`](/home/auro/code/parallel-n64/tools/hires_pack_compare_subsets.py) when you have multiple review-only subset artifacts for the same family.
- It summarizes:
  - proposed variant group
  - record count
  - total replacement data size
  - retained variant-group count
  - shared runtime context

## Next Implementation Step

- Inspect the review artifact and imported-index output on the strict Paper Mario families
- Inspect a tiny imported subset for the strict file-select families
- Use the attached policy layer to start testing explicit imported-family decisions without changing runtime behavior
- Decide what additional discriminators or policy fields are required to turn the ambiguous selector policies into deterministic ones, using the recorded runtime context instead of ad hoc notes
- Keep runtime code unchanged until the imported subset can be inspected and compared against strict fixture evidence
