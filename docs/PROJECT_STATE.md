# Project State

## Mission

- Build a stable hi-res texture replacement and scaling path for the ParaLLEl video core
- Keep `feature off` aligned with current baseline behavior and N64 parity goals
- Build agent-first tooling so debugging and verification are reproducible

## Current Status

- Phase 0 execution is active
- Planning docs are in place and now back the implementation start
- The first tracked fixture/scenario seed is the Paper Mario title screen scaffold
- The tracked title-screen save/load loop is currently stabilized by a frontend-side mitigation: the adapter disables RetroArch savestate thumbnails on the Vulkan HW-frame path
- The repo-default title-screen scenario now produces a savestate, reloads it, and captures a screenshot with savestate thumbnails disabled and explicit waits after `SAVE_STATE` and `LOAD_STATE_SLOT 0`
- The tracked quit path now exits cleanly with a single `QUIT` command because the adapter forces `confirm_quit = "false"` in its per-run appendconfig
- The save-state serialization contract now uses a shared computed M64P size and bounded save writes, and the rebuilt core passes the tracked title-screen save/load runtime scenario
- The authoritative title-screen path now uses explicit RetroArch agent commands and a log-gated startup handoff instead of timing-only waits
- The authoritative title-screen fixture is now: load savestate paused, settle exactly `3` frames, then capture
- Tracked runtime scenarios now disable RetroArch widgets and screenshot/save-state notifications so repeated captures can be byte-identical
- Repeated title-screen authoritative runs now produce byte-identical screenshots at `4x` internal scale after the 3-frame settle
- RetroArch now has an explicit stdin agent input path for per-port joypad/analog overrides
- Repeated input probes from the authoritative title-screen state now produce byte-identical post-input captures when holding `START` through a controlled frame advance
- RetroArch `GET_STATUS frame=` is now trustworthy as a fixture-relative frame clock for the tracked Paper Mario scenarios
- The tracked adapter now normalizes `GET_STATUS` state matching, so scenario waits remain stable even when RetroArch logs `PAUSED` in uppercase
- RetroArch `STEP_FRAME` is now trustworthy for long transition-heavy probes as well; the old `int8_t` cap on frame-step requests was removed after it truncated a `300`-frame save-backed gameplay probe at `127` frames
- The tracked file-select scenario now has an authoritative savestate-backed steady-state path and still preserves the title-screen bootstrap controller path for reminting
- Repeated file-select authoritative runs now produce byte-identical screenshots at `4x` after the 3-frame settle
- The canonical Paper Mario fixture workflow is now `load state -> settle 3 frames -> screenshot`; controller scripting is the bootstrap path for minting new authoritative states
- The tracked Paper Mario scenarios now force the ParaLLEl renderer path explicitly with `PARALLEL_N64_GFX_PLUGIN_OVERRIDE=parallel` and bundle-local RetroArch core options, so fixture baselines are no longer accidentally taken on a GL path
- The tracked Paper Mario scenarios now use `WAIT_COMMAND_READY` for real command-channel readiness on the ParaLLEl path instead of relying on earlier log-only startup gates
- The local RetroArch stdin command surface now includes `PING`, and the adapter uses it to prove the command channel is ready before issuing tracked savestate commands
- The current authoritative file-select state is minted from the deterministic title-screen bootstrap path using a held `START` input for `60` frames and a frame-targeted save at `frame=303`
- Paired `off` and `on` scenario runs are now verified directly from the tracked scenario entrypoints on the corrected ParaLLEl path
- The Vulkan descriptor-indexing gate on this machine is now fixed for tracked runs: the context recovers the required feature bits through a Vulkan 1.2 feature-query fallback, and hi-res startup no longer disables itself on capability grounds
- The tracked hi-res pack-path override bug is now fixed: `PARALLEL_RDP_HIRES_CACHE_PATH` takes precedence over the core's default system-directory path during runtime resolution
- The hi-res replacement loader now accepts a direct `.hts` pack path as well as a cache directory, so the tracked Paper Mario pack loads without requiring scenario-side path hacks
- Current `on`-mode title and file-select bundles now show a loaded hi-res provider with real keying activity instead of a disabled/no-op path
- Tracked Paper Mario scenario bundles now record requested/used authority mode and active state hashes
- There is now a dedicated file-select remint helper for intentionally rebuilding the authoritative state from the bootstrap path
- Paper Mario fixture lineage is now explicit in a machine-readable authority graph at `tools/fixtures/paper-mario-authority-graph.yaml`
- The next ladder target, `hos_05 ENTRY_3`, is now modeled explicitly as a planned fixture even though its bootstrap route and authoritative state are not minted yet
- The tracked RetroArch adapter now enforces serial runtime launches with a lock in addition to the existing process check
- The tracked adapter can now snapshot core memory directly into bundle traces with `SNAPSHOT_CORE_MEMORY`
- The local RetroArch build now falls back to `RETRO_MEMORY_SYSTEM_RAM` for `READ_CORE_MEMORY` when a core does not publish a libretro memory map
- The tracked title-screen and file-select fixtures now decode an empirical vanilla Paper Mario US `gGameStatus` slice from `0x800740aa` into `traces/paper-mario-game-status.json`
- The Paper Mario semantic JSON now records a SHA-256 for that raw window plus an explicit empirical phase guess for the proven title-screen and file-select authorities
- The tracked title-screen and file-select fixtures now also snapshot symbol-backed vanilla globals for `CurGameMode` (`0x80151700`) and map-transition state (`0x800A0944`) on every authoritative run
- The corrected authoritative title-screen state now reports clean `CurGameMode` title callbacks: `state_init_title_screen` / `state_step_title_screen`
- The corrected authoritative file-select state now reports clean `CurGameMode` file-select callbacks: `state_init_file_select` / `state_step_file_select`
- The canonical steady-state title-screen capture hash is now `42e501afb2548a5067bc034578c5bcebf0bf2a40f612bbcc94972af716ad6ff2`
- The canonical steady-state file-select capture hash is now `6fa8688b382fa1e6f0323f054861a85f593d2d47ca737bb78448e3f268ca63e3`
- The embedded shader header now has a matching legacy-generation path again: the tracked shader pack was regenerated with an older `slangmosh` contract compatible with this branch, after the newer generator proved incompatible with the local Granite runtime API
- The current branch now has a minimal active replacement path for tracked fixtures: lookup results are decoded, uploaded as sampled images, assigned descriptor indices, and threaded into tile/shader state for the rasterizer path
- The latest verified `on`-mode title-screen run preserves steady-state semantics while loading the hi-res pack successfully and reporting `lookups=196 hits=178 misses=18 provider=on`
- The latest verified `on`-mode file-select run also preserves steady-state semantics while loading the hi-res pack successfully and reporting `lookups=165 hits=82 misses=83 provider=on`
- `on` and `off` are no longer pixel-identical on the strict fixtures: the current title-screen `on` hash is `ba91ffce0cc7b6053568c0a7774bf0ae80825c95d95fce89ba4a9f79c62b9d16`, and the current file-select `on` hash is `8a90f7874bd797a186ff85d488033dc332b2a75f5bec91ad33ca8246e6be7730`
- Raw-pixel comparison now confirms real visible divergence on both fixtures while semantic state stays locked: title-screen `AE=3412580`, `RMSE=0.267821`; file-select `AE=1289800`, `RMSE=0.0928543`
- The tracked title-screen and file-select scenarios can now verify known-good `on` hashes as well as `off`, so the current visible-hires milestone is enforced directly by the scenario layer instead of only by manual comparison
- The current Phase 1 blocker has therefore moved again: replacement wiring is now visibly live, and the next task is to judge correctness versus corruption on the strict fixtures and tighten texel mapping / alias behavior where needed
- The tracked adapter now supports a memory-based wait primitive, `WAIT_CORE_MEMORY_HEX`, so scenarios and probes can block on exact vanilla RAM signatures instead of sleep-only timing
- The semantic JSON now also emits a decomp-backed `map_name_candidate` for KMR, HOS, and OSR area-local map indices
- The corrected startup semantic values are stable for both tracked fixtures: `areaID=0 (AREA_KMR)`, `mapID=0`, `entryID=0`, `introPart=1`, `startupState=0`
- A deeper savefile-backed probe now verifies deterministic long-step control from the file-select authority and settles reproducibly at `areaID=0 (AREA_KMR)`, `mapID=3`, `entryID=5`
- Staging the local Paper Mario `.srm` does not change that deeper deterministic transition result, so missing external save RAM is no longer the leading explanation for the current semantic ambiguity
- Paper Mario decomp research now shows `LOAD_FROM_FILE_SELECT` is handled specially in `kmr_02`, and KMR map IDs are area-local indices rather than direct map suffixes
- In the current decomp-backed map ordering, that deeper probe's `mapID=3` corresponds to a `kmr_04` candidate, which directly highlights the remaining ambiguity: the candidate map name and the `kmr_02` file-select special case do not line up yet
- That means the first save-backed gameplay transition is now semantically distinguishable from the startup/file-select fixtures, but its current `area/map/entry` tuple should still be treated as transition evidence rather than canonical scene identity, and it does not yet reach the planned `hos_05 ENTRY_3` target
- A direct symbol-backed probe of that deeper transition shows `CurGameMode` callback pointers switch from the authority-state `logos` pair to the `intro` pair while `map_transition` remains idle, which strongly suggests the current `START` path is progressing through intro-state logic rather than a clean file-select-to-world handoff
- A deterministic cold-boot trace still shows the vanilla callback path can move through `startup -> logos -> intro` under stepped automation, but the correct wall-clock title path is now proven: `boot -> wait 20s -> START once -> wait 5s`
- The correct wall-clock file-select path is also proven: `load title state -> settle 3 -> hold START about 1s -> release -> wait 4s`, and authoritative reminting now stabilizes that target as a deterministic paused bootstrap path: `hold START for 60 frames -> advance to frame 303 -> save`
- Direct snapshots of the raw `gGameStatus` button arrays are not yet a trustworthy input-delivery metric: they remain zero both in early boot probes and in later title-screen authority probes where `START` clearly affects behavior
- The obvious shifted-symbol probes for deeper mode/menu state have been ruled out so far: the likely `CurGameModeID` window near `0x80195750` is zero in the tracked states, and a broad `0x80180000` region scan did not produce a valid title/file-select/world mode candidate
- Tracked runtime scenarios now isolate save RAM inside each bundle, and savefile identity is explicit in bundle metadata instead of silently coming from `~/.config/retroarch/saves`
- There is now an intentional helper to stage a local Paper Mario `.srm` into gitignored assets for future deeper fixtures
- RetroArch `SAVE_STATE` is now understood as an asynchronous task path; tracked authority minting requires `WAIT_SAVE_STATE`, and save operations must be sequenced ahead of screenshot tasks to avoid blocking-task contention
- `run-build.sh` is the authoritative local build entrypoint because it carries the ParaLLEl build flags and auto-cleans when flag fingerprints change

## Locked Planning Backbone

1. Phase 0: agent-first tooling, fixtures, evidence bundles, deterministic control
2. Phase 1: hi-res replacement without corruption
3. Phase 2: scaling and sharpness work

## Current Validation Scope

- Paper Mario only
- First strict Phase 1 fixtures:
  - title screen
  - file select

## Paper Mario Fixture Ladder Status

- active: title screen
- active: file select main menu
- planned: `hos_05 ENTRY_3`
- planned: `osr_00 ENTRY_3`
- planned: pause stats/items

## Locked Decisions

- Savestates are the authority once available
- Debug warps and scripted entry are acceptable before authoritative savestates exist
- Fixture identity is locked to manifest, ROM identity, savestate identity, config snapshot, and expected capture points
- Evidence bundles are required
- Evidence bundles include final output plus lightweight intermediate evidence
- Fallbacks and exclusions must report explicit reasons
- `papermario-dx` is optional debug help, not the final correctness authority
- Runtime asset support starts with the current Paper Mario pack
- Preprocessing/import into a cleaner internal representation is allowed if it improves correctness and debugging

## Corruption Definition For Phase 1

- wrong texture content
- broken placement or scaling
- obvious sampling artifacts such as extra dots, dithering-like corruption, or visual breakup
- UI or message corruption
- crashes, asserts, or hangs
- silent fallback when replacement was expected

## Repos In Scope

- [parallel-n64](/home/auro/code/parallel-n64)
- [RetroArch](/home/auro/code/RetroArch)
- [papermario-dx](/home/auro/code/paper_mario/papermario-dx)

## Working Rule

- classify issues using all available evidence: output, traces, logs, telemetry, fixture identity, and config state
