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

## Imported Index v1

- `schema_version`
- `source`
  - legacy cache path
  - legacy entry count
- `records`
  - one imported record per active legacy entry in the selected family set
  - preserves legacy checksum provenance and decoded asset metadata
- `compatibility_aliases`
  - explicit aliases for constrained compatibility tiers only
  - currently intended for `compat-unique` and `compat-repl-dims-unique`
- `unresolved_families`
  - explicit ambiguous legacy families that should not become runtime fallback automatically

## Next Implementation Step

- Inspect the imported-index output on the strict Paper Mario families
- Decide what additional fields are required to disambiguate ambiguous CI families during import
- Keep runtime code unchanged until the imported subset can be inspected and compared against strict fixture evidence
