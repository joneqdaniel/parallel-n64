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
5. targeted structured-runtime widening
6. default-path promotion only after the Paper Mario breadth gate

This does not replace the Phase 0 / Phase 1 / Phase 2 backbone. It defines the
current execution order inside the hi-res replacement phase.

## Why This Order

- tooling first reduces ambiguity
- hi-res replacement must stabilize before scaling work can be trusted
- scaling should build on a proven replacement path, not on a moving target

## Current Validation Scope

- Paper Mario only

## First Fixture Ladder

1. active: title screen
2. active: file select main menu
3. planned: `hos_05 ENTRY_3`
4. planned: `osr_00 ENTRY_3`
5. planned: pause stats/items

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
