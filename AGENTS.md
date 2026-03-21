# Agent Instructions

## Start Here
- [README.md](/home/auro/code/parallel-n64/README.md)
- [Project State](/home/auro/code/parallel-n64/docs/agent-first/PROJECT_STATE.md)
- [Phase Overview](/home/auro/code/parallel-n64/docs/agent-first/plans/PHASE_OVERVIEW.md)
- [Workspace Paths](/home/auro/code/parallel-n64/docs/agent-first/WORKSPACE_PATHS.md)
- [Project Notebook](/home/auro/code/parallel-n64/PROJECT_NOTES.md)

## Package Manager
- None. Use root shell scripts, `cmake`, `ctest`, and `make` as needed.

## File-Scoped Commands
| Task | Command |
|------|---------|
| Build target | `cmake --build build --target <target>` |
| Run one test | `ctest --test-dir build -R <test_name> --output-on-failure` |
| Required gate | `./run-tests.sh --profile emu-required` |
| Runtime gate | `./run-tests.sh --profile emu-runtime-conformance` |
| Dump gate | `./run-dump-tests.sh --provision-validator` |

## Active Scope
- Current plan sequence: Phase 0 tooling, Phase 1 hi-res replacement, Phase 2 scaling
- Validation scope is Paper Mario only until the first major milestone is stable
- `feature off` must stay baseline-safe
- Evidence bundles are required for fixture runs
- Fallbacks and exclusions must report explicit reasons

## Key Paths
- Active renderer work: [mupen64plus-video-paraLLEl](/home/auro/code/parallel-n64/mupen64plus-video-paraLLEl)
- Libretro seam: [libretro/libretro.c](/home/auro/code/parallel-n64/libretro/libretro.c)
- Current tests: [tests/emulator_behavior](/home/auro/code/parallel-n64/tests/emulator_behavior)
- Fixtures: [tools/fixtures](/home/auro/code/parallel-n64/tools/fixtures)
- Scenarios: [tools/scenarios](/home/auro/code/parallel-n64/tools/scenarios)
- Adapters: [tools/adapters](/home/auro/code/parallel-n64/tools/adapters)
- Plans: [docs/agent-first/plans](/home/auro/code/parallel-n64/docs/agent-first/plans)

## Working Rules
- Prefer explicit classification: baseline issue, hi-res issue, scaling issue, or tooling/fixture issue
- Treat `papermario-dx` as optional debug help, not final correctness authority
- Keep machine-specific path assumptions aligned with [WORKSPACE_PATHS.md](/home/auro/code/parallel-n64/docs/agent-first/WORKSPACE_PATHS.md)

## Commit Attribution
AI commits MUST include:
```text
Co-Authored-By: <agent name> <noreply@openai.com>
```
