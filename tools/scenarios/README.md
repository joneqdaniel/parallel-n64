# Scenario Runners

This directory is for deterministic end-to-end workflows.

The shared runtime contract is documented in [MODEL.md](/home/auro/code/parallel-n64/tools/scenarios/MODEL.md).

Use it for:

- launching RetroArch/core/content with known settings
- loading savestates or replay checkpoints
- capturing frames, screenshots, and logs
- comparing outputs against expected results
- producing small reproducible reports

Do not use it for:

- storing large assets
- game-specific source instrumentation
- permanent research notes

Scenario runners should consume fixture manifests from [`tools/fixtures/`](/home/auro/code/parallel-n64/tools/fixtures) and write generated output to [`artifacts/`](/home/auro/code/parallel-n64/artifacts).

Current tracked scenario seeds:

- [`paper-mario-title-screen.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-title-screen.sh)
- [`paper-mario-title-screen.runtime.env`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-title-screen.runtime.env)
- [`paper-mario-file-select.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-file-select.sh)
- [`paper-mario-file-select.runtime.env`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-file-select.runtime.env)
- [`paper-mario-hos-05-entry-3.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-hos-05-entry-3.sh)
- [`paper-mario-hos-05-entry-3.runtime.env`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-hos-05-entry-3.runtime.env)
- [`remint-paper-mario-file-select-authority.sh`](/home/auro/code/parallel-n64/tools/scenarios/remint-paper-mario-file-select-authority.sh)
- [`remint-paper-mario-hos-05-entry-3-authority.sh`](/home/auro/code/parallel-n64/tools/scenarios/remint-paper-mario-hos-05-entry-3-authority.sh)
- [`stage-paper-mario-savefile.sh`](/home/auro/code/parallel-n64/tools/scenarios/stage-paper-mario-savefile.sh)

Current Paper Mario runtime note:

- save/load command sequences now use log-gated startup readiness and explicit command acknowledgements instead of blind timing where possible
- the tracked title-screen scenario depends on the adapter disabling savestate thumbnails, which removes the current save-state crash seen on the Vulkan HW-frame path
- the tracked title-screen scenario depends on the adapter disabling RetroArch quit confirmation so a single `QUIT` command exits cleanly
- the tracked title-screen and file-select scenarios now use a trustworthy fixture-relative `frame=` clock
- the tracked adapter now normalizes `GET_STATUS` state matching, so scenario waits do not depend on whether RetroArch logs `paused` or `PAUSED`
- tracked Paper Mario scenarios now also use `WAIT_COMMAND_READY`, which proves the RetroArch command channel is alive before load/save commands are issued on the ParaLLEl path
- tracked Paper Mario scenarios now force the intended ParaLLEl/Vulkan path with `PARALLEL_N64_GFX_PLUGIN_OVERRIDE=parallel` and bundle-local core options
- the tracked adapter now supports `WAIT_CORE_MEMORY_HEX`, which lets local scenario flows wait on exact RAM signatures for deterministic probes
- the canonical steady-state Paper Mario workflow is `load savestate -> settle 3 frames -> capture`
- paired `on` runs now also emit machine-readable hi-res capability evidence, including the resolved cache path, the coarse disable reason, and the descriptor-indexing feature bits seen at runtime
- paired `on` runs now also collapse raw hi-res hit/miss/TLUT lines into stable bucket summaries in `traces/hires-evidence.json`, so repeated uncovered classes can be compared across runs without diffing the whole RetroArch log
- the same `hires-evidence.json` trace now also cross-checks miss keys against the active `.hts`/`.htc` index, so bundle evidence can distinguish “unmatched in the local pack index under the current checksum generation” from “lookup present under another formatsize”
- CI palette probe runs now also record `ci_palette_probe.families` in `traces/hires-evidence.json`, so representative CI misses can report whether their low-32 pack family is exact/generic, dimension-uniform, or structurally ambiguous without changing the default lookup path
- the same CI probe now also records `ci_palette_probe.usages` and `ci_palette_probe.emulated_tmem`, so strict bundles can show how many palette indices were actually sampled and whether raw-shadow versus emulated-TMEM palette views produce any pack-backed candidate at all
- for offline pack-format work, use [hires_pack_family_report.py](/home/auro/code/parallel-n64/tools/hires_pack_family_report.py) against a strict bundle and cache path to classify low32 families into constrained-compatibility candidates versus ambiguous/import-required families
- for migration-oriented pack work, use [hires_pack_migrate.py](/home/auro/code/parallel-n64/tools/hires_pack_migrate.py) to turn selected low32 families into a machine-readable import plan grouped by recommended tier
- add `--emit-import-index` to [hires_pack_migrate.py](/home/auro/code/parallel-n64/tools/hires_pack_migrate.py) when you want the imported-index scaffold rather than just the tier report
- that imported-index output now includes explicit `variant_groups` for compatibility aliases and unresolved families, which is the current best offline view of how one ambiguous Glide-era low32 family splits into concrete import-time replacement clusters
- when the imported index is bundle-backed, it also carries `observed_runtime_context` from the strict fixture so import-time policy can reference the exact runtime event, sparse palette usage, and emulated-TMEM palette view that surfaced the family
- the imported index now also emits `selector_policy`, which states whether a family is already deterministic at import time or still needs manual disambiguation and which inputs are available to resolve it
- use [hires_pack_import_policy.json](/home/auro/code/parallel-n64/tools/hires_pack_import_policy.json) with `hires_pack_migrate.py --policy ...` when you want the imported index to carry explicit family decisions or review-required suggestions
- tracked Paper Mario scenarios now also support `RUNTIME_ENV_OVERRIDE` for temporary experimental runs, and `DISABLE_SCREENSHOT_VERIFY=1` when a controlled debug run is expected to diverge from the locked strict hashes
- runtime env files are now auto-exported while sourcing, so temporary `PARALLEL_RDP_*` debug toggles in a `RUNTIME_ENV_OVERRIDE` file actually reach the RetroArch/core child process
- the ParaLLEl runtime path now supports temporary hi-res debug filters through `PARALLEL_RDP_HIRES_FILTER_ALLOW_TILE`, `PARALLEL_RDP_HIRES_FILTER_ALLOW_BLOCK`, and `PARALLEL_RDP_HIRES_FILTER_SIGNATURES`; filtered events are recorded in `traces/hires-evidence.json`
- tracked file-select runs also forward `PARALLEL_RDP_HIRES_BLOCK_SHAPE_PROBE=1` into the ParaLLEl runtime for debug-only block reinterpretation evidence; this keeps the strict screenshot hash locked while logging alternate-shape hits and block upload context
- the current Phase 1 experimental pattern is: keep the strict authority state fixed, suppress one bucket or one mode, and compare the filtered frame against the locked `off` / `on` captures to identify which replacement classes actually drive the visible change
- strict pack-swap experiments should also keep the authority state fixed and relax screenshot verification only long enough to compare the new pack against the locked prior `on` bundle; that workflow has now shown the `PM64K-NWO401` swap is byte-identical to the older local candidate on title and file-select
- the current strict file-select evidence now distinguishes two unresolved classes:
  - the smaller CI tile misses (`8x16` / `32x16`) are present in the pack under the same low-32 texture CRC but a different palette half
  - the dominant `64x1` CI block miss stays absent even under the new block-shape probe, so it is not explained by a simple contiguous reinterpretation like `32x2` or `16x4`
- the current low-32 CI fallback experiments refine that split further:
  - `PARALLEL_RDP_HIRES_CI_LOW32_FALLBACK=1` is a narrow real change and recovers one unique `8x16` case on strict file select
  - `PARALLEL_RDP_HIRES_CI_LOW32_FALLBACK=3` is a tighter middle-ground experiment that only accepts low-32 fallback when all candidate pack entries agree on replacement dimensions; on strict file select it recovers the unambiguous `32x16` class and the single truly unique `8x16` case
  - `PARALLEL_RDP_HIRES_CI_LOW32_FALLBACK=2` recovers the current CI tile palette-class misses broadly on strict file select, leaving only the block classes unresolved
  - these are debug-only direction-finding experiments, not accepted runtime policy
- the new CI family probe explains why those fallback results split the way they do:
  - the representative `32x16` family is generic-only but dimension-uniform (`2` generic entries, `1` replacement-dimension family), which matches the success of `replacement-dims-unique`
  - the representative `8x16` family is generic-only and structurally broad (`17` generic entries across `3` replacement-dimension families), which is exactly the kind of case that should stay out of the default path until a better discriminator exists
- the newer negative probe results narrow the next design step further:
  - hashing only the sparse set of actually used palette indices does not produce pack hits for the remaining ambiguous CI misses
  - hashing the emulated loaded TLUT words from `tlut_tmem_shadow` also does not produce pack hits for those misses
  - so the remaining CI gap is likely an identity-model mismatch, not just a raw-shadow-versus-TMEM or used-range-versus-sparse-index bug
- the tracked Paper Mario semantic trace currently uses an empirical vanilla `gGameStatus` slice at `0x800740aa`; it now records a raw window SHA-256, empirical phase guess for proven authority states, and decomp-backed `map_name_candidate` values for KMR/HOS/OSR area-local map indices, but it is not yet a full scene-name/mode decoder
- tracked title-screen and file-select runs now also snapshot symbol-backed vanilla `CurGameMode` and map-transition globals, so each authority bundle records callback-phase evidence in addition to the `gGameStatus` window
- the corrected Paper Mario title-screen authority now reports `state_init_title_screen` / `state_step_title_screen` and captures to `42e501afb2548a5067bc034578c5bcebf0bf2a40f612bbcc94972af716ad6ff2`
- the corrected Paper Mario file-select authority now reports `state_init_file_select` / `state_step_file_select` and captures to `6fa8688b382fa1e6f0323f054861a85f593d2d47ca737bb78448e3f268ca63e3`
- the verified title remint path is `boot -> wait 20s -> START once -> wait 5s -> save`
- the verified file-select remint path is `load title state -> settle 3 -> hold START for 60 frames -> advance to frame 303 -> save`
- `SAVE_STATE` is asynchronous in RetroArch; tracked authority minting now requires `WAIT_SAVE_STATE`, and save steps should happen before screenshot tasks to avoid task-queue contention
- the current `on`-mode result on this machine now reaches a real active provider path: the pack loads, the provider turns `on`, and bundles record real hit/miss telemetry
- the current `on`-mode result is now visibly active as well: tracked title/file-select `on` bundles no longer match `off` at the raw-pixel level while still preserving the same semantic callback state
- the tracked title-screen and file-select scenarios now carry known-good `off` and `on` screenshot hashes, so both sides of the first strict Phase 1 targets can be verified automatically
- the current Phase 1 question is no longer “is the path live”; it is “is the visible result correct, or is it corrupted”
- raw `gGameStatus` button-array snapshots are not currently a trustworthy input-delivery metric; they stay zero even in later title-screen authority probes where `START` clearly changes behavior
- Paper Mario decomp research shows `LOAD_FROM_FILE_SELECT` is handled specially in `kmr_02`, so deeper startup-to-world probes should not treat the first `area/map/entry` tuple as canonical scene identity without more evidence
- tracked runtime scenarios now isolate save RAM inside each bundle via `savefile_directory`, even when no explicit `.srm` is staged
- a local Paper Mario `.srm` can be intentionally copied into gitignored assets with `stage-paper-mario-savefile.sh` for future deeper fixtures
- controller scripts remain in the repo as bootstrap paths for minting or replacing authoritative savestates
- the file-select remint helper intentionally rebuilds the authoritative state from the bootstrap path and verifies it against the canonical capture hash
- planned ladder steps should still get scenario and remint-script stubs so future work extends the model instead of bypassing it
