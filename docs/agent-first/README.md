# Agent-First Workspace

This directory is the home for cross-project planning and interface design.

It exists to keep agent workflow design separate from:

- renderer/core implementation
- one-off shell orchestration
- local test assets
- frontend-specific patches

## Current Structure

- [`PROJECT_NOTES.md`](/home/auro/code/parallel-n64/PROJECT_NOTES.md): living research notebook and running synthesis
- [`docs/agent-first/README.md`](/home/auro/code/parallel-n64/docs/agent-first/README.md): structure and document map
- [`tools/scenarios/`](/home/auro/code/parallel-n64/tools/scenarios): deterministic runners and orchestration
- [`tools/fixtures/`](/home/auro/code/parallel-n64/tools/fixtures): fixture manifests and scenario metadata
- [`tools/adapters/`](/home/auro/code/parallel-n64/tools/adapters): wrapper glue for external repos and tools
- [`artifacts/`](/home/auro/code/parallel-n64/artifacts): generated captures, logs, reports, and debug bundles

## Intended Document Split

`PROJECT_NOTES.md` stays as the running notebook for now.

As planning hardens, material should move into focused docs here:

- architecture and boundaries
- RetroArch tooling contract
- Paper Mario fixture matrix
- renderer instrumentation plan
- phased implementation plans

## Boundary Rule

Keep cross-project workflow design here.

Do not put:

- core-specific renderer semantics in RetroArch docs
- game-specific scene knowledge in generic tooling adapters
- ephemeral run output into versioned planning docs
