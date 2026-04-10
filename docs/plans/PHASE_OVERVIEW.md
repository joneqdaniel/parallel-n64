# Phase Overview

## Goal

- Build a stable hi-res replacement and scaling program for the ParaLLEl video core without regressing baseline behavior when the feature is off.

## Phase Ladder

1. Phase 0: tooling, fixtures, and evidence discipline
2. Phase 1: hi-res replacement without corruption
3. Phase 2: scaling and sharpness work

## Active Redirect Inside Phase 1

The controlling sequence for the current Phase 1 work lives in
[Hi-Res Runtime Primary Plan](/home/auro/code/parallel-n64/docs/plans/hires_runtime_primary_plan.md).

The current near-term order is:

1. keep the promoted enriched full-cache `PHRB` baseline green on the active Paper Mario authority fixtures
2. continue provider-owned runtime-contract tightening and remove remaining checksum-shaped seams
3. continue strengthening `hts2phrb` as the common-case front door without letting converter convenience outrun the runtime contract
4. continue reducing canonical-only ambiguity and overlay residue through bounded review-only policy
5. keep the zero-config compat-only lane and the tracked review-only reduction lane explicit and non-default
6. leave pool semantics, source-backed triangle promotion, auto-conversion, and second-game breadth deferred until the core runtime/converter picture is cleaner

## Current Runtime And Converter Lanes

- Promoted enriched full-cache `PHRB` baseline:
  - default Paper Mario authority and conformance path
- Zero-config compat-only fallback:
  - explicit override or dedicated refresh lane only
- Tracked review-only reduction lane:
  - maintained converter-side ambiguity reduction proof, explicitly non-default

Use [`docs/PROJECT_STATE.md`](/home/auro/code/parallel-n64/docs/PROJECT_STATE.md) for the live counts and current residue in those lanes.

## Why This Order

- Tooling and fixture trust must exist before runtime movement means anything.
- Runtime-contract tightening must happen before converter convenience can be trusted.
- Converter-side reductions should stay review-only until they clear the same gates as runtime changes.
- Scaling work should build on a stable replacement path, not on a moving target.

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

- semantic hi-res evidence participates in pass/fail
- tooling and docs can overlap, but runtime promotion still needs explicit sign-off
- default-path promotion waits for the Paper Mario breadth gate
- generality claims wait for second-game validation
