# Phase Overview

## Goal

- Build a stable hi-res texture replacement and scaling program for the ParaLLEl video core without losing baseline behavior when features are off

## Sequence

1. Phase 0: agent-first tooling and fixture hardening
2. Phase 1: hi-res replacement without corruption
3. Phase 2: scaling and sharpness work

## Current Redirect Inside Phase 1

The current controlling runtime/package sequence is defined in
[Hi-Res Runtime Primary Plan](/home/auro/code/parallel-n64/docs/plans/hires_runtime_primary_plan.md).

Within the existing phase ladder, the active near-term order is:

1. validation trust and authority cleanup
2. first provider/loader preservation slice for `PHRB`
3. palette parity, `LoadBlock`, and `hts2phrb` skeleton work in parallel
4. identity classification gate
5. targeted structured-runtime widening, now starting from a provider that separates native sampled records from compat low32 families, explicitly prefers `PHRB` over legacy duplicate keys in mixed cache dirs, can describe native sampled pools directly, resolves exact sampled descriptors through native sampled decode instead of checksum-only re-selection, keeps compat CI fallback descriptors in a separate compat cache path instead of re-entering generic/native duplicates, and from a selected-package review path that distinguishes candidate-free absent families from already-rejected selector-conflict and pool-conflict families, emits explicit pool-family deferment recommendations, and surfaces provider composition in validation summaries
   - the provider also now keeps explicit native-versus-compat checksum duplicate indices, so later runtime widening does not have to infer that split from load order
6. default-path promotion only after the Paper Mario breadth gate

Current runtime split:

- active Paper Mario authorities still validate the legacy default `.hts` path
- selected-package timeout validation is the current deeper `PHRB` runtime lane
- selected-package authority validation now also proves the same explicit `PHRB` lane across title screen, file select, and `kmr_03 ENTRY_5`
- both selected-package lanes are now part of the opt-in runtime-conformance tier:
  - `emu.conformance.paper_mario_selected_package_authorities`
  - `emu.conformance.paper_mario_selected_package_timeout_validation`
- both explicit selected-package lanes now fail closed if provider composition drifts away from `phrb-only`
- provider-composition gates can now distinguish those lanes explicitly via `source_mode`, so native-`PHRB` minimums should not be promoted into the authority fixtures until that lane actually moves

This does not replace the Phase 0 / Phase 1 / Phase 2 backbone. It defines the
current execution order inside the hi-res replacement phase.

Completed enabling slices and any intentionally deferred work must stay recorded
in [Hi-Res Runtime Primary Plan](/home/auro/code/parallel-n64/docs/plans/hires_runtime_primary_plan.md),
especially its `Current Implementation State`, `Deferred Work Register`, and
`Immediate Next Step` sections.

## Why This Order

- tooling first reduces ambiguity
- hi-res replacement must stabilize before scaling work can be trusted
- scaling should build on a proven replacement path, not on a moving target

## Current Validation Scope

- Paper Mario only

## First Fixture Ladder

1. active: title screen
2. active: file select main menu
3. active: `kmr_03 ENTRY_5`
4. planned: `hos_05 ENTRY_3`
5. planned: `osr_00 ENTRY_3`

## Global Rules

- `feature off` must remain baseline-safe
- `feature on` prioritizes correctness and diagnosability over early broad coverage
- all fixture runs require evidence bundles
- all fallbacks and exclusions require explicit reason reporting
- unsupported or risky categories must be listed explicitly, not implied away

## Gate Style

- hybrid gating
- tooling and docs can overlap
- renderer milestones require explicit phase sign-off
- semantic hi-res evidence must participate in pass/fail before default-path promotion
