# Agent Instructions

## Start Here
- [README.md](/home/auro/code/parallel-n64/README.md)
- [Project State](/home/auro/code/parallel-n64/docs/PROJECT_STATE.md)
- [Phase Overview](/home/auro/code/parallel-n64/docs/plans/PHASE_OVERVIEW.md)
- [Hi-Res Runtime Primary Plan](/home/auro/code/parallel-n64/docs/plans/hires_runtime_primary_plan.md)
- [Workspace Paths](/home/auro/code/parallel-n64/docs/WORKSPACE_PATHS.md)
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
| Rebuild live libretro core for ParaLLEl scenarios | `make -j4 -B HAVE_PARALLEL=1 parallel_n64_libretro.so` |

## Active Scope
- Current plan sequence: Phase 0 tooling, Phase 1 hi-res replacement, Phase 2 scaling
- Current controlling plan for the runtime/package shift: [Hi-Res Runtime Primary Plan](/home/auro/code/parallel-n64/docs/plans/hires_runtime_primary_plan.md)
- Immediate execution order:
  - validation trust and authority cleanup
  - first provider/loader preservation slice for `PHRB`
  - palette parity, `LoadBlock`, and `hts2phrb` skeleton work in parallel
  - identity classification before default-path promotion
- Validation scope is Paper Mario only until the first major milestone is stable
- `feature off` must stay baseline-safe
- Evidence bundles are required for fixture runs
- Fallbacks and exclusions must report explicit reasons
- Emulator-facing runtime tests run at `4x` internal scale and one at a time

## Key Paths
- Active renderer work: [mupen64plus-video-paraLLEl](/home/auro/code/parallel-n64/mupen64plus-video-paraLLEl)
- Libretro seam: [libretro/libretro.c](/home/auro/code/parallel-n64/libretro/libretro.c)
- Current tests: [tests/emulator_behavior](/home/auro/code/parallel-n64/tests/emulator_behavior)
- Fixtures: [tools/fixtures](/home/auro/code/parallel-n64/tools/fixtures)
- Scenarios: [tools/scenarios](/home/auro/code/parallel-n64/tools/scenarios)
- Adapters: [tools/adapters](/home/auro/code/parallel-n64/tools/adapters)
- Plans: [docs/plans](/home/auro/code/parallel-n64/docs/plans)

## Working Rules
- Prefer explicit classification: baseline issue, hi-res issue, scaling issue, or tooling/fixture issue
- Treat `papermario-dx` as optional debug help, not final correctness authority
- Keep machine-specific path assumptions aligned with [WORKSPACE_PATHS.md](/home/auro/code/parallel-n64/docs/WORKSPACE_PATHS.md)
- Do not parallelize emulator-facing runtime tests; they are heavy and occupy the display

## Commit Attribution
AI commits MUST include:
```text
Co-Authored-By: <agent name> <noreply@openai.com>
```
