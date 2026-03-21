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
- first real RetroArch control adapter using existing command seams
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

## Current Progress

- complete: RetroArch checkout reset to upstream
- complete: first Paper Mario title-screen fixture manifest
- complete: first bundle scaffold with ROM and hi-res pack hashes
- complete: first RetroArch stdin control path using existing command seams
- complete: first live title-screen runtime attempt with `GET_STATUS`, pause, and screenshot evidence
- complete: standardized tracked RetroArch runtime scenarios as fullscreen window launches with a singleton guard against concurrent `retroarch` processes
- complete: identified the current save/load crash as a command-timing issue after `SAVE_STATE`, not a raw serialization failure
- complete: added local adapter `WAIT <seconds>` support and applied explicit waits to the tracked title-screen save/load flow
- complete: confirmed the main frontend-side crash trigger is RetroArch savestate thumbnail capture on the Vulkan HW-frame path; disabling thumbnails restores stable save/load behavior for the tracked flow
- complete: verified the tracked title-screen scenario now saves, loads, and captures evidence successfully on the repo-default path with savestate thumbnails disabled and explicit waits after save/load
- complete: verified graceful RetroArch shutdown on the tracked path by disabling frontend quit confirmation (`confirm_quit = "false"`) in the adapter appendconfig
- pending: authoritative savestate-backed title-screen fixture
- pending: replace fixed waits with a stronger completion/ack mechanism once the minimal control path is stable
- in progress: replace the hardcoded libretro serialize size with a computed M64P size contract and bounded save writes; touched objects compile, full integrated verification still pending

## Out Of Scope

- broad multi-game validation
- final hi-res correctness
- final scaling correctness
- heavy dependence on `papermario-dx`
