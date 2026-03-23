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

## Not Yet Claimed Categories

- texrect edge cases beyond explicitly validated fixtures
- CI/TLUT-heavy variants not yet proven by fixture evidence
- framebuffer-derived texture cases
- broader animated UI classes outside the initial Paper Mario ladder
