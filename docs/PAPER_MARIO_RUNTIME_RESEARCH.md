# Paper Mario Runtime Research

This note holds supplemental Paper Mario probe history, deferred seam evidence, and offline tooling guidance that no longer belongs in the operational scenario index.

Use the controlling docs for current policy and promotion status:

- [Hi-Res Runtime Primary Plan](/home/auro/code/parallel-n64/docs/plans/hires_runtime_primary_plan.md)
- [Project State](/home/auro/code/parallel-n64/docs/PROJECT_STATE.md)
- [EMU_TESTING.md](/home/auro/code/parallel-n64/docs/EMU_TESTING.md)

Treat this document as a research notebook, not as plan authority.

## Quick Map

- Use [tools/scenarios/README.md](/home/auro/code/parallel-n64/tools/scenarios/README.md) for maintained runner entrypoints and current authority lanes.
- Use this note when you need:
  - historical file-select and title-timeout probe context
  - the current rationale for deferred seams
  - offline pack-review workflow reminders
  - debug-only runtime flag references
- The most important still-active research conclusions are:
  - file-select deeper-state work is still menu-bound
  - title-timeout remains the best no-save deeper-state probe
  - `64x1 fs514` still looks like authored-surface/block transport work, not transient strip noise
  - `8x16 fs258` still looks like sampled-object/subrect transport work, not row-byte reinterpretation
  - source-backed triangle promotion, `1b8530fb` pool semantics, and second-game breadth are still deferred

## Current Research Boundaries

- The maintained default Paper Mario runtime lane is the promoted enriched full-cache `PHRB` baseline.
- The maintained fallback front door is the zero-context compat-only full-cache refresh lane.
- The maintained review-only reduction lane is the tracked authority-context overlay profile.
- Source-backed triangle promotion, `1b8530fb` pool semantics, and second-game breadth remain deferred.

## File-Select Probe History

- The current file-select input-probe path is [`paper-mario-file-select-input-probe.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-file-select-input-probe.sh).
- The savefile-backed deep branch is reproducible but still menu-bound:
  - staging the local `.srm`, holding `START` for `120` frames, and settling to `frame=423` lands on screenshot hash `89cb1bddd5c2dd2a62b063210af11c2324eca04d3060e746042edc0323b00e8e`
  - semantics stay in `state_init_file_select` / `state_step_file_select` with `entryID=11`
- A no-input control run back out to `frame=423` from the authoritative file-select state reproduces the canonical file-select hash `6fa8688b382fa1e6f0323f054861a85f593d2d47ca737bb78448e3f268ca63e3`, so the deeper branch is input-caused rather than a pure settle-time effect.
- One-frame `START` and `A` pulses are not no-ops under the current savefile-backed setup. With the current settle, both collapse to the same first deeper branch.
- The current post-handoff branch ladder is:
  - authority + no input -> `6fa8688b382fa1e6f0323f054861a85f593d2d47ca737bb78448e3f268ca63e3`
  - authority + `START` -> `89cb1bddd5c2dd2a62b063210af11c2324eca04d3060e746042edc0323b00e8e`
  - authority + `A` -> `89cb1bddd5c2dd2a62b063210af11c2324eca04d3060e746042edc0323b00e8e`
  - `START x120 -> A` -> `674bbf51ab0c985d16088aedd373d2bd7d3d8fdc5f1e12020858f322e7073732`
  - `START x120 -> A -> A` -> `fece26f3ac694b9cbf9c395c10a4cb0543499cdc8eb2aa9beaacb896c2acd1ad`
  - `START x120 -> START -> START` -> `86d3d0a9f7db600bdc0f0f4b8ec29d9c7ff1418a7e7c7ac346dc9a710c2dd3a7`
- All of those branches still remain in `state_init_file_select` / `state_step_file_select` and still read `filemenu_currentMenu = FILE_MENU_MAIN`.
- The strongest current discriminator for the hidden `authority + A` branch is now window-state evidence rather than top-level menu predicates:
  - authority state:
    - `WIN_FILES_TITLE.fp_update = filemenu_update_show_title`
    - `WIN_FILES_SLOT2_BODY.fp_update = filemenu_update_show_options_right`
  - hidden `authority + A` branch:
    - `WIN_FILES_TITLE.fp_update = filemenu_update_hidden_with_rotation`
    - `WIN_FILES_SLOT2_BODY.fp_update = filemenu_update_hidden_with_rotation`
    - `WIN_FILES_INPUT_FIELD.fp_update = filemenu_update_show_name_input`
    - `WIN_FILES_INPUT_KEYBOARD.fp_update = filemenu_update_show_name_input`
- Practical conclusion: the first deeper `authority + A` branch is create-file / name-input flow, not confirm/start flow.
- The local Paper Mario `.srm` is still low-confidence for populated-slot testing:
  - even the cold-boot save-backed file-select remint still verifies `selected_slot_has_data = false`
  - use it as research input only, not as a correctness dependency

## Title-Timeout And Deeper-State Probes

- The strongest current non-save deeper-state path is [`paper-mario-title-timeout-probe.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-title-timeout-probe.sh).
- Current observed checkpoints:
  - `900` frames -> `state_init_enter_demo` / `state_step_enter_world`
  - `960` frames -> `state_init_world` / `state_step_world`, `kmr_03`, `entry 5`
  - `1200` frames -> `state_init_battle` / `state_step_battle`, `kmr_03`, `entry 0`
  - `1500` frames -> `state_init_world` / `state_step_world`, `kmr_06`, `entry 3`
- This remains the preferred path for widening Paper Mario hi-res evidence beyond menu-heavy states without save-data dependency.
- [`paper-mario-kmr-03-entry-5.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-kmr-03-entry-5.sh) is the corresponding savestate-backed steady-state authority fixture.
- The canonical savestate-backed `off` hash for that fixture is `04ea11ae5d0bd5b64d79851d88e406f3167454a5033630396e6fc492f60052d5`.

## Draw-Class And Family Findings

- Strict Paper Mario bundles now carry machine-readable hi-res capability evidence, descriptor-path counts, provenance summaries, draw usage, sampler usage, and family probes in `traces/hires-evidence.json`.
- Early strict-fixture hi-res traffic is overwhelmingly texrect/copy-mode driven rather than broad textured-triangle traffic.
- The dominant visible strict-fixture missing-texture work split remains:
  - `64x1 fs514` block family
  - smaller ambiguous `8x16 fs258` CI family
- Block-family probe result for `64x1 fs514`:
  - `21` unique addresses
  - dominant address delta `0x80`, matching the observed `128`-byte row span
  - no exact duplicate row payloads
  - zero-padded row envelope with active bytes concentrated roughly in `0x18..0x6b`
  - practical implication: repeated row slices from a larger authored surface or sheet are more plausible than transient strip noise
- Tile-family probe result for active `8x16 fs258`:
  - `5` unique addresses and `5` unique low32 keys
  - no address delta matches the observed `8`-byte row size
  - every captured `8`-byte row at those addresses is all-zero
  - parent-surface checks show same-start `16x16 CI4` candidates reproduce the active low32 families, while shifted starts do not
  - practical implication: this gap is better modeled as sampled-object/subrect transport than row-byte reinterpretation

## CI Palette And Identity Findings

- CI palette probe runs now record family, usage, emulated-TMEM, and logical-view summaries in `traces/hires-evidence.json`.
- The first strict logical-view probe produced a useful negative result:
  - ambiguous `8x16` CI families get distinct logical CRCs when `tlut_type` flips
  - neither logical view hits the current pack on that fixture
- Narrow CI fallback experiments showed:
  - `PARALLEL_RDP_HIRES_CI_LOW32_FALLBACK=1` recovers one unique `8x16` case
  - `PARALLEL_RDP_HIRES_CI_LOW32_FALLBACK=3` recovers the unambiguous `32x16` class and the one truly unique `8x16` case
  - `PARALLEL_RDP_HIRES_CI_LOW32_FALLBACK=2` recovers the current CI tile palette-class misses broadly, leaving block classes unresolved
- These remain direction-finding experiments, not accepted runtime policy.
- The current bounded CI compatibility-tier candidate is `PARALLEL_RDP_HIRES_CI_COMPAT=3`, which applies the same `replacement-dims-unique` rule as an opt-in runtime compatibility path after exact CI lookup misses.
- Practical conclusion: the remaining CI gap still looks like an identity-model mismatch, not just a raw-shadow-vs-TMEM or used-range-vs-sparse-index bug.

## Selected-Package And Deferred Seam Research

- The selected-package timeout validation lane is the main shallow review surface for deeper `PHRB` work.
- When review inputs are present it emits selector review, pool review, pool-regression review, seam-register, alternate-source review, cross-scene review, and joined activation review artifacts.
- Current deferred seam status:
  - `1b8530fb`: still `defer-runtime-pool-semantics` with `keep-flat-runtime-binding`
  - triangle source-backed families `91887078`, `6af0d9ca`, and `e0d4d0dc`: still review-only and blocked from promotion
  - `7701ac09`: offline dedupe and broader asset aliasing are proven review-only package-shaping tools, not default behavior
- The `91887078` zero-selector singleton remains useful evidence but not safe to promote:
  - it converts `10296` timeout misses into exact hits at `960`
  - the gameplay frame stays byte-identical
  - selected-package title and file-select authorities change heavily
  - `kmr_03 ENTRY_5` stays unchanged
- The tracked review-only reduction lane is currently driven by:
  - [hires_runtime_overlay_review_profile.json](/home/auro/code/parallel-n64/tools/hires_runtime_overlay_review_profile.json)
  - [hires_runtime_overlay_review_transport_policy.json](/home/auro/code/parallel-n64/tools/hires_runtime_overlay_review_transport_policy.json)
  - [hires_canonical_family_selection_review.json](/home/auro/code/parallel-n64/tools/hires_canonical_family_selection_review.json)
- The current persistent proof is [hts2phrb-report.json](/home/auro/code/parallel-n64/artifacts/hts2phrb-review/20260409-pm64-all-families-authority-context-overlay-review-profile/hts2phrb-report.json):
  - `19` bindings
  - `9` unresolved
  - `302` canonical-only families
  - `75` canonical-only review groups
  - `66` tracked review selections

## Review-Only Package Shaping

- The current tracked reduction inputs are:
  - [hires_runtime_overlay_review_profile.json](/home/auro/code/parallel-n64/tools/hires_runtime_overlay_review_profile.json)
  - [hires_runtime_overlay_review_transport_policy.json](/home/auro/code/parallel-n64/tools/hires_runtime_overlay_review_transport_policy.json)
  - [hires_canonical_family_selection_review.json](/home/auro/code/parallel-n64/tools/hires_canonical_family_selection_review.json)
- Current persistent proof remains [hts2phrb-report.json](/home/auro/code/parallel-n64/artifacts/hts2phrb-review/20260409-pm64-all-families-authority-context-overlay-review-profile/hts2phrb-report.json):
  - `19` bindings
  - `9` unresolved
  - `302` canonical-only families
  - `75` canonical-only review groups
  - `66` tracked review selections
- This lane is useful for bounded converter reduction work, but it is still explicitly non-default.

## Offline Tooling References

- Family classification:
  - [hires_pack_family_report.py](/home/auro/code/parallel-n64/tools/hires_pack_family_report.py) classifies low32 families from a strict bundle and cache path.
  - [hires_pack_migrate.py](/home/auro/code/parallel-n64/tools/hires_pack_migrate.py) emits migration-oriented import plans or imported-index scaffolds.
  - [hires_pack_review.py](/home/auro/code/parallel-n64/tools/hires_pack_review.py) generates review artifacts without treating the imported index as a final format commitment.
- Review subsets and comparisons:
  - [hires_pack_emit_subset.py](/home/auro/code/parallel-n64/tools/hires_pack_emit_subset.py) materializes imported review subsets.
  - [hires_pack_compare_subsets.py](/home/auro/code/parallel-n64/tools/hires_pack_compare_subsets.py) compares several review-only subset artifacts side by side.
- Proxy and selected-package review:
  - [hires_proxy_candidate_review.py](/home/auro/code/parallel-n64/tools/hires_proxy_candidate_review.py) joins runtime bundle distance, exact-hit context, and transported asset similarity.
  - [hires_pack_build_package.py](/home/auro/code/parallel-n64/tools/hires_pack_build_package.py) emits a loader manifest, materialized package, and final `PHRB` from selected bindings.
  - [hires_pack_build_selected_package.py](/home/auro/code/parallel-n64/tools/hires_pack_build_selected_package.py) is the policy-driven selected-package build path, including `--review-profile`.
- Generic legacy-pack front door:
  - [hts2phrb.py](/home/auro/code/parallel-n64/tools/hts2phrb.py) is the generic legacy-pack front door.
  - Important behavior:
    - zero-config `--cache <pack>` defaults to all-family inventory mode
    - accepts bundle directories, `traces/hires-evidence.json`, and `validation-summary.{json,md}`
    - accepts repeatable `--context-bundle` inputs as enrichment-only context
    - always emits canonical loader/package output
    - can apply review-only duplicate, alias, and review-profile shaping
    - emits runtime-overlay artifacts only when overlay building is enabled and deterministic bindings exist, unless overlay is forced
    - emits `PHRB` v7 with explicit runtime-ready flags, 64-bit blob offsets, and preserved payload format metadata
    - stores legacy payload blobs directly and streams binary package emission from the legacy cache
    - supports `--runtime-overlay-mode {auto,always,never}`, `--minimum-outcome`, `--require-promotable`, `--max-total-ms`, and `--max-binary-package-bytes`

## Experimental Overrides And Debug Flags

- Use `RUNTIME_ENV_OVERRIDE` for temporary experiments; runtime env files are auto-exported while sourcing.
- Use `DISABLE_SCREENSHOT_VERIFY=1` only when controlled experiments are expected to diverge from locked strict hashes.
- Prefer the real `PARALLEL_RDP_HIRES_FILTER_*` names; `HIRES_FILTER_*` remains compatibility fallback only.
- Current verified filter isolation:
  - file select `allow_block=0` is a no-op and preserves the locked `on` hash
  - file select `allow_tile=0` collapses to the `off` hash
  - title screen `allow_tile=0` also collapses to the `off` hash
  - practical implication: the current visible hi-res path on those strict fixtures is tile-only
- `PARALLEL_RDP_HIRES_BLOCK_SHAPE_PROBE=1` is available for debug-only block reinterpretation evidence.
- `PARALLEL_RDP_HIRES_CI_SELECT=low32:formatsize:widthxheight[;...]` is the debug-only imported-selector preview path for ambiguous CI families.

## Related References

- [PAPER_MARIO_SIGNAL_TABLE.md](/home/auro/code/parallel-n64/docs/plans/PAPER_MARIO_SIGNAL_TABLE.md)
- [tools/scenarios/README.md](/home/auro/code/parallel-n64/tools/scenarios/README.md)
- [tests/emulator_behavior](/home/auro/code/parallel-n64/tests/emulator_behavior)
