# Phase 0: Agent-First Tooling

## Objective

- Create a small, reliable, reproducible toolkit for driving Paper Mario fixtures and collecting evidence without depending on UI improvisation

## Required Capabilities

- load ROM
- pause emulator
- load state
- save state
- capture frame or screenshot
- send deterministic controller input
- record structured enough status/config data to reproduce a run

## Required Outputs

- fixture manifest format
- first Paper Mario fixture registry
- evidence bundle structure
- scenario runner skeleton
- workspace path documentation
- root onboarding docs for agents

## Repo Focus

- [parallel-n64](/home/auro/code/parallel-n64): docs, manifests, scenarios, adapters, evidence structure
- [RetroArch](/home/auro/code/RetroArch): reset to upstream, then add only the tooling needed for deterministic control/capture/reporting
- [papermario-dx](/home/auro/code/paper_mario/papermario-dx): optional debug-only integration if ambiguity blocks progress

## Phase 0 Minimum Bar

- use existing RetroArch seams first
- add small additive tooling patches where current seams are not deterministic or not machine-readable enough
- reserve an internal agent-input path if existing control seams prove inadequate

## Exit Criteria

- agents can run the initial Paper Mario fixtures reproducibly
- evidence bundles are produced consistently
- fixture identity is explicit and locked
- the workflow is fast enough to be used repeatedly during renderer work

## Out Of Scope

- broad multi-game validation
- final hi-res correctness
- final scaling correctness
- heavy dependence on `papermario-dx`
