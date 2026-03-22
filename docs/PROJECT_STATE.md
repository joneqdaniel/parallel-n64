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
- The tracked file-select scenario now has an authoritative savestate-backed steady-state path and still preserves the title-screen bootstrap controller path for reminting
- Repeated file-select authoritative runs now produce byte-identical screenshots at `4x` after the 3-frame settle
- The canonical Paper Mario fixture workflow is now `load state -> settle 3 frames -> screenshot`; controller scripting is the bootstrap path for minting new authoritative states
- The current authoritative file-select state was minted from the deterministic bootstrap path at save offset `2`
- Tracked Paper Mario scenario bundles now record requested/used authority mode and active state hashes
- There is now a dedicated file-select remint helper for intentionally rebuilding the authoritative state from the bootstrap path
- Paper Mario fixture lineage is now explicit in a machine-readable authority graph at `tools/fixtures/paper-mario-authority-graph.yaml`
- The next ladder target, `hos_05 ENTRY_3`, is now modeled explicitly as a planned fixture even though its bootstrap route and authoritative state are not minted yet
- The tracked RetroArch adapter now enforces serial runtime launches with a lock in addition to the existing process check
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
