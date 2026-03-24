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
- Hi-res bundle traces now collapse raw hit/miss log spam into stable bucket summaries, so strict-fixture comparisons can track repeated uncovered classes instead of diffing whole RetroArch logs
- Current strict-fixture bucket summaries already show the next likely cleanup targets: title misses collapse to 5 unique buckets, while file-select misses collapse to 6 and are dominated by repeated `mode=block fmt=2 siz=2 wh=64x1 fs=514 tile=7` misses
- Hi-res bundle traces now also cross-check miss keys against the active `.hts` pack index, and the current strict-fixture result is narrower than an art-coverage claim: the logged title/file misses are unmatched in the local pack index under the current checksum generation, not present under some other `formatsize`
- That evidence does not yet prove the creator omitted those replacements; it still leaves room for a different pack revision or a checksum/path mismatch between our current runtime keying and the pack's intended replacement identity
- The renderer now has a temporary hi-res debug filter path driven by `PARALLEL_RDP_HIRES_FILTER_ALLOW_TILE`, `PARALLEL_RDP_HIRES_FILTER_ALLOW_BLOCK`, and `PARALLEL_RDP_HIRES_FILTER_SIGNATURES`, so strict fixtures can suppress a chosen replacement class without changing the normal architecture
- The scenario layer now supports `RUNTIME_ENV_OVERRIDE` and `DISABLE_SCREENSHOT_VERIFY=1` for controlled experimental runs that intentionally diverge from the locked strict hashes
- Scenario runtime env files are now auto-exported while sourcing, so `PARALLEL_RDP_*` debug toggles reliably reach the RetroArch/core child process during controlled experiments
- The first controlled filter experiment is now recorded on the title screen: suppressing `mode=tile fmt=2 siz=1 wh=296x6 fs=258 tile=7` yields `filtered=66`, keeps `state_init_title_screen` / `state_step_title_screen`, and produces filtered hash `654fe6a57bca20d337272304fac66216c474b7eeeea5d3d494cae73a47862e1a`
- File-select filter experiments now show the same shared `mode=tile fmt=2 siz=1 wh=296x6 fs=258 tile=7` class is the main visual driver there as well: suppressing it yields `filtered=33` and moves the frame much closer to baseline `off` than baseline `on`
- The dominant file-select-specific hit class, `mode=tile fmt=3 siz=1 wh=16x8 fs=259 tile=7`, is secondary by comparison: suppressing it yields `filtered=44` but only a small pixel shift relative to baseline `on`, which points at a narrower UI/detail contribution
- The coarse mode-level title experiment is now decisive: disabling all tile replacements (`allow_tile=0`) yields `hits=0`, `filtered=178`, and reproduces the baseline `off` title-screen hash exactly, so the current visible hi-res path is fully explained by tile-hit replacement classes rather than some hidden side effect
- The local pack has now been cross-checked against the `v4.0.1` release set, and the active test pack was swapped from the older local candidate (`2018570744` bytes / `15159` entries / `14774f23...`) to `PM64K-NWO401` (`2016964616` bytes / `15168` entries / `ae2030e4...`) with the old payload backed up locally
- That swap produced an unexpectedly strict result on the tracked fixtures: title-screen and file-select `on` captures, semantic state, and hi-res hit/miss telemetry are byte-identical before and after the pack change
- So for the current strict scenes, the remaining misses are not explained by “we were simply on the wrong pack revision”; either both revisions behave the same there, or the unresolved cases sit outside the actual delta between those releases
- The hi-res evidence layer now distinguishes a narrower class than full checksum absence: on the strict file-select bundle, 8 miss events / 7 unique keys are present in the pack under the same low-32 texture CRC but a different palette half
- Those palette-variant misses are concentrated in the smaller CI tile classes, not the dominant block class: `mode=tile fmt=2 siz=1 wh=8x16 fs=258 tile=7` and `mode=tile fmt=2 siz=1 wh=32x16 fs=258 tile=7`
- Runtime debug logs now expose `pal=` and `pcrc=` on hi-res key lines, and the current file-select palette-variant misses all show `pal=0`; the mismatch is therefore not explained by a non-zero palette bank, but by a deeper palette-CRC identity mismatch
- The new CI palette probe has now ruled out the most obvious variants for those file-select misses: changing the inferred entry count, using a legacy aggregate bank-hash scheme, and probing legacy per-bank hash/CRC32 candidates all fail to produce a pack hit while keeping the strict file-select hash stable at `8a90f7874bd797a186ff85d488033dc332b2a75f5bec91ad33ca8246e6be7730`
- The logged candidate palette CRCs for the representative CI misses also do not line up with the active pack's stored high-32 variants for the same low-32 texture CRCs, which makes the remaining likely fault line the TLUT shadow/update semantics rather than one more small hash-formula tweak
- The CI probe is now augmented with low-32 pack-family diagnostics that do not alter lookup behavior:
  - the representative `32x16` file-select family (`low32=2a1be0a4`) is generic-only and dimension-uniform: `2` generic entries, `2` palette variants, `1` replacement-dimension family (`640x160`)
  - the representative ambiguous `8x16` family (`low32=42779bdd`) is also generic-only but much broader: `17` generic entries, `17` palette variants, `3` replacement-dimension families, and no entry matching the current exact palette CRC
  - that split matches the earlier live fallback experiments: `replacement-dims-unique` is directionally reasonable for part of the CI class, while the broader `8x16` family still needs a better discriminator than a permissive low-32 alias
- Two more CI hypotheses are now explicitly ruled out on the same strict file-select fixture without changing the default path:
  - the ambiguous `8x16` miss only samples `19` palette indices across a `0..102` range, and the `32x16` miss samples `53` indices across `0..238`, but hashing only the sparse used-index set still does not produce a pack hit
  - hashing the emulated loaded TLUT words from `tlut_tmem_shadow` also does not produce pack hits for those same misses, whether using the current entry-count view or the sparse used-index view
  - together, those negatives mean the remaining CI gap is probably not one more small palette-CRC formula bug; it is more likely an identity-model mismatch that will need either a constrained compatibility tier or a cleaner imported pack representation
- There is now a dedicated offline pack-family analyzer at [hires_pack_family_report.py](/home/auro/code/parallel-n64/tools/hires_pack_family_report.py), and it confirms the current split on the strict file-select bundle:
  - the representative `32x16` family (`low32=2a1be0a4`) is a plausible constrained compatibility candidate and classifies as `compat-repl-dims-unique`
  - the representative `8x16` family (`low32=42779bdd`) classifies as `ambiguous-import-or-policy`
  - that is the strongest current evidence that the inherited Glide-era pack identity is itself part of the problem, and that an imported internal pack format is now a first-class design path rather than a fallback idea
- There is now a migration-oriented scaffold at [hires_pack_migrate.py](/home/auro/code/parallel-n64/tools/hires_pack_migrate.py) plus a first design note at [HIRES_PACK_IMPORT_MODEL.md](/home/auro/code/parallel-n64/docs/plans/HIRES_PACK_IMPORT_MODEL.md), so legacy-pack import is now a tracked Phase 1 workstream rather than just an open-ended idea
- The migration scaffold now emits the first imported-index format for selected families, separating:
  - imported `records`
  - explicit `compatibility_aliases`
  - `unresolved_families`
- That imported index now also groups compatibility and ambiguous legacy families into explicit dimension-led `variant_groups`, so import-time policy can operate on concrete legacy clusters instead of flat low-32 families
- The first strict file-select imported-index result is now concrete:
  - the constrained `2a1be0a4/fs258` family collapses to one compatibility variant group, `640x160`
  - the ambiguous `42779bdd/fs258` family remains unresolved but is now split into three explicit variant groups, `64x64`, `120x120`, and `144x144`
- Those imported compatibility/unresolved entries now also carry strict-bundle `observed_runtime_context`, including runtime mode, runtime `wh`, observed palette CRC, sparse palette-usage data, and the emulated-TMEM palette view that originally exposed the family
- Those same imported entries now also carry `selector_policy`, so the current import output can already distinguish deterministic compatibility families from unresolved families that still need a manual import decision
- There is now a first explicit import-policy layer at [hires_pack_import_policy.json](/home/auro/code/parallel-n64/tools/hires_pack_import_policy.json), which currently:
  - locks the deterministic `2a1be0a4/fs258 -> 640x160` case
  - records a non-binding `120x120` suggestion for the ambiguous `42779bdd/fs258` family
  - records why `120x120` is currently stronger than `64x64` / `144x144` on the strict file-select evidence
- There is now a first non-committal review path at [hires_pack_review.py](/home/auro/code/parallel-n64/tools/hires_pack_review.py), so strict import slices can be inspected as review artifacts before we treat the imported index as a settled format
- That review path now also ranks candidate variant groups against the current observed runtime context and attached policy, so we can state why one ambiguous candidate looks stronger or weaker without turning that into runtime behavior
- That makes legacy pack transport a real implementation path instead of only a planning statement
- The new block-shape probe is now wired through the tracked file-select scenario and keeps the strict hash intact while logging alternate-shape diagnostics
- That probe has already ruled out the dominant file-select miss as a simple hidden multi-line reinterpretation: `mode=block fmt=2 siz=2 wh=64x1 fs=514 tile=7` stays a plain `64x1` upload (`tmem_stride_words=0`) and finds no alternate-shape pack hit
- The same probe does find alternate-shape hits for smaller non-dominant block misses, including `mode=block fmt=4 siz=2 wh=128x1 fs=516 tile=7 -> 4x32` and `mode=block fmt=0 siz=3 wh=1024x1 fs=768 tile=7 -> 32x32`
- The current TLUT tracking path is correspondingly suspicious: `tlut_shadow` is still populated as a raw contiguous RDRAM copy on `LoadTLUT`, so the next correctness step is to verify whether that shadow actually matches the palette bytes/layout the replacement pack identity expects
- `tlut_shadow` now patches the palette-shadow range by TMEM offset instead of overwriting and zeroing the whole 512-byte shadow on every partial `LoadTLUT`; on the strict file-select fixture that changes the CI palette CRCs materially but does not yet change the final frame or recover new pack hits
- A blunt follow-up experiment, copying TLUT entries into the shadow with a naive 16-bit byte swap, regressed the strict file-select `on` result badly (`hits=48`, `misses=117`, hash `948a4fad87bba561d40cf683915c9d52d6273f1a15017f17885fd1a808a2afdd`), so the remaining issue is not solved by simply swapping palette bytes at the current shadow layer
- The next likely fix boundary is therefore a more exact TMEM/TLUT model for replacement keying rather than one more small palette-CRC tweak: offset/persistence mattered, but exact palette representation still does not match the pack identity
- The CI replacement evidence is now sharper than “palette mismatch exists”: a new low-32 diagnostic index proves the current strict file-select CI misses do have pack-backed candidates when keyed only by the low-32 texture CRC
- That diagnostic result is now validated by live runtime experiments after fixing the scenario env-export bug:
  - `PARALLEL_RDP_HIRES_CI_LOW32_FALLBACK=1` (`unique`) is a narrow real change, not a shell no-op
  - it converts one unique `8x16` CI miss into a hit, moves file-select from `hits=82 misses=83` to `hits=84 misses=81`, and changes the frame hash to `d4661996bc280d4e6a6e1a4fa6dbabeadb47520c4b4b0241f9e2b20f489dcf4e`
  - the pixel delta versus the strict `on` baseline is small (`15946` changed pixels, normalized average channel delta `0.000639`)
  - `PARALLEL_RDP_HIRES_CI_LOW32_FALLBACK=3` (`replacement-dims-unique`) is a tighter middle ground
  - it only accepts low-32 fallback when all candidate pack entries for that low-32 key agree on the replacement dimensions
  - on strict file select it recovers the unambiguous `32x16` class and the single truly unique `8x16` case, moving file-select from `hits=82 misses=83` to `hits=86 misses=79` and changing the frame hash to `24274e62a18c436dc13570b6e51f7dc600b0de89d4aee56086cffd82248f797a`
  - its pixel delta versus the strict `on` baseline sits where it should between `unique` and `any` (`139795` changed pixels, normalized average channel delta `0.005271`)
  - after that tighter rule, the remaining palette-class misses collapse to the still-ambiguous `8x16` family, while the block classes remain unchanged
  - `PARALLEL_RDP_HIRES_CI_LOW32_FALLBACK=2` (`any`) is a much broader real change
  - it converts all current CI tile palette misses on the strict file-select fixture into hits, moves file-select from `hits=82 misses=83` to `hits=90 misses=75`, and changes the frame hash to `2f00a7eb6c0c592a363fca987981d6eb6e6d5a43c9cac0d337c8f444282b18c8`
  - in that broader mode, the remaining unresolved strict file-select misses collapse entirely to the block classes, still dominated by `mode=block fmt=2 siz=2 wh=64x1 fs=514 tile=7`
  - the pixel delta versus the strict `on` baseline is material but still bounded (`166168` changed pixels, normalized average channel delta `0.006020`), which makes it useful as a debug direction even though it is too permissive to treat as production behavior today
- The current Phase 1 question is therefore narrower again:
  - CI low-32 fallback is directionally capable of recovering pack-backed file-select replacements
  - `replacement-dims-unique` is now the first concrete tighter candidate rule worth considering
  - the real remaining design choice is whether that rule is acceptable enough to harden, or whether we still need a better palette-side discriminator for the ambiguous `8x16` family, while separately solving the still-unmatched block classes
- Cross-emulator research now gives the broad guardrails for that decision:
  - the strongest relevant local references are `PCSX2`, `Dolphin`, `PPSSPP`, and `Flycast`
  - the shared pattern is consistent: exact replacement identity remains authoritative, while broader compatibility matching lives in an explicit second tier with separate reporting and tighter constraints
  - `PCSX2` is the clearest conceptual precedent for the current CI work: exact paletted lookup first, then an explicit palette-relaxed retry
  - `Dolphin` strengthens the palette-model side of the argument: palette/TLUT identity should track the actually used palette span rather than a blunt full-shadow view
  - `Flycast` reinforces bank-aware paletted identity, which maps well onto the current N64 CI4/CI8 problem
  - `PPSSPP` reinforces the policy lesson: wildcard/alias-style fallback can exist, but it must remain explicit, constrained, and diagnosable
  - the main design risk from those references is now explicit: hardening `low32_any` as production behavior would repeat the same permissive trap other emulators avoid
  - the main positive direction from those references is also explicit: improve the exact CI/TLUT identity so it matches the effective palette semantics pack authors expect, then keep any broader lookup as a named compatibility tier rather than burying it inside the exact path
  - the block/shape research is equally clear: other emulators do not broadly solve replacement misses with free-form runtime shape reinterpretation, and local N64 docs only justify such reinterpretation when the `LoadBlock` / `LoadTile` transfer semantics prove an equivalent layout
  - that means the current generic block-shape search should remain diagnostic unless a documented `dxt` / interleave / wrap rule can justify turning a specific class into a real compatibility path
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
