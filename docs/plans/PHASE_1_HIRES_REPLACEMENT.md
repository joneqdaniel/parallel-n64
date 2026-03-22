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
- the current Phase 1 blocker is no longer provider startup; it is that final frame hashes still match `off`, so replacement lookup results are not yet producing a visible rendering delta on the tracked fixtures
- current code evidence says the dead stop is between lookup and render binding: this branch records hit metadata but does not yet feed `decode_rgba8()` / descriptor assignment into the active renderer path

## Not Yet Claimed Categories

- texrect edge cases beyond explicitly validated fixtures
- CI/TLUT-heavy variants not yet proven by fixture evidence
- framebuffer-derived texture cases
- broader animated UI classes outside the initial Paper Mario ladder
