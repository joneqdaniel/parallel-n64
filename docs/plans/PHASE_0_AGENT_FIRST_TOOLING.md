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
- complete: normalized adapter `GET_STATUS` state matching so tracked waits remain correct even when RetroArch logs uppercase state names such as `PAUSED`
- complete: removed the RetroArch `STEP_FRAME` request cap caused by `run_frames_and_pause` using `int8_t`; long transition probes can now execute and verify requests larger than `127` frames exactly
- complete: promoted the validated `START`-hold controller path into a tracked Paper Mario file-select scenario and verified repeated scenario runs produce byte-identical captures distinct from the title-screen baseline
- complete: minted an authoritative file-select savestate from the deterministic bootstrap path and switched the steady-state file-select fixture back to `load -> settle 3 -> capture`
- complete: scenario bundles now record requested/used authority mode plus active state hashes for tracked Paper Mario savestate fixtures
- complete: added a dedicated file-select remint helper so authoritative state replacement is intentional and verified instead of ad hoc
- complete: documented the shared scenario model and added a common scenario shell library so new fixtures inherit the same authority/bundle contract
- complete: encoded the current Paper Mario savestate lineage in a machine-readable authority graph and pointed tracked fixtures at it
- complete: closed a tracked adapter race by adding a runtime launch lock so emulator-facing scenarios cannot overlap
- complete: extended the fixture model to distinguish active vs planned ladder steps and scaffolded `hos_05 ENTRY_3` as the next explicit Paper Mario target
- complete: added bundle-level semantic memory snapshots for tracked Paper Mario fixtures and fixed local RetroArch `READ_CORE_MEMORY` fallback for cores without libretro memory maps
- complete: isolated save RAM inside tracked runtime bundles and added an intentional Paper Mario savefile staging helper for future deeper fixtures
- complete: corrected the tracked Paper Mario semantic decode to use an empirical vanilla `gGameStatus` slice at `0x800740aa` with little-endian field decoding, restoring coherent startup traces for title screen and file select
- complete: added a stable SHA-256 identity for the raw Paper Mario semantic window plus explicit empirical phase guesses for the proven title-screen and file-select authority states
- complete: added decomp-backed `map_name_candidate` output for KMR, HOS, and OSR area-local map indices so semantic traces can name likely map targets without pretending they are authoritative yet
- complete: verified the first deeper save-backed transition with the corrected semantic slice; it reproducibly settles at `AREA_KMR map=3 entry=5`, which proves non-startup state transition even though it is not the planned `hos_05 ENTRY_3` target yet
- complete: ruled out missing external save RAM as the explanation for that deeper transition; staging the local Paper Mario `.srm` does not change the observed `AREA_KMR map=3 entry=5` result
- complete: confirmed from decomp that `LOAD_FROM_FILE_SELECT` is handled specially in `kmr_02`, so the current post-file-select `area/map/entry` tuple should be treated as transition evidence, not final scene identity
- complete: mapped the current post-file-select tuple through the decomp KMR map order; `AREA_KMR map=3` currently implies a `kmr_04` candidate, which makes the remaining scene-identity ambiguity explicit instead of hidden
- complete: ruled out the first obvious shifted-symbol mode-state candidates; the likely `CurGameModeID` window near `0x80195750` is zero in the tracked states, and a broad `0x80180000` scan did not produce a valid title/file-select/world mode pattern
- complete: promoted symbol-backed vanilla globals into the tracked title-screen and file-select semantic bundle path by snapshotting `CurGameMode` (`0x80151700`) and map-transition globals (`0x800A0944`) alongside the existing `gGameStatus` slice
- complete: verified those richer tracked traces still preserve the canonical title-screen and file-select screenshot hashes while exposing a new constraint: both authority states currently report `state_init_logos` / `state_step_logos` callbacks and idle map-transition globals
- complete: verified the deeper deterministic `START` probe switches `CurGameMode` callback pointers to the `intro` pair while map-transition globals remain idle, which strongly suggests the current path is progressing through intro-state logic rather than a clean file-select-to-world handoff
- complete: added a reusable adapter wait primitive, `WAIT_CORE_MEMORY_HEX`, so runtime flows can block on exact vanilla RAM signatures instead of sleep-only timing
- complete: traced the deterministic cold-boot callback path and confirmed the current vanilla startup flow is `startup -> logos -> intro`
- complete: proved the current startup-to-title automation path is still unresolved; repeated deterministic `START` pulses do not change the cold-boot callback path
- complete: ruled out one tempting but bad metric for that investigation: direct snapshots of the raw `gGameStatus` button arrays remain zero even in later title-screen authority probes where `START` clearly affects behavior, so those raw button windows are not currently trustworthy input-delivery evidence
- complete: identified the real title-screen and file-select bootstrap routes from live wall-clock runs; title is now `boot -> wait 20s -> START once -> wait 5s`, and file select is now `load title state -> settle 3 -> START once -> wait 5s`
- complete: added a RetroArch stdin `WAIT_SAVE_STATE` command and adapter acknowledgement path so tracked workflows can wait for async save tasks instead of sleeping blindly
- complete: identified a real task-ordering constraint in RetroArch save flows; authority minting now saves before screenshots to avoid blocking-task contention in the task queue
- complete: reminted and verified a true title-screen authority state that loads back into `state_init_title_screen` / `state_step_title_screen` and captures to `611f3db618b6f38b978e4b17ba0255661f3281cc36e630a4f6891fe0aafaf285`
- complete: reminted and verified a true file-select authority state that loads back into `state_init_file_select` / `state_step_file_select` and captures to `ee62392552352b8e585eac0f2dbbd22872c20e9f05506ec1350d8b0f3c16fe0a`
- in progress: broaden the Paper Mario semantic trace beyond the current vanilla `gGameStatus` slice and current `CurGameMode`/transition windows so deeper probes can name high-level startup/menu/intro/world state cleanly and reach the planned `hos_05 ENTRY_3` authority path

## Out Of Scope

- broad multi-game validation
- final hi-res correctness
- final scaling correctness
- heavy dependence on `papermario-dx`
