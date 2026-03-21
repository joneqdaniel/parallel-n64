# parallel-n64 Agent Workspace

## Mission

This repo is the planning and implementation home for a stable hi-res texture replacement and scaling program for the ParaLLEl video core.

The project is being run as an agent-first workflow:

- the docs should let a new agent understand the mission quickly
- the plans should make phase, scope, and exit criteria explicit
- the tooling should make debugging reproducible without UI guesswork

## Current Status

The project is in formal planning and documentation hardening ahead of implementation.

The agreed backbone is:

1. Phase 0: agent-first tooling, fixtures, evidence bundles, deterministic control
2. Phase 1: hi-res replacement without corruption
3. Phase 2: scaling and sharpness work

Current validation scope is Paper Mario only.
The first strict Phase 1 fixtures are title screen and file select.

## Start Here

- [AGENTS.md](/home/auro/code/parallel-n64/AGENTS.md)
- [Project State](/home/auro/code/parallel-n64/docs/PROJECT_STATE.md)
- [Phase Overview](/home/auro/code/parallel-n64/docs/plans/PHASE_OVERVIEW.md)
- [Workspace Paths](/home/auro/code/parallel-n64/docs/WORKSPACE_PATHS.md)
- [Project Notebook](/home/auro/code/parallel-n64/PROJECT_NOTES.md)
- [Docs Index](/home/auro/code/parallel-n64/docs/README.md)

## Key Working Rules

- `feature off` must preserve baseline behavior unless a change clearly brings the renderer closer to N64 parity
- `feature on` prioritizes correctness and diagnosability over apparent early coverage
- fixture runs require evidence bundles
- fallback and exclusion behavior must be explicit and logged
- savestates are the authority once available; debug warps and scripted entry are acceptable earlier in the ladder
- emulator-facing runtime tests should run at `4x` internal scale and one at a time

## Active Repos In Scope

- [parallel-n64](/home/auro/code/parallel-n64)
- [RetroArch](/home/auro/code/RetroArch)
- [papermario-dx](/home/auro/code/paper_mario/papermario-dx)

Use [Workspace Paths](/home/auro/code/parallel-n64/docs/WORKSPACE_PATHS.md) for the canonical local layout on this machine.

## Key Repo Areas

- [mupen64plus-video-paraLLEl](/home/auro/code/parallel-n64/mupen64plus-video-paraLLEl): active video-core implementation target
- [libretro/libretro.c](/home/auro/code/parallel-n64/libretro/libretro.c): frontend/core option seam in this repo
- [tests/emulator_behavior](/home/auro/code/parallel-n64/tests/emulator_behavior): current emulator behavior test surface
- [tools/fixtures](/home/auro/code/parallel-n64/tools/fixtures): versioned fixture metadata
- [tools/scenarios](/home/auro/code/parallel-n64/tools/scenarios): deterministic scenario runners
- [tools/adapters](/home/auro/code/parallel-n64/tools/adapters): cross-repo wrapper glue
- [artifacts](/home/auro/code/parallel-n64/artifacts): generated workflow output

## Local Commands

- `./run-build.sh`
- `./run-tests.sh`
- `./run-tests.sh --profile emu-required`
- `./run-tests.sh --profile emu-runtime-conformance`
- `./run-dump-tests.sh --provision-validator`

See [EMU_TESTING.md](/home/auro/code/parallel-n64/docs/EMU_TESTING.md) for the current test tiers.
