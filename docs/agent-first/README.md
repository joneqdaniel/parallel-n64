# Agent-First Workspace

## Purpose

- make project state, plans, decisions, and machine assumptions obvious to newly spawned agents
- keep cross-project workflow design separate from renderer implementation details and local run output

## Read Order

1. [Project State](/home/auro/code/parallel-n64/docs/agent-first/PROJECT_STATE.md)
2. [Phase Overview](/home/auro/code/parallel-n64/docs/agent-first/plans/PHASE_OVERVIEW.md)
3. [Workspace Paths](/home/auro/code/parallel-n64/docs/agent-first/WORKSPACE_PATHS.md)
4. [Project Notebook](/home/auro/code/parallel-n64/PROJECT_NOTES.md)

## Core Docs

- [Project State](/home/auro/code/parallel-n64/docs/agent-first/PROJECT_STATE.md): mission, status, locked decisions, corruption definition
- [Workspace Paths](/home/auro/code/parallel-n64/docs/agent-first/WORKSPACE_PATHS.md): canonical local repo and dependency paths
- [Plans](/home/auro/code/parallel-n64/docs/agent-first/plans/README.md): phase docs and supporting contracts
- [Project Notebook](/home/auro/code/parallel-n64/PROJECT_NOTES.md): detailed running synthesis and research log

## Workflow Directories

- [tools/scenarios](/home/auro/code/parallel-n64/tools/scenarios): deterministic runners and orchestration
- [tools/fixtures](/home/auro/code/parallel-n64/tools/fixtures): fixture manifests and scenario metadata
- [tools/adapters](/home/auro/code/parallel-n64/tools/adapters): cross-repo wrapper glue
- [artifacts](/home/auro/code/parallel-n64/artifacts): generated captures, logs, reports, and debug bundles

## Boundary Rules

- keep cross-project workflow design here
- keep renderer-specific semantics in implementation and implementation-facing docs
- keep game-specific semantics out of generic adapters unless explicitly acting as debug-only instrumentation
- keep generated output out of versioned planning docs
