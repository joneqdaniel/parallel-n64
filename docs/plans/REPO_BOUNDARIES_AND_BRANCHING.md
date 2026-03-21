# Repo Boundaries And Branching

## Repo Roles

- [parallel-n64](/home/auro/code/parallel-n64): planning source of truth, fixture metadata, scenario runners, adapters, evidence conventions, video-core implementation
- [RetroArch](/home/auro/code/RetroArch): frontend/tooling patch target for deterministic control, capture, reporting, and orchestration
- [papermario-dx](/home/auro/code/paper_mario/papermario-dx): optional debug-only semantic reference and telemetry source

## Boundary Rules

- do not put emulator-specific renderer meaning into RetroArch
- do not make final correctness depend on `papermario-dx`
- keep cross-project orchestration in `parallel-n64`, not in ad hoc shell state

## Branch Strategy

- keep `master` usable for notes, docs, and stable project metadata
- use dedicated phase branches for implementation work
- align phase names across repos when multi-repo work is active
- prefer small checkpoint commits and pushes to avoid losing project state

## Current Frontend Rule

- reset the local RetroArch fork to upstream before Phase 0 implementation begins
