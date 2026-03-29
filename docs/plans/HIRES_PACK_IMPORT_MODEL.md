# Hi-Res Pack Import Model

## Why This Exists

- The current inherited Glide-era pack format appears to collapse multiple semantic variants into the same runtime family
- Some CI families are suitable for constrained compatibility handling
- Other CI families are fundamentally ambiguous under the legacy format and should not be promoted into permissive runtime fallback

This document describes the shape of the import model itself. The evidence threshold for when we should feel confident enough to commit to that model is tracked separately in [HIRES_FORMAT_CONFIDENCE_PLAN.md](/home/auro/code/parallel-n64/docs/plans/HIRES_FORMAT_CONFIDENCE_PLAN.md).

## Core Rule

- Legacy pack format is an input format
- Internal imported format is the authoritative working format for future ParaLLEl hi-res work
- The authoritative imported identity should describe the sampled texture object plus relevant sampler/palette state, not merely the legacy upload blob or filename schema

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
- [`tools/hires_pack_compare_views.py`](/home/auro/code/parallel-n64/tools/hires_pack_compare_views.py)
  - compares the legacy-family view against the canonical sampled-object view for one emitted subset
- [`tools/hires_pack_proxy_review.py`](/home/auro/code/parallel-n64/tools/hires_pack_proxy_review.py)
  - aggregates transport-hint families onto their real runtime sampled-object proxies so we can review the actual transport pool before promoting anything into runtime-ready bindings
  - now also treats runtime-ready sampled canonical records as direct proxies, so deterministic sampled slices and unresolved hint-collapsed proxy slices share one review model
- [`tools/hires_pack_emit_proxy_bindings.py`](/home/auro/code/parallel-n64/tools/hires_pack_emit_proxy_bindings.py)
  - emits sampled-proxy-centered bindings and unresolved proxy transport cases so selection can happen against the real sampled object instead of the hint families
- [`tools/hires_pack_emit_bindings.py`](/home/auro/code/parallel-n64/tools/hires_pack_emit_bindings.py)
  - emits deterministic canonical sampled-object bindings and separates unresolved transport cases for future importer work
- [`tools/hires_pack_emit_loader_manifest.py`](/home/auro/code/parallel-n64/tools/hires_pack_emit_loader_manifest.py)
  - emits a loader-oriented manifest from deterministic bindings so future runtime/import work can consume canonical records without deciding on JSON-in-C++ yet
- [`tools/hires_pack_materialize_package.py`](/home/auro/code/parallel-n64/tools/hires_pack_materialize_package.py)
  - materializes a deterministic canonical package slice with extracted PNG assets so transport output can be inspected directly before runtime integration
- [`tools/hires_pack_emit_binary_package.py`](/home/auro/code/parallel-n64/tools/hires_pack_emit_binary_package.py)
  - emits a parser-friendly binary package with raw RGBA payloads, so future C++ integration can avoid both JSON and PNG decoding on the hot path
- [`tools/hires_pack_inspect_binary_package.py`](/home/auro/code/parallel-n64/tools/hires_pack_inspect_binary_package.py)
  - round-trips the `PHRB` package format into a readable JSON view so the binary handoff stays verifiable before a C++ consumer exists
- [`tools/hires_pack_select_transport.py`](/home/auro/code/parallel-n64/tools/hires_pack_select_transport.py)
  - narrows a materialized canonical package to one selected transported payload per policy key, so runtime-ready `PHRB` experiments can stay tool-side and reproducible
- [`tools/hires_pack_transport_policy.json`](/home/auro/code/parallel-n64/tools/hires_pack_transport_policy.json)
  - records provisional transported-payload choices separately from family/variant-group import policy, so canonical runtime packages can be selected without pretending the choice is final or universal
- [`tools/hires_pack_build_selected_package.py`](/home/auro/code/parallel-n64/tools/hires_pack_build_selected_package.py)
  - builds a reproducible selected `PHRB` package from existing `bindings.json` payloads plus explicit policy-backed review-pool candidates
  - now supports `--bindings-input` for extending an existing selected package and policy-backed single-candidate review-pool picks via `selected_replacement_id`

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
- `canonical_records`
  - one record per sampled-object canonical identity observed in the imported slice
  - links canonical sampled object IDs to the legacy replacement records that currently transport into them
  - now also carries concrete `transport_candidates` with imported replacement payload metadata for each linked legacy replacement
- `legacy_transport_aliases`
  - one record per legacy family-to-canonical transport edge
  - explicit bridge between upload-family inputs and sampled-object runtime identity
- `compatibility_aliases`
  - explicit aliases for constrained compatibility tiers only
  - currently intended for `compat-unique` and `compat-repl-dims-unique`
  - now also carries:
    - `observed_runtime_context`
    - `selector_policy`
    - `policy_key`
    - `candidate_variant_group_ids`
    - `diagnostics.variant_groups`
    - `canonical_sampled_objects`
- `unresolved_families`
  - explicit ambiguous legacy families that should not become runtime fallback automatically
  - now grouped into explicit dimension-led `variant_groups` so import-time policy can reason about concrete ambiguous clusters instead of a flat legacy family
  - now also carries `observed_runtime_context` from the strict bundle that surfaced the family
  - now also carries `selector_policy`, even when that policy is only “manual disambiguation required”
  - now also carries `policy_key`
  - now also carries `canonical_sampled_objects`

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

The first file-select input-probe expansion now adds a third useful case as well:
- a deterministic `right` probe from the authoritative file-select state surfaces `dd798ca8/fs258`
- that family lands on a single `560x160` variant group and currently classifies as `compat-unique`
- that matters because it shows the imported selector model can grow from real bundle-backed exploration without forcing us to treat every newly exposed CI family as ambiguous by default

## Sampled-Object Canonicalization

The new strict sampled-object probe changes the transport model materially:
- legacy upload-side low-32 families are not necessarily the canonical identity ParaLLEl should match at runtime
- on the strict file-select bundle, upload families like `ab53409b` and `2a1be0a4` collapse into sampled draw-side CI4 texrect objects with canonical keys `7064585c` and `c139c1c0`
- those sampled canonical keys do not exist in the active legacy pack index, which means imported transport must preserve both:
  - a canonical sampled-object identity for ParaLLEl-owned exact lookup
  - one or more legacy upload-family aliases that explain how old packs map onto that canonical object
- practical implication: imported records should gain an explicit canonical sampled-object section, while compatibility aliases become a legacy-to-canonical transport layer instead of the primary identity model
- the new HLE-to-LLE conversion research strengthens the legacy-bridge direction, but it does not change one hard rule: direct legacy texture/palette CRC equality is transport evidence only, not the final native key
- partial bridge outputs with guessed native fields such as `tmem_offset`, `tmem_stride`, or sampled dimensions remain review artifacts and must not be treated as runtime-ready imported records
- the current preferred resolution order is now explicit: Tier 1 bridge generation, Tier 2 ROM/display-list scan for native-field recovery, Tier 3 runtime capture only for what static analysis cannot explain

The migration tool now emits that bridge when sampled-object bundle data is available:
- `records[*].diagnostics.canonical_sampled_objects`
- `compatibility_aliases[*].canonical_sampled_objects`
- `unresolved_families[*].canonical_sampled_objects`
- verified example: the emitted sampled import index at [20260327-sampled-import-index.json](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260327-sampled-import-index.json) carries `2a1be0a4/fs2 -> sampled-fmt2-siz0-off0-stride32-wh64x16-fs2-low32c139c1c0`
- the same emitted index now also keeps the dominant missing family alive as an unresolved transport record: `legacy-low32-ab53409b-fs2` with canonical sampled object `sampled-fmt2-siz0-off0-stride8-wh16x16-fs2-low327064585c` and reason `missing-active-pool`
- the same import path now also consumes tile-family parent-surface hints when a bundle carries [hires-tile-family-report.json](/home/auro/code/parallel-n64/artifacts/paper-mario-file-select-tile-family-probe/on/20260328-105848/traces/hires-tile-family-report.json):
  - delta-0 reduced-size candidates are preserved as review-only canonical sampled objects with `candidate_origin = tile-family-parent-surface`
  - current example slice: [20260328-tile-parent/import-index.json](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-tile-parent/import-index.json)
  - current review artifact: [20260328-tile-parent/review.md](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-tile-parent/review.md)
  - the same slice now materializes into [20260328-tile-parent/bindings.json](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-tile-parent/bindings.json), [20260328-tile-parent/loader-manifest.json](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-tile-parent/loader-manifest.json), [20260328-tile-parent/package.phrb](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-tile-parent/package.phrb), and [20260328-tile-parent/package-inspect.json](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-tile-parent/package-inspect.json)
  - current result: `0` deterministic bindings and `5` unresolved/review-only transport cases
  - the important new signal is not runtime readiness, but proxy alignment: each same-start `16x16 CI4` hint now points at the one real sampled-object proxy observed in the source sampled bundle, `sampled-fmt2-siz0-off0-stride8-wh16x16-fs2-low327064585c`
  - those hints simultaneously record `runtime_proxy_identity_mismatch=1`, which is why they must stay review-only until the canonical transport path is expressed in terms of the real sampled object rather than the hinted legacy low-32 family
  - practical implication: active file-select `8x16` families can now enter the canonical transport discussion as explicit same-start `16x16 CI4` hints with a linked runtime proxy, without pretending they are final runtime-ready imported records
- the review and subset tools can now be driven directly from the sampled strict bundle with explicit `--low32/--formatsize` seeds, which is how [20260327-sampled-review.md](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260327-sampled-review.md) and [20260327-sampled-subset.json](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260327-sampled-subset.json) were emitted
- the canonical transport view for that same slice is now explicit too:
  - the imported index itself now carries `canonical_records` and `legacy_transport_aliases`
  - `canonical_records[*].transport_candidates` now makes the deterministic sampled-object path concrete by embedding the transported replacement payload metadata directly in the canonical record
- the next narrowing step is now explicit too: deterministic canonical bindings can be emitted directly from a sampled subset via [`tools/hires_pack_emit_bindings.py`](/home/auro/code/parallel-n64/tools/hires_pack_emit_bindings.py), while unresolved transport cases stay separate
- from there, [`tools/hires_pack_emit_loader_manifest.py`](/home/auro/code/parallel-n64/tools/hires_pack_emit_loader_manifest.py) can flatten the deterministic slice into the exact asset-oriented fields the current legacy cache loader path already understands
- [`tools/hires_pack_materialize_package.py`](/home/auro/code/parallel-n64/tools/hires_pack_materialize_package.py) now takes that one step further and emits a concrete package directory with decoded image assets plus a package manifest
- [`tools/hires_pack_emit_binary_package.py`](/home/auro/code/parallel-n64/tools/hires_pack_emit_binary_package.py) now turns that package directory into a simple binary container (`PHRB` v2) with fixed-width tables, a string table, raw RGBA blobs, and numeric sampled-object identity fields (`sampled_low32`, `sampled_entry_pcrc`, `sampled_sparse_pcrc`)
- [`tools/hires_pack_inspect_binary_package.py`](/home/auro/code/parallel-n64/tools/hires_pack_inspect_binary_package.py) now provides the inverse inspection path for both `PHRB` v1 and v2, so the binary handoff is testable without touching the runtime
- the current conservative runtime loader only consumes `PHRB` records with exactly one transported asset candidate, which is intentional: multi-candidate canonical records still need tool-side transport selection before they are runtime-ready
- the new narrowing step is now explicit and reproducible via [`tools/hires_pack_select_transport.py`](/home/auro/code/parallel-n64/tools/hires_pack_select_transport.py)
- that narrowed path is now runtime-proven for the deterministic sampled-object `c139c1c0` slice on strict file select:
  - loading the wrong canonical package ([20260328-sampled-phrb-runtime-2](/home/auro/code/parallel-n64/artifacts/paper-mario-file-select/on/20260328-sampled-phrb-runtime-2)) produces no exact hits and collapses to baseline `off`, which is the expected negative control
  - narrowing the correct sampled package to one payload at a time yields two valid runtime experiments with exact sampled-object hits:
    - [20260328-sampled-c139-opt1](/home/auro/code/parallel-n64/artifacts/paper-mario-file-select/on/20260328-sampled-c139-opt1)
    - [20260328-sampled-c139-opt2](/home/auro/code/parallel-n64/artifacts/paper-mario-file-select/on/20260328-sampled-c139-opt2)
  - both prove the current remaining ambiguity is transport policy, not canonical sampled-object lookup plumbing
- the transport-policy-backed path is now split cleanly:
  - [`tools/hires_pack_transport_policy.json`](/home/auro/code/parallel-n64/tools/hires_pack_transport_policy.json) now carries both `transport_families` and `transport_proxies`
  - [20260328-sampled-proxy](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-sampled-proxy) proves the proxy-centered package handoff can be emitted as a real `PHRB` v2 slice for `c139c1c0`
  - [20260328-tile-parent-proxy](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-tile-parent-proxy) makes the unresolved `7064585c` sampled proxy the active review surface instead of the five collapsed hint families
- current runtime status is stronger again after the lookup-only seam fix:
  - the earlier live regression was caused by a frontend/runtime prerequisite bug, not by the proxy package shape: lookup-only mode was not enabling host-visible TMEM even though draw-side sampled-object exact lookup depends on CPU-visible TMEM
  - [`mupen64plus-video-paraLLEl/rdp.cpp`](/home/auro/code/parallel-n64/mupen64plus-video-paraLLEl/rdp.cpp) now enables host-visible TMEM when either sampled-object probe mode or lookup-only mode is active
  - strict authoritative file-select reruns now restore exact sampled-object hits for both the old family-selected package and the new proxy-selected package:
    - [20260328-old-c139-lookup-only-fixed](/home/auro/code/parallel-n64/artifacts/paper-mario-file-select/on/20260328-old-c139-lookup-only-fixed)
    - [20260328-sampled-proxy-lookup-only-fixed](/home/auro/code/parallel-n64/artifacts/paper-mario-file-select/on/20260328-sampled-proxy-lookup-only-fixed)
  - both bundles log `2` sampled-object exact hits for `c139c1c0` and land on the same screenshot hash `831cd6a7dff2d44654c854dbbcd91d13071cf49d6622f9141084780b47bf2b32`
  - practical implication: proxy-centered packaging is now runtime-proven again for the deterministic `c139c1c0` slice, so the remaining active importer/runtime blocker is not lookup plumbing but unresolved transport selection for sampled proxies like `7064585c`
  - bundle extraction now records sampled-object exact hits separately from the upload-side summary, which keeps canonical `PHRB` lookup-only runs machine-readable instead of relying on raw log inspection
  - the first proxy-centered `7064585c` combined previews now convert the unresolved pool into a bounded review surface:
    - preview root: [20260328-7064585c-combined-previews](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-7064585c-combined-previews)
    - each preview keeps the deterministic `c139c1c0` binding and adds one representative `7064585c` transported payload
    - all six previews produce `14` sampled-object exact hits total: `12` for `7064585c` plus the shared `2` `c139c1c0` hits
    - the first mixed-family ordering is `16x16`, `120x120`, `144x144`, `384x512`, `64x64`, `96x96`
    - the focused `469bad6f` sweep now refines that ranking materially:
      - preview root: [20260328-469bad6f-previews](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-469bad6f-previews)
      - all `10` candidates keep the same `14` exact-hit structure
      - `16x16` no longer leads once the family is isolated
      - strongest current candidates are `af028e08__120x120` and `81b32e31__120x120` by RMSE, with `c3984de7__120x120` lowest by AE
      - `373fa1d0__120x120`, `e3394be6__120x120`, and `fa12dda5__120x120` collapse to the same final frame hash
      - asset comparison now reduces the effective review surface further:
        - review artifact: [asset-comparison.md](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-469bad6f-previews/asset-comparison.md)
        - `373fa1d0`, `e3394be6`, and `fa12dda5` are exact duplicates
        - `af028e08` and `81b32e31` are near-duplicates
        - `c3984de7` remains the strongest structurally distinct alternative
      - proxy-centered runtime review sharpens that further:
        - review artifact: [top3-runtime-review.md](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-469bad6f-previews/top3-runtime-review.md)
        - all three candidates keep the same `14` sampled-object exact-hit structure
        - `c3984de7__120x120` is materially farther from the proven `c139` baseline than the other two
        - `af028e08__120x120` and `81b32e31__120x120` remain extremely close in runtime output
      - the provisional proxy selection is now runtime-composed too:
        - package: [20260328-sampled-proxy-plus-706/package.phrb](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-sampled-proxy-plus-706/package.phrb)
        - runtime proof: [20260328-sampled-proxy-plus-706](/home/auro/code/parallel-n64/artifacts/paper-mario-file-select/on/20260328-sampled-proxy-plus-706)
        - the combined package reproduces the earlier `af028e08` preview hash `1a0719dfcba68736d09579d8fb1e6eb628cf62fa89544675f8d7ddffe70500bb` with `14` exact hits total
      - the selected package can now be rebuilt directly from tracked import artifacts and policy:
        - builder: [tools/hires_pack_build_selected_package.py](/home/auro/code/parallel-n64/tools/hires_pack_build_selected_package.py)
        - tracked build inputs: [20260327-sampled-import-index.json](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260327-sampled-import-index.json), [20260328-tile-parent/import-index.json](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-tile-parent/import-index.json), and [hires_pack_transport_policy.json](/home/auro/code/parallel-n64/tools/hires_pack_transport_policy.json)
        - review pools are explicit opt-ins via `--review-input` and `--review-pool-key`
        - regression diagnosis: the no-title builder briefly emitted `PHRB` v3 assets with implicit selector checksums from `legacy_checksum64`, which over-constrained sampled-object lookup compared to the old `PHRB` v2 proof package
        - current fix: selector checksums are explicit-only transport fields, not default metadata copied from legacy checksums
        - old proof revalidation: [20260328-selected-from-import-index-v2/package.phrb](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-selected-from-import-index-v2/package.phrb) still works on the current core and now verifies to hash `edb0c84ff65226ba7c37546bc06fd3bb3f78eb8965cfdf095659551e78d177de` with `13` sampled-object exact hits
        - rebuilt current proof package: [20260328-selected-no-title-v2/package.phrb](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-selected-no-title-v2/package.phrb)
        - rebuilt live proof: [20260328-selected-no-title-v2-runtime](/home/auro/code/parallel-n64/artifacts/paper-mario-file-select/on/20260328-selected-no-title-v2-runtime)
        - current result: the rebuilt v3 package reproduces the same strict runtime output as the revalidated old package while preserving the newer handoff format
      - the same selected package now has a tracked negative validation on title screen:
        - runtime proof: [20260328-selected-from-import-index-v2-runtime](/home/auro/code/parallel-n64/artifacts/paper-mario-title-screen/on/20260328-selected-from-import-index-v2-runtime)
        - current result: `0` sampled-object exact hits and the strict title frame falls back to the `off` hash
        - design implication: the current native import bridge is proven only for the file-select CI texrect seam; early-scene generalization still needs another sampled-object family or a broader draw-side eligibility model
      - the broader draw-side probe path is now validated on title copy-mode texrects and exposes a richer canonical surface than the original `940cea6e` story:
        - runtime proof: [20260328-title-sampled-probe-v4](/home/auro/code/parallel-n64/artifacts/paper-mario-title-screen/on/20260328-title-sampled-probe-v4)
        - current sampled title keys now include:
          - `940cea6e` -> `296x6` copy texrect with zeroed sampled palette CRCs
          - `28916d63` -> the same `296x6` copy texrect once TLUT state is populated
          - `7701ac09` -> `200x2` 1-cycle texrect with `53` transported `1600x16` candidates
          - `148e68ee` -> the minor `296x2` copy texrect
        - import implication: title-screen expansion now needs multi-key canonical transport for the visible title scene, not just more policy refinement for the file-select CI seam
      - the sampled transport review now preserves canonical sampled identity directly, and [hires_pack_emit_probe_pool_binding.py](/home/auro/code/parallel-n64/tools/hires_pack_emit_probe_pool_binding.py) can emit a review-only transport-pool binding straight from one sampled review group
      - the new full native title package now proves that those canonical pools can compose at runtime:
        - package: [20260328-title-combined-pools-v2-full/package.phrb](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-title-combined-pools-v2-full/package.phrb)
        - runtime proof: [20260328-title-combined-pools-v2-full-runtime](/home/auro/code/parallel-n64/artifacts/paper-mario-title-screen/on/20260328-title-combined-pools-v2-full-runtime)
        - current result: `172` exact hits total and title hash `620692162a2fbf167ef6e4a468f3a56890d229e75cbfd828dc5ad56ffe73a85b`
          - `106` hits on `7701ac09`
          - `33` hits on `28916d63`
          - `33` hits on `940cea6e`
        - distance to strict legacy `on` improves materially again:
          - full combined pools vs legacy `on`: `AE=67829221`, `RMSE=22.04`
          - earlier selector-aware `940` pool vs legacy `on`: `AE=381982996`, `RMSE=48.24`
          - earlier partial combined pools vs legacy `on`: `AE=327399288`, `RMSE=44.69`
        - policy-built title package: [20260328-selected-plus-title-v4/package.phrb](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-selected-plus-title-v4/package.phrb)
        - policy-built title runtime proof: [20260328-selected-plus-title-v4-runtime](/home/auro/code/parallel-n64/artifacts/paper-mario-title-screen/on/20260328-selected-plus-title-v4-runtime)
        - corrected cache-path proof: [20260328-title-control-correct-cache](/home/auro/code/parallel-n64/artifacts/paper-mario-title-screen/on/20260328-title-control-correct-cache)
        - current result: explicit review-pool selectors now let the tracked builder reproduce the older full-title package exactly on the strict title fixture once the selected `PHRB` is actually loaded instead of the default `.hts`
        - current merged-package note: visual review shows the combined package improves all current comparison scenes, so the import model should still aim toward one merged package rather than scene-shaped packages as the product target
        - active selected merged package: [20260328-selected-plus-title-v8-144x16-B-policy/package.phrb](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260328-selected-plus-title-v8-144x16-B-policy/package.phrb)
        - active correctness concern: the center-content `111` region still looks wrong or unloaded, but the active merged title center crop is byte-identical to the strict legacy `on` title reference, so it is not treated as a native import regression
        - title-family isolation now points at the active import-side contributors:
          - `71c71cdd` alias experiments are exact-hit-positive but pixel-identical to the corrected title control: [20260328-title-71-alias-first-correct-cache](/home/auro/code/parallel-n64/artifacts/paper-mario-title-screen/on/20260328-title-71-alias-first-correct-cache) and [20260328-title-71-alias-last-correct-cache](/home/auro/code/parallel-n64/artifacts/paper-mario-title-screen/on/20260328-title-71-alias-last-correct-cache) both keep hash `620692162a2fbf167ef6e4a468f3a56890d229e75cbfd828dc5ad56ffe73a85b`; `alias-first` only raises sampled exact hits from `172` to `178`
          - `28916d63` exact-hit-only control collapses to the strict title `off` frame, and removing it leaves both strict title and merged file-select outputs unchanged, so it is now treated as redundant on the current strict fixtures
          - primary visible-title contributors are now `7701ac09` and `940cea6e`
          - `148e68ee` is now included as a safe zero-diff extension on the active selected merged package
          - `0f472c21` is now included as the TLUT-populated twin of that same minor 296x2 strip
          - `0e89915a` and `1d234571` are now carried provisionally through explicit selected review-pool candidates (`legacy-2c8a8202-00000000-fs0-1440x160`) rather than hand-built probe packages
          - the provisional `144x16` title pair is now source-backed: the updated Tier 2 scan [20260328-title-copyright/report.md](/home/auro/code/parallel-n64/artifacts/paper-mario-tier2-static-scan/20260328-title-copyright/report.md) matches the upstream non-JP copyright chunks directly to the current runtime `144x16` sampled pair (`0e89915a`, `1d234571`)
          - the next low-complexity unresolved title transport cases remain `049201f4` and `ce437230`, which still have no transported candidates at all; the title block-family probe proves their shared upload family `dfe97266` is a real structured `2048x1` row, and the updated Tier 2 scan [20260328-title-copyright/report.md](/home/auro/code/parallel-n64/artifacts/paper-mario-tier2-static-scan/20260328-title-copyright/report.md) now matches that seam to the non-PAL `Press Start` `128x32 IA8` loadblock path rather than leaving it as an unattributed title miss
          - pack-side spot check further narrows the problem: the local `.hts` already contains five `1280x320` entries and three `1440x160` entries, which makes the remaining title IA8 gap look more like transport bridging failure than straightforward asset absence
        - debugging implication: scene-shaped packages remain control artifacts, not the intended runtime format
        - import implication: some canonical title records are transport pools, some scenes require multiple simultaneous canonical records, and the open question is now how to formalize that multi-key title path while tightening the active merged package around the remaining primary `7701ac09` / `940cea6e` contributors, with the `144x16` lower-strip pair now recorded as policy-backed provisional selections
    - practical implication: the import/runtime transport problem for `7064585c` now has a tracked provisional selection, with `81b32e31` retained as the nearest alternate and `c3984de7` as the strongest structurally distinct fallback
- the package manifest now also records decoded `pixel_sha256` values, `alpha_normalized_pixel_sha256` values, and duplicate-pixel groups, so importer design can distinguish fully distinct transport content from any future duplicate or near-duplicate transport variants
  - markdown: [20260327-sampled-legacy-vs-canonical.md](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260327-sampled-legacy-vs-canonical.md)
  - json: [20260327-sampled-canonical-projection.json](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260327-sampled-canonical-projection.json)


      - the title `Press Start` IA8 seam is now tracked through the import model as a source-backed, zero-selector sampled-object path:
        - seeded review tool: [tools/hires_seed_review_pool.py](/home/auro/code/parallel-n64/tools/hires_seed_review_pool.py)
        - seeded review artifact: [20260329-title-press-start-seeded/review.md](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260329-title-press-start-seeded/review.md)
        - it carries the two sampled title objects (`049201f4`, `ce437230`) with the five source-backed `1280x320` pack entries even though no legacy upload-family selector matches them directly
        - first important negative result: seeded legacy-selector bindings are total no-ops for all five candidates on strict title
        - `tools/hires_pack_emit_probe_pool_binding.py` now supports explicit selector modes, and `tools/hires_pack_build_selected_package.py` now threads `selector_mode` from policy-backed review pools into the selected builder path
        - zero-selector transport is the first mode that activates the seam:
          - manual proof: [20260329-press-start-09e981b2-zero-selector-runtime-v2](/home/auro/code/parallel-n64/artifacts/paper-mario-title-screen/on/20260329-press-start-09e981b2-zero-selector-runtime-v2)
          - exact hits fire on both sampled objects and the title hash becomes `ac266300c4bb14375c61994bff90368591067578d857ab5e6f7c10d85921c920`
        - full zero-selector ranking: [runtime-summary.md](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260329-title-press-start-zero-selector/runtime-summary.md)
          - all five candidates produce `2` target hits (`049201f4`, `ce437230`)
          - current lead is `legacy-09e981b2-0001abdc-fs0-1280x320`
        - transport policy now records provisional zero-selector review-pool entries for:
          - `sampled-low32-049201f4-fs259`
          - `sampled-low32-ce437230-fs259`
        - policy-built selected package: [20260329-selected-plus-title-v8-press-start-09e/package.phrb](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260329-selected-plus-title-v8-press-start-09e/package.phrb)
          - title runtime proof: [20260329-selected-plus-title-v8-press-start-09e-runtime](/home/auro/code/parallel-n64/artifacts/paper-mario-title-screen/on/20260329-selected-plus-title-v8-press-start-09e-runtime)
          - file-select runtime proof: [20260329-selected-plus-title-v8-press-start-09e-runtime](/home/auro/code/parallel-n64/artifacts/paper-mario-file-select/on/20260329-selected-plus-title-v8-press-start-09e-runtime)
          - current result: the policy-built package reproduces the manual title proof exactly and remains byte-identical to the active merged file-select package
        - import-model implication: zero-selector review-pool transport is now a justified bounded tool for source-backed sampled objects when legacy-family selectors are known to be structurally wrong; it remains provisional, explicit, and review-driven rather than becoming silent default behavior
        - broader validation now passed on the first non-menu timeout slice: [20260329-title-timeout-960-v8-press-start-09e](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/on/20260329-title-timeout-960-v8-press-start-09e) reaches `state_init_world` / `state_step_world` at `kmr_03 entry 5` with `sampled_object_probe.exact_hit_count = 0`, so the current zero-selector `Press Start` seam remains title-only across that world transition probe

      - the main `7701ac09` title strip pool is now structurally constrained by an upload-side sequence review:
        - tool: [tools/hires_title_stripe_sequence.py](/home/auro/code/parallel-n64/tools/hires_title_stripe_sequence.py)
        - artifact: [20260329-title-stripe-sequence/sequence.md](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260329-title-stripe-sequence/sequence.md)
        - the active title package still logs the underlying upload walk as exactly `56` sequential `200x2 RGBA32` stripes with dominant address delta `0x640`, matching the upstream `kmr_21` `TitleImage[1600 * i]` loop
        - that walk has `54` unique upload keys: one unresolved key, `71c71cdd`, repeats at sequence `0`, `1`, and `55`, while the remaining `53` unique stripes line up with the current `53` transported candidates in the `7701ac09` pool
        - import implication: the largest remaining title pool is no longer best understood as a flat bag of 53 candidates; it is an ordered title-surface mapping problem with one repeated unresolved edge family

      - the `296x6` title copy-strip path now shows the same structural pattern:
        - artifact: [20260329-title-copy-strip-sequence/sequence.md](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260329-title-copy-strip-sequence/sequence.md)
        - the active title package logs exactly `33` sequential `296x6` upload strips with dominant delta `0x6f0` and `29` unique upload keys
        - one key, `5c66840b2eb5c22e`, repeats at sequence `0` and `29-32`, while the remaining `29` unique keys line up with the current `29` transported candidates in the `940cea6e` pool
        - import implication: both major title pools (`7701ac09` and `940cea6e`) now look like ordered title-surface mappings with repeated edge families, which is a better guide for future canonical transport than generic pool ranking

      - ordered surface maps now make that explicit:
        - stripe map: [20260329-title-stripe-surface-map/map.md](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260329-title-stripe-surface-map/map.md)
        - copy-strip map: [20260329-title-copy-strip-surface-map/map.md](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260329-title-copy-strip-surface-map/map.md)
        - `7701ac09` maps `53` transported candidates one-to-one onto sequence slots `2-54`, leaving only the repeated unresolved edge family `71c71cdd` at `0`, `1`, and `55`
        - `940cea6e` maps all `33` sequence slots onto transported replacements directly, so it is already closer to an ordered imported surface than to a free review pool

      - ordered surface manifests now carry the first importer-facing surface shape for those pools:
        - tool: [tools/hires_emit_surface_manifest.py](/home/auro/code/parallel-n64/tools/hires_emit_surface_manifest.py)
        - stripe manifest: [20260329-title-stripe-surface-map/manifest.md](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260329-title-stripe-surface-map/manifest.md)
        - copy-strip manifest: [20260329-title-copy-strip-surface-map/manifest.md](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260329-title-copy-strip-surface-map/manifest.md)
        - import implication: for these title contributors, the next native-format step should be ordered-surface records with explicit unresolved edge slots rather than larger review pools or ad hoc selectors

      - a first tool-side ordered-surface package now makes that bridge concrete:
        - tool: [tools/hires_build_surface_package.py](/home/auro/code/parallel-n64/tools/hires_build_surface_package.py)
        - package: [20260329-title-surface-package/surface-package.json](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260329-title-surface-package/surface-package.json)
        - format id: `phrs-surface-package-v1`
        - current scope: `surface-7701ac09` (`53` replacements, `3` unresolved edge slots) and `surface-940cea6e` (`29` replacements, `0` unresolved slots)
        - import implication: the remaining design problem is no longer whether ordered surfaces are a useful abstraction; it is whether the runtime should consume this shape directly or via a narrower compiled/binary form

## Policy Layer

- Use [`tools/hires_pack_import_policy.json`](/home/auro/code/parallel-n64/tools/hires_pack_import_policy.json) to record explicit import decisions or non-binding suggestions.
- Pass it with `--policy` when emitting an imported index.
- The policy file can also carry explicit reasoning notes, including why a suggested candidate currently looks stronger and why other variant groups are weaker.
- The policy file can also carry explicit overturn conditions, so a non-binding suggestion states what new evidence would cause us to change it.
- Current examples:
  - `legacy-low32-2a1be0a4-fs258`
    - explicit selected variant group: `legacy-low32-2a1be0a4-fs258-640x160`
  - `legacy-low32-dd798ca8-fs258`
    - explicit selected variant group: `legacy-low32-dd798ca8-fs258-560x160`
  - `legacy-low32-42779bdd-fs258`
    - manual-review-required
    - suggested variant group: `legacy-low32-42779bdd-fs258-64x64`
    - suggestion is intentionally non-binding until validated
    - the earlier family-wide `120x120` suggestion was overturned by stronger mixed low32-specific runtime evidence
    - current mixed selector preview that reproduces the strict file-select `low32_any` control exactly:
      - `42779bdd:258:64x64`
      - `469bad6f:258:120x120`
      - `5464fdf1:258:384x512`
      - `53302ad5:258:120x120`
      - hash `2f00a7eb6c0c592a363fca987981d6eb6e6d5a43c9cac0d337c8f444282b18c8`
      - `AE_vs_any=0`
    - design implication: this neighborhood now looks like a per-low32 selector problem, not a single shared variant-group decision

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
- Use the file-select input-probe scenario to expand the bundle-backed CI family set gradually, one deterministic menu-state change at a time
- Inspect a tiny imported subset for the strict file-select families
- Use the attached policy layer to start testing explicit imported-family decisions without changing runtime behavior
- Decide what additional discriminators or policy fields are required to turn the ambiguous selector policies into deterministic ones, using the recorded runtime context instead of ad hoc notes
- Keep runtime code unchanged until the imported subset can be inspected and compared against strict fixture evidence

## Ordered-Surface Compile Bridge

- [`tools/hires_compile_surface_package.py`](/home/auro/code/parallel-n64/tools/hires_compile_surface_package.py) now provides the first direct bridge from `phrs-surface-package-v1` into the existing canonical runtime handoff stack.
- Input:
  - ordered-surface package JSON, for example [`20260329-title-surface-package/surface-package.json`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260329-title-surface-package/surface-package.json)
- Output:
  - `bindings.json`
  - `loader-manifest.json`
  - materialized package dir
  - `PHRB` binary
- First compiled artifact: [`20260329-title-surface-compiled/package.phrb`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260329-title-surface-compiled/package.phrb)
  - `surface-7701ac09` compiles into one sampled-object record with `53` explicit selector-bearing asset candidates
  - `surface-940cea6e` compiles into one sampled-object record with `29` explicit selector-bearing asset candidates
  - unresolved `7701ac09` edge slots remain metadata-only (`surface-7701ac09-unresolved`) instead of being promoted into fake selectors
  - edge review artifact: [`20260329-title-surface-edge-review/review.md`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260329-title-surface-edge-review/review.md) confirms the remaining `3` slots are edge-only, and that classification now carries through compiled bindings and selected-package builds
- Runtime implication:
  - ordered surfaces do not require a new core-side package format to become useful
  - current `PHRB` v3 is already expressive enough for the ordered-surface subset when each ordered slot is compiled into a selector-bearing asset candidate under one sampled-object record
- Validation:
  - title-only compiled package runtime proof: [`20260329-title-surface-compiled-runtime`](/home/auro/code/parallel-n64/artifacts/paper-mario-title-screen/on/20260329-title-surface-compiled-runtime)
  - file-select cross-scene proof: [`20260329-title-surface-compiled-runtime`](/home/auro/code/parallel-n64/artifacts/paper-mario-file-select/on/20260329-title-surface-compiled-runtime)
  - practical outcome: `940cea6e` now compiles and runs as shared selector-bearing sampled-object content, while `7701ac09` remains title-local in the first compiled bridge
- The same bridge now also composes with the selected-package builder:
  - active combined package: [`20260329-selected-plus-title-v9-grouped/package.phrb`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260329-selected-plus-title-v9-grouped/package.phrb)
  - builder inputs: selected file-select bindings + compiled ordered-surface bindings + policy-backed review-pool seams + grouped coupled title seams
  - import implication: ordered surfaces can already participate in the active selected-package flow without bypassing the rest of the canonical import model
  - builder shortcut: [`tools/hires_pack_build_selected_package.py`](/home/auro/code/parallel-n64/tools/hires_pack_build_selected_package.py) now accepts `--surface-package-input` directly, and the rebuilt `20260329-selected-plus-title-v9-direct-surface/package.phrb` is byte-identical to the earlier manual v9 package.
  - coupled review-pool shortcut: the same builder now accepts `--review-pool-group-key`, with `title-press-start-128x32-pair` and `title-copyright-144x16-pair` defined in [`tools/hires_pack_transport_policy.json`](/home/auro/code/parallel-n64/tools/hires_pack_transport_policy.json)
  - current zero-risk proof: rebuilding `20260329-selected-plus-title-v9-direct-surface/package.phrb` through `title-press-start-128x32-pair` reproduces the same package hash `55ad0bfb1792200625552f8344f687e236e62d69cf96c3447a11b0b3e34f35ab` as the explicit per-key build
  - grouped runtime proof:
    - title: [`20260329-selected-plus-title-v9-grouped-runtime`](/home/auro/code/parallel-n64/artifacts/paper-mario-title-screen/on/20260329-selected-plus-title-v9-grouped-runtime)
    - file select: [`20260329-selected-plus-title-v9-grouped-runtime`](/home/auro/code/parallel-n64/artifacts/paper-mario-file-select/on/20260329-selected-plus-title-v9-grouped-runtime)
    - practical outcome: the grouped builder path promotes the `144x16` copyright pair into the active merged package while keeping file select byte-identical to the earlier merged v9 result

