# Project State

## Mission

- Build a stable hi-res texture replacement and scaling path for the ParaLLEl video core.
- Keep `feature off` aligned with baseline behavior and N64 parity goals.
- Keep debugging, validation, and promotion agent-first and reproducible.

## Current Status

- The repo is in the Phase 1 runtime/package shift inside the Phase 0/1 backbone.
- The controlling execution document is [Hi-Res Runtime Primary Plan](/home/auro/code/parallel-n64/docs/plans/hires_runtime_primary_plan.md).
- Implementation is active against that plan, not just staged for it.
- Paper Mario remains the primary authority game.
- SM64 is the first validated cross-game proof (GlideN64-compat CRC, PHRB pipeline end-to-end).

### Current Paper Mario Runtime Lanes

- Promoted enriched full-cache `PHRB` baseline:
  - default authority path and current default conformance baseline
  - enrichment via `--context-dir` automatic discovery (103 expanded bundles from local artifact tree)
  - current converter state: `368` canonical-only families, `143` native sampled / `8487` compat runtime-ready
  - current runtime-overlay state: `97` bindings / `46` unresolved overlay families
- Zero-config compat-only full-cache `PHRB` fallback:
  - maintained only through explicit override or the dedicated zero-config refresh lane
  - current converter state: `8620` runtime-ready compat records and `372` deferred compat records
- Tracked review-only reduction lane:
  - current best converter-side ambiguity reduction proof, explicitly non-default
  - current converter state: `302` canonical-only families in `75` grouped reviews
  - current review-only shaping state: `66` tracked review selections and `19` bindings / `9` unresolved overlay families

### Runtime Contract State

- The provider now preserves structured `PHRB` identity at load time instead of discarding it.
- Generic descriptor resolution, upload-time resolution, and CI low32 compat materialization now run through shared provider-owned typed resolution helpers instead of separate renderer fallback ladders.
- The renderer keeps native sampled identity alive further into cache and decode paths instead of collapsing immediately back to checksum-shaped handling.
- The selected-package `960` timeout lane is now a real native-runtime proof:
  - `source_mode=phrb-only`
  - `descriptor_paths(sampled=66 native_checksum=0 generic=0 compat=0)`
  - current proof: [validation-summary.md](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-selected-package-timeout-current-contract/validation-summary.md)
- The default Paper Mario authority fixtures now resolve only through promoted enriched full-cache `PHRB` artifacts by default and fail closed if no promoted enriched artifact exists.
- The upload-path resolution cascade now includes a sampled-exact-selector step between the singleton-family check and the checksum fallback.
- The PHRB self-test now validates the sampled index instead of the checksum index.
- `.phrb` is the only runtime format. HTS/HTC loading, CacheSourcePolicy, and source-mode core options have been removed from the runtime. Legacy formats are import-only via `hts2phrb`.
- GlideN64-compat draw-time CRC is auto-enabled when loaded PHRB contains compat entries (`has_compat_entries()`), with no source-mode gating required.
- The dead generic checksum-only descriptor path (`resolve_hires_replacement_descriptor`) has been removed.
- The authority refresh now uses `--context-dir` to automatically discover all local validation summaries as enrichment sources.
- Current default authority outcome:
  - `source_mode=phrb-only`
  - `entry_count=12909`
  - `native_sampled_entry_count=651`
  - sampled-only descriptor traffic on title screen, file select, and `kmr_03 ENTRY_5`
  - native-checksum-exact-upload entries resolve geometry-mismatched families (not a code gap)

### Converter State

- `hts2phrb` is now canonical-package-first rather than binding-first.
- The front door now supports:
  - zero-config `--cache <pack>`
  - bundle and validation-summary inputs
  - enrichment-only `--context-bundle`
  - recursive enrichment discovery `--context-dir`
  - explicit runtime-class gates
  - `--reuse-existing`
  - review-only duplicate / alias / review-profile overlays
  - canonical loader/package emission plus optional runtime overlay
- The current local full-cache Paper Mario front-door outcomes are:
  - zero-context: `partial-runtime-package`, compat-only
  - authority-context: `partial-runtime-package`, mixed-native-and-compat
- Local converter breadth currently covers:
  - the current Paper Mario legacy cache (Rice CRC, old format `0x40a20000`)
  - the repo-local pre-v401 Paper Mario legacy cache (Rice CRC, old format)
  - SM64 Reloaded v2.6.0 HD (Rice CRC, GlideN64 format `0x08000000`, 2530 entries)
  - OoT Reloaded v11.0.0 HD (Rice CRC, GlideN64 format `0x08000000`, 43267 entries)

### Cross-Game Runtime State

- **SM64 Reloaded** — validated cross-game proof with boot conformance test:
  - HTS → `hts2phrb` → PHRB: 2530/2530 entries, `promotable-runtime-package`, zero unresolved, 1.5s conversion
  - PHRB → runtime: 6,599 compat draw-time hits in 30s title screen boot
  - Format coverage: RGBA (fmt=0) and IA (fmt=3) both hitting; no CI textures in SM64 pack
  - GlideN64-compat CRC auto-enabled from loaded PHRB compat entries
  - Automated boot conformance test: `emu.conformance.sm64_hires_boot`
- **OoT Reloaded** — validated cross-game proof with boot conformance test:
  - HTS → `hts2phrb` → PHRB: 43,266/43,267 entries, `partial-runtime-package`, 1 ambiguous family (`a388567b:fs258`)
  - PHRB is 8.9GB; streaming load reads only metadata (~13.5MB), textures loaded on demand via file seek
  - PHRB → runtime: 43,322 entries loaded, 46,751 compat draw-time hits in 45s boot
  - CI palette CRC validated: 11,455 CI hits out of 23,368 CI attempts (49% hit rate; misses are pack coverage, not CRC mismatch)
  - GPU budget/eviction available via `PARALLEL_RDP_HIRES_GPU_BUDGET_MB` env var (default unlimited)
  - Automated boot conformance test: `emu.conformance.oot_hires_boot` (asserts CI hits > 0)
- **GlideN64-compat RDRAM CRC**:
  - Root cause was parameter mismatch: our upload path computes Rice CRC with SetTextureImage params at load time; GlideN64 uses tile descriptor params at draw time
  - Draw-time fallback recomputes CRC using tile line stride, SetTileSize dimensions, and tile descriptor size enum
  - Auto-enabled when loaded PHRB contains compat entries (`has_compat_entries()`); `PARALLEL_RDP_HIRES_GLIDEN64_COMPAT_CRC=1` env var remains as debug override
  - Does not fire for packs with only native sampled entries — prevents false-positive CRC32 collisions on TMEM-keyed packs
  - CI palette CRC validated empirically on OoT (matching GlideN64's `checksum64 = (palette_crc << 32) | texture_crc`)

### Validation State

- Active strict fixtures:
  - title screen
  - file select
  - `kmr_03 ENTRY_5`
- Active runtime-conformance lanes:
  - full-cache enriched authority validation
  - full-cache zero-config refresh validation
  - selected-package authority validation
  - selected-package timeout validation
  - selected-package timeout lookup-without-probe validation
  - SM64 hi-res boot conformance (provider=on, compat_draw_hits > 0)
  - OoT hi-res boot conformance (entries > 40K, CI hits > 0)
- Semantic hi-res evidence now participates in pass/fail on the active authorities.
- The title-timeout lane remains the main no-save deeper-state review surface.

### Deferred / Open Gaps

- Broaden structured sampled-object lookup further across runtime without reopening deferred pool/source seams prematurely.
- Reduce the remaining converter canonical-only residue (`302` families / `75` groups on the tracked review-only lane).
- Reduce the remaining review-only overlay residue (`9` unresolved on the tracked review-only lane).
- Keep `.phrb` authoritative while legacy formats remain explicit input/refresh paths.
- Keep these items deferred until the core gap is smaller:
  - `1b8530fb` runtime pool semantics
  - source-backed triangle promotion
  - auto-conversion

## Historical Context

- The long Paper Mario probe chronology, ordered-surface bridge history, selected-package milestone trail, deferred seam evidence, and offline review workflows now live in [PAPER_MARIO_RUNTIME_RESEARCH.md](/home/auro/code/parallel-n64/docs/PAPER_MARIO_RUNTIME_RESEARCH.md).
- Use that note when you need:
  - file-select probe history
  - title-timeout milestone history
  - block/tile/CI family research notes
  - older selected-package and title-surface bridge milestones
  - detailed offline `hires_pack_*` and `hts2phrb` research workflows

## Locked Planning Backbone

1. Phase 0: agent-first tooling, fixtures, evidence bundles, deterministic control
2. Phase 1: hi-res replacement without corruption
3. Phase 2: scaling and sharpness work

## Current Planning Focus

- Keep the promoted enriched full-cache `PHRB` baseline green for title screen, file select, and `kmr_03 ENTRY_5`.
- Continue provider-owned runtime-contract tightening and remove remaining checksum-shaped seams.
- Continue reducing `hts2phrb` canonical-only ambiguity and overlay residue through bounded review-only policy.
- Keep the zero-config compat-only fallback lane and the tracked review-only reduction lane explicit instead of conflating them with the promoted baseline.
- Leave pool semantics, source-backed triangle promotion, auto-conversion, and second-game breadth deferred until the core runtime/converter gap narrows further.
- Supporting planning docs still matter, but [Hi-Res Runtime Primary Plan](/home/auro/code/parallel-n64/docs/plans/hires_runtime_primary_plan.md) wins on sequencing and promotion order.

## Current Validation Scope

- Paper Mario: primary authority game with strict conformance fixtures.
- SM64: validated cross-game proof with automated boot conformance test.
- OoT: validated cross-game proof with automated boot conformance test (streaming load, CI palette CRC).
- First strict Phase 1 fixtures:
  - title screen
  - file select
  - `kmr_03 ENTRY_5`

## Paper Mario Fixture Ladder Status

- active: title screen
- active: file select main menu
- active: `kmr_03 ENTRY_5`
- planned: `hos_05 ENTRY_3`
- planned: `osr_00 ENTRY_3`
- planned: pause stats/items

## Locked Decisions

- Savestates are the authority once available.
- Debug warps and scripted entry are acceptable before authoritative savestates exist.
- Fixture identity is locked to manifest, ROM identity, savestate identity, config snapshot, and expected capture points.
- Evidence bundles are required.
- Evidence bundles include final output plus lightweight intermediate evidence.
- Fallbacks and exclusions must report explicit reasons.
- `papermario-dx` is optional debug help, not the final correctness authority.
- Runtime asset support starts with the current Paper Mario pack.
- Preprocessing/import into a cleaner internal representation is allowed if it improves correctness and debugging.

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

- Classify issues using all available evidence: output, traces, logs, telemetry, fixture identity, and config state.
