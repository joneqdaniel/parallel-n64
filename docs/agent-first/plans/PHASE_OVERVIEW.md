# Phase Overview

## Goal

- Build a stable hi-res texture replacement and scaling program for the ParaLLEl video core without losing baseline behavior when features are off

## Sequence

1. Phase 0: agent-first tooling and fixture hardening
2. Phase 1: hi-res replacement without corruption
3. Phase 2: scaling and sharpness work

## Why This Order

- tooling first reduces ambiguity
- hi-res replacement must stabilize before scaling work can be trusted
- scaling should build on a proven replacement path, not on a moving target

## Current Validation Scope

- Paper Mario only

## First Fixture Ladder

1. title screen
2. file select main menu
3. `hos_05 ENTRY_3`
4. `osr_00 ENTRY_3`
5. pause stats/items

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
