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
- the reported RetroArch `frame=` value is trustworthy enough to use as a fixture-relative frame clock
- steady-state fixtures use authoritative savestates with the canonical path `load -> settle 3 -> capture`

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
- complete: replaced the hardcoded libretro serialize size with a computed M64P size contract and bounded save writes, then verified the rebuilt core through the tracked title-screen save/load runtime scenario
- complete: identified `run-build.sh` as the authoritative ParaLLEl-aware build path; raw `make` can mix stale artifacts across flag sets
- complete: replaced timing-only startup assumptions with a log-gated readiness check keyed to `EmuThread: M64CMD_EXECUTE.`
- complete: added explicit RetroArch stdin agent commands for `SET_PAUSE`, `STEP_FRAME`, and `LOAD_STATE_SLOT_PAUSED`
- complete: fixed the RetroArch stdin action parser so longer action commands are not shadowed by shorter prefix matches
- complete: disabled widgets and screenshot/save-state notifications in tracked runtime runs so screenshots can be compared byte-for-byte
- complete: verified an authoritative savestate-backed title-screen fixture with a deterministic post-load settle rule: load paused, advance `3` frames, capture
- complete: verified repeated authoritative title-screen runs now produce byte-identical screenshots at `4x`
- complete: added explicit RetroArch stdin agent commands for per-port input override (`SET_INPUT_PORT`, `CLEAR_INPUT_PORT`, `GET_INPUT_PORT`)
- complete: verified repeated deterministic controller-input probes from the authoritative title-screen state produce byte-identical post-input captures
- complete: fixed RetroArch command timing so agent commands are polled at the runloop level instead of landing too late inside `retro_run()`
- complete: fixed the `STEP_FRAME` budget so it only decrements when a real core frame executed
- complete: made RetroArch `GET_STATUS frame=` trustworthy as a fixture-relative frame clock for the tracked Paper Mario scenarios
- complete: promoted the validated `START`-hold controller path into a tracked Paper Mario file-select scenario and verified repeated scenario runs produce byte-identical captures distinct from the title-screen baseline
- complete: minted an authoritative file-select savestate from the deterministic bootstrap path and switched the steady-state file-select fixture back to `load -> settle 3 -> capture`
- complete: scenario bundles now record requested/used authority mode plus active state hashes for tracked Paper Mario savestate fixtures
- complete: added a dedicated file-select remint helper so authoritative state replacement is intentional and verified instead of ad hoc
- complete: documented the shared scenario model and added a common scenario shell library so new fixtures inherit the same authority/bundle contract
- complete: encoded the current Paper Mario savestate lineage in a machine-readable authority graph and pointed tracked fixtures at it
- complete: closed a tracked adapter race by adding a runtime launch lock so emulator-facing scenarios cannot overlap
- complete: extended the fixture model to distinguish active vs planned ladder steps and scaffolded `hos_05 ENTRY_3` as the next explicit Paper Mario target

## Out Of Scope

- broad multi-game validation
- final hi-res correctness
- final scaling correctness
- heavy dependence on `papermario-dx`
