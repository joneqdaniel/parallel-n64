# Project State

## Mission

- Build a stable hi-res texture replacement and scaling path for the ParaLLEl video core
- Keep `feature off` aligned with current baseline behavior and N64 parity goals
- Build agent-first tooling so debugging and verification are reproducible

## Current Status

- Planning and documentation are active
- Formal implementation has not started yet
- The next execution phase is Phase 0

## Locked Planning Backbone

1. Phase 0: agent-first tooling, fixtures, evidence bundles, deterministic control
2. Phase 1: hi-res replacement without corruption
3. Phase 2: scaling and sharpness work

## Current Validation Scope

- Paper Mario only
- First strict Phase 1 fixtures:
  - title screen
  - file select

## Locked Decisions

- Savestates are the authority once available
- Debug warps and scripted entry are acceptable before authoritative savestates exist
- Fixture identity is locked to manifest, ROM identity, savestate identity, config snapshot, and expected capture points
- Evidence bundles are required
- Evidence bundles include final output plus lightweight intermediate evidence
- Fallbacks and exclusions must report explicit reasons
- `papermario-dx` is optional debug help, not the final correctness authority
- Runtime asset support starts with the current Paper Mario pack
- Preprocessing/import into a cleaner internal representation is allowed if it improves correctness and debugging

## Corruption Definition For Phase 1

- wrong texture content
- broken placement or scaling
- obvious sampling artifacts such as extra dots, dithering-like corruption, or visual breakup
- UI or message corruption
- crashes, asserts, or hangs
- silent fallback when replacement was expected

## Repos In Scope

- [parallel-n64](/home/auro/code/parallel-n64)
- [RetroArch](/home/auro/code/RetroArch)
- [papermario-dx](/home/auro/code/paper_mario/papermario-dx)

## Working Rule

- classify issues using all available evidence: output, traces, logs, telemetry, fixture identity, and config state
