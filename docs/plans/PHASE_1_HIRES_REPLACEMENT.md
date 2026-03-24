# Phase 1: Hi-Res Replacement

## Objective

- Load hi-res replacements correctly without corruption while preserving explicit fallback to native behavior when replacement is unsafe or unavailable

## First Strict Targets

- title screen
- file select main menu

## Required Rules

- strict matching and explicit fallback over permissive false positives
- every fallback or exclusion reports a reason
- runtime behavior must remain diagnosable through bundle evidence
- `feature off` must remain baseline-safe

## Asset Direction

- start with the current Paper Mario pack in local assets
- allow preprocessing/import into a cleaner internal representation if that reduces runtime ambiguity or improves correctness
- do not treat the inherited Glide-era pack identity as authoritative if it encodes ambiguous runtime policy rather than stable texture identity

## Success Definition

- replacements load without corruption in the first strict targets
- expected replacements either apply correctly or fail with explicit reason reporting
- `feature off` bundles for the same fixtures stay visually safe and trace/config clean

## Current Entry Blocker

- paired `on` runs for the corrected ParaLLEl title-screen and file-select authorities are now reproducible and machine-readable
- the Vulkan descriptor-indexing gate and direct-pack load path are now working in tracked runs
- the hi-res provider now loads the Paper Mario pack and produces real hit/miss telemetry on both strict targets
- the replacement path is now visibly active on both strict targets, and `on` / `off` no longer match at the raw-pixel level
- the current Phase 1 blocker is no longer wiring; it is correctness: decide whether the visible deltas are the expected hi-res result or corruption, then tighten texel mapping / alias behavior until the strict fixtures are clean
- current strict-fixture evidence:
  - title screen: `lookups=196 hits=178 misses=18 provider=on`, `AE=3412580`, `RMSE=0.267821`
  - file select: `lookups=165 hits=82 misses=83 provider=on`, `AE=1289800`, `RMSE=0.0928543`
  - hi-res traces now also expose stable bucket summaries, which collapse title misses to 5 unique classes and file-select misses to 6 unique classes
  - the current dominant unresolved file-select class is `mode=block fmt=2 siz=2 wh=64x1 fs=514 tile=7` with 70 repeated misses in the last verified strict `on` bundle
  - the new pack cross-check in `hires-evidence.json` shows those current strict-fixture misses are unmatched in the active local Paper Mario `.hts` index under our current checksum generation, not mismatched under another `formatsize`
  - that is not the same as proving the pack has no intended coverage there; it still leaves open a different pack revision or a runtime keying mismatch on our side
  - the new temporary debug filter path can now suppress selected replacement classes for controlled experiments, and the first title-screen probe shows `mode=tile fmt=2 siz=1 wh=296x6 fs=258 tile=7` is a major visual driver: disabling it filters 66 replacement applications while keeping the fixture semantically stable
  - scenario runtime env files now auto-export while sourcing, after a Phase 1 tooling bug briefly made `PARALLEL_RDP_*` experiment toggles look active in the scenario shell without actually reaching the RetroArch/core child process
  - file-select probes now sharpen that picture:
    - disabling the shared `mode=tile fmt=2 siz=1 wh=296x6 fs=258 tile=7` class filters 33 replacement applications and pulls the frame much closer to baseline `off`
    - disabling `mode=tile fmt=3 siz=1 wh=16x8 fs=259 tile=7` filters 44 replacement applications but leaves the frame much closer to baseline `on`, so that class appears to be a narrower UI/detail layer
  - disabling all tile replacements on the title screen reproduces the baseline `off` hash exactly, which proves the current visible hi-res path is entirely carried by tile-hit replacement classes
  - swapping the active local pack to the closest `v4.0.1` candidate (`PM64K-NWO401`) does not change the strict title/file fixtures at all: hashes, semantic state, and hit/miss summaries stay identical
  - that means the current strict-scene misses are not resolved by a simple pack-version bump from the older local candidate to `v4.0.1 4K NWO`
  - the pack cross-check now separates a smaller implementation-bug class from full checksum absence: on file select, `8` miss events / `7` unique keys are present in the pack under the same low-32 texture CRC but a different palette half
  - those palette-variant misses are the smaller CI tile classes (`8x16` / `32x16`), not the dominant `64x1` block class
  - runtime debug logs now expose `pal=` and `pcrc=` for hi-res keys, and the current palette-variant misses all show `pal=0`, which points away from palette-bank selection and toward a deeper CI palette-CRC mismatch
  - the debug-only CI palette probe is now available on tracked file-select runs via `PARALLEL_RDP_HIRES_CI_PALETTE_PROBE=1`
  - current CI probe result:
    - changing the inferred palette entry count does not rescue the representative `8x16` / `32x16` file-select misses
    - legacy aggregate bank-hash candidates do not rescue those misses either
    - legacy per-bank hash / CRC32 candidates also fail to produce pack hits
    - the representative current and candidate palette CRCs still do not line up with the active pack's stored high-32 variants for the same low-32 texture CRCs
    - that pushes the next likely bug boundary from “pick a different CRC formula” to “verify whether the current `LoadTLUT` shadow/update path is even hashing the right palette bytes/layout”
  - the CI probe now also records low-32 pack-family structure without changing lookup behavior:
    - the representative `32x16` file-select family (`low32=2a1be0a4`) is generic-only and dimension-uniform: `2` generic entries, `2` palette variants, `1` replacement-dimension family (`640x160`)
    - the representative ambiguous `8x16` family (`low32=42779bdd`) is also generic-only but structurally broad: `17` generic entries, `17` palette variants, `3` replacement-dimension families, and no entry matching the current exact palette CRC
    - that split explains why `replacement-dims-unique` is a plausible constrained compatibility tier for part of the CI problem while the broader `8x16` family still needs a better discriminator than “same low-32 texture CRC”
  - the CI probe now also carries two negative diagnostics that matter:
    - the ambiguous `8x16` miss only samples `19` palette indices across a `0..102` range, and the `32x16` miss samples `53` indices across `0..238`, but hashing only the sparse used indices still does not produce a pack hit
    - hashing the emulated TLUT words from `tlut_tmem_shadow` also does not produce pack hits for those same misses, whether using the current entry-count view or the sparse used-index view
    - that means the remaining CI ambiguity is not explained by “hash only the used palette entries” or “hash the loaded TLUT words instead of the raw shadow”; the next likely step is a more explicit compatibility/import model rather than more ad hoc CRC variants
  - the new offline family analyzer makes the pack-format pressure explicit:
    - `tools/hires_pack_family_report.py --cache assets/PAPER MARIO_HIRESTEXTURES.hts --bundle <strict-file-select-bundle>` classifies the representative `32x16` family (`low32=2a1be0a4`) as `compat-repl-dims-unique`
    - the same analyzer classifies the representative ambiguous `8x16` family (`low32=42779bdd`) as `ambiguous-import-or-policy`
    - that means part of the current CI problem is not “find the right CRC”; it is “the inherited pack format is collapsing multiple semantic variants into one runtime family, and we may need an imported internal format to separate them cleanly”
  - the migration utility now emits the first imported-index scaffold:
    - `tools/hires_pack_migrate.py --emit-import-index --cache assets/PAPER MARIO_HIRESTEXTURES.hts --bundle <strict-file-select-bundle>`
    - that output separates imported `records`, explicit `compatibility_aliases`, and `unresolved_families`
    - ambiguous and compatibility families are now grouped further into explicit dimension-led `variant_groups`, so import work can target concrete legacy clusters instead of flat low-32 families
    - those imported families now also carry `observed_runtime_context` from the strict bundle, including runtime mode, runtime `wh`, current palette CRC, sparse palette-usage data, and the emulated-TMEM palette view that exposed the ambiguity
    - imported families now also carry `selector_policy`, so the migration output states explicitly whether a family is already deterministic at import time or still requires manual disambiguation
    - current strict file-select example:
      - `2a1be0a4/fs258` collapses to one compatibility variant group: `640x160`
      - that family now has a deterministic selector policy
      - `42779bdd/fs258` remains unresolved but is now split into three import-time groups: `64x64`, `120x120`, and `144x144`
      - that family now carries a manual-disambiguation selector policy instead of being an unstructured unresolved family
    - this is the first concrete transport path from legacy Glide-era packs into a cleaner ParaLLEl-owned representation
  - the first TLUT-state correction is now in place: the shadow patches by TMEM offset instead of wiping the whole palette shadow on every 32-byte update
  - current result of that correction:
    - the representative CI palette CRCs change materially on file select, so the old whole-shadow overwrite path was definitely wrong
    - the strict file-select frame and hit/miss totals still do not improve, so offset/persistence alone is not the remaining fix
  - a naive “swap every 16-bit TLUT entry before hashing” follow-up was tested and rejected:
    - it regressed strict file select to `hits=48` / `misses=117`
    - it changed the file-select `on` frame to `948a4fad87bba561d40cf683915c9d52d6273f1a15017f17885fd1a808a2afdd`
    - that means the remaining palette mismatch needs a more exact TMEM/TLUT representation, not a blanket byte swap at the current shadow layer
  - the new low-32 CI fallback experiments now prove that the palette-class misses are recoverable in principle:
    - `PARALLEL_RDP_HIRES_CI_LOW32_FALLBACK=1` (`unique`) produces a real but narrow result on strict file select: `hits=84` / `misses=81`, hash `d4661996bc280d4e6a6e1a4fa6dbabeadb47520c4b4b0241f9e2b20f489dcf4e`
    - in that mode, one unique `8x16` CI case is recovered while the remaining palette-class misses stay unresolved
    - `PARALLEL_RDP_HIRES_CI_LOW32_FALLBACK=3` (`replacement-dims-unique`) is the first tighter middle-ground rule:
      - it only accepts low-32 fallback when all candidate pack entries for that low-32 key agree on replacement dimensions
      - on strict file select it yields `hits=86` / `misses=79`, hash `24274e62a18c436dc13570b6e51f7dc600b0de89d4aee56086cffd82248f797a`
      - it recovers the `32x16` CI class and the single truly unique `8x16` case while leaving the ambiguous multi-size `8x16` families unresolved
    - `PARALLEL_RDP_HIRES_CI_LOW32_FALLBACK=2` (`any`) produces the first broad CI recovery result on strict file select: `hits=90` / `misses=75`, hash `2f00a7eb6c0c592a363fca987981d6eb6e6d5a43c9cac0d337c8f444282b18c8`
    - in that broader mode, the current CI palette miss classes disappear from the strict fixture and only the block classes remain unresolved
    - that makes low-32 matching a useful debug direction, but not yet an accepted runtime policy: `any` is too permissive, and `replacement-dims-unique` is the first concrete tighter rule that may be worth hardening or refining
  - the debug-only block-shape probe is now available on tracked file-select runs via `PARALLEL_RDP_HIRES_BLOCK_SHAPE_PROBE=1`
  - current probe result:
    - the dominant `mode=block fmt=2 siz=2 wh=64x1 fs=514 tile=7` class is not rescued by simple contiguous shape reinterpretation and logs as a plain `64x1` upload with `tmem_stride_words=0`
    - smaller non-dominant block misses do have alternate-shape pack hits (`128x1 -> 4x32`, `1024x1 -> 32x32`)
  - the current Phase 1 split is now explicit:
    - CI palette-class misses have a plausible tighter recovery path to design
    - the dominant block miss class is still unmatched and appears to need a different fix entirely
  - cross-emulator comparison now sharpens the broad design rule:
    - keep exact replacement identity authoritative
    - if CI compatibility lookup survives, promote it into a named second-tier identity rather than letting it remain an opaque runtime heuristic
    - focus the exact-path redesign on more faithful CI/TLUT semantics, likely closer to the effective palette slice/bank actually sampled by the RDP
    - keep block-shape probing in research mode unless a documented `LoadBlock` / `dxt` / interleave rule justifies a specific normalization path
  - current working direction:
    - keep exact runtime lookup authoritative
    - keep `replacement-dims-unique` as a debug-backed compatibility candidate, not default policy
    - keep pushing the imported/internal replacement index so it can encode a cleaner CI identity than the inherited Glide-era pack layout, including explicit variant groups where legacy families are structurally ambiguous

## Not Yet Claimed Categories

- texrect edge cases beyond explicitly validated fixtures
- CI/TLUT-heavy variants not yet proven by fixture evidence
- framebuffer-derived texture cases
- broader animated UI classes outside the initial Paper Mario ladder
