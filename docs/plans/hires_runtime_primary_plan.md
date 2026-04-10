# Hi-Res Runtime Primary Plan

## Why This Exists

- The repo now has a viable hi-res direction, but the remaining risk is drift: converter convenience, Paper Mario-specific evidence, or compatibility heuristics taking over the architecture.
- This document keeps the sequence fixed: native-first `PHRB` runtime contract first, bounded compatibility second, broader validation after the core seam is cleaner.
- This is a control document, not a probe notebook. Live counts, artifact snapshots, and historical evidence belong in [`docs/PROJECT_STATE.md`](/home/auro/code/parallel-n64/docs/PROJECT_STATE.md) and [`docs/PAPER_MARIO_RUNTIME_RESEARCH.md`](/home/auro/code/parallel-n64/docs/PAPER_MARIO_RUNTIME_RESEARCH.md).

## Short Verdict

- Keep the current direction.
- Keep `PHRB` as the runtime target and `hts2phrb` as the legacy front door.
- Keep compatibility work explicit and fenced.
- Keep Paper Mario as the current authority game, but do not let Paper Mario-specific seams define the architecture.

## Plan Authority

- This is the controlling execution plan for the hi-res runtime and package work.
- If another doc disagrees on sequencing or architectural priority, this document wins.
- Supporting roles:
  - [`docs/PROJECT_STATE.md`](/home/auro/code/parallel-n64/docs/PROJECT_STATE.md): current status, live lane state, current blocker counts
  - [`docs/PAPER_MARIO_RUNTIME_RESEARCH.md`](/home/auro/code/parallel-n64/docs/PAPER_MARIO_RUNTIME_RESEARCH.md): probe history, deferred seam evidence, review-only shaping history
  - [`docs/plans/PHASE_OVERVIEW.md`](/home/auro/code/parallel-n64/docs/plans/PHASE_OVERVIEW.md): short repo-facing phase map

## Repo Integration Requirements

- Repo entrypoints must present this as the active plan:
  - [`README.md`](/home/auro/code/parallel-n64/README.md)
  - [`AGENTS.md`](/home/auro/code/parallel-n64/AGENTS.md)
  - [`docs/README.md`](/home/auro/code/parallel-n64/docs/README.md)
  - [`docs/plans/README.md`](/home/auro/code/parallel-n64/docs/plans/README.md)
  - [`docs/plans/PHASE_OVERVIEW.md`](/home/auro/code/parallel-n64/docs/plans/PHASE_OVERVIEW.md)
  - [`docs/PROJECT_STATE.md`](/home/auro/code/parallel-n64/docs/PROJECT_STATE.md)
- Historical and research docs may stay, but they should not compete with this plan for authority.
- User-facing repo story must stay coherent:
  - runtime target: `PHRB`
  - legacy import path: `.hts` / `.htc`
  - public front door: `hts2phrb`
  - auto-conversion only after promotion gates

## Current Assessment

### What Is Working

- `PHRB` is now a real runtime path, not just a speculative target.
- The provider preserves structured native identity and now owns more of the resolution contract.
- The Paper Mario authority set is no longer legacy-first by default.
- `hts2phrb` is a real canonical-package-first front door with direct tests and operational gates.
- Bounded compatibility investigations have been classified instead of left open-ended.

### What Is Still Wrong

- Structured sampled-object identity is not yet the primary runtime key across the full renderer.
- Some checksum-shaped runtime seams still remain.
- `.phrb` is not yet the only production runtime source repo-wide.
- Converter ambiguity and overlay residue are reduced, but not eliminated.
- Cross-game breadth is still missing.

## Current Implementation State

### Completed Slices

- Validation trust is live on the active Paper Mario authority fixtures.
- Provider/runtime preservation work is live:
  - structured `PHRB` identity survives load
  - native sampled records and compat families are separated
  - typed provider-owned resolution results now cover the main generic, upload, sampled, and CI compat seams that were previously open-coded in the renderer
- Runtime lane shape is explicit:
  - promoted enriched full-cache `PHRB` baseline
  - zero-config compat-only fallback
  - tracked review-only reduction lane
- `hts2phrb` is canonical-package-first, operationally gated, and reproducible for the local Paper Mario legacy packs.
- CI palette parity and simple `LoadBlock` retry are classified and no longer count as open architecture drivers.

### Still Open

- Broaden structured sampled-object lookup beyond the current bounded seams.
- Finish replacing checksum-shaped primary lookup with structured runtime identity.
- Make `.phrb` the only production runtime source.
- Preserve ordered-surface runtime identity cleanly.
- Reduce converter canonical-only ambiguity and overlay residue further.
- Add non-Paper-Mario converter breadth once a local legacy pack exists.
- Start second-game validation only after the runtime/converter picture is cleaner.

### Where Live State Lives

- Use [`docs/PROJECT_STATE.md`](/home/auro/code/parallel-n64/docs/PROJECT_STATE.md) for current lane counts, current authority status, and current converter residue.
- Use [`docs/PAPER_MARIO_RUNTIME_RESEARCH.md`](/home/auro/code/parallel-n64/docs/PAPER_MARIO_RUNTIME_RESEARCH.md) for historical artifact chains, deferred seam evidence, and review-only package shaping details.

## Deferred Work Register

The following work is intentionally deferred and must stay explicit until promoted or rejected:

- Source-backed triangle promotion for `91887078`, `6af0d9ca`, and `e0d4d0dc`
- `1b8530fb` pool-preserving runtime semantics
- Promotion of `7701ac09` review-only dedupe and alias shaping into the canonical selected-package build
- Repo-wide auto-conversion from legacy packs to cached `PHRB`
- Second-game validation and generality claims

## Core Decision

The project should continue on the current imported-format and sampled-object path, with this order:

1. Make the native package contract authoritative at runtime.
2. Keep compatibility logic explicit and secondary.
3. Continue reducing converter ambiguity without inventing new runtime heuristics.
4. Broaden validation only after the runtime and converter picture is clearer.
5. Treat legacy formats as import inputs, not long-term runtime formats.

The project should not spend the next cycle on:

- more selector heuristics
- more bridge machinery as the primary path
- runtime lookup-mode matrices
- `.hts` / `.htc` as long-term runtime formats

## Execution Order

1. Keep the promoted enriched full-cache `PHRB` baseline green across title screen, file select, and `kmr_03 ENTRY_5`.
2. Continue provider-owned runtime-contract tightening and remove remaining checksum-shaped seams where direct tests exist.
3. Continue strengthening `hts2phrb` as the common-case front door without letting converter convenience outrun the runtime contract.
4. Reduce canonical-only ambiguity and overlay residue through bounded review-only policy instead of new runtime heuristics.
5. Keep the zero-config compat-only lane and the tracked review-only reduction lane explicit and non-default while those reductions remain unpromoted.
6. Return to deferred pool and source-backed seams only after the runtime/converter gap is narrower.
7. Start second-game validation only after the Paper Mario breadth and runtime-contract gates are materially cleaner.

## Immediate Priorities

1. Keep the promoted enriched full-cache `PHRB` baseline and its authority refresh lane green.
2. Tighten the remaining runtime/provider seams that still behave checksum-first.
3. Keep the zero-config compat-only lane green as an explicit fallback rather than a silent default.
4. Reduce `hts2phrb` canonical-only ambiguity and overlay residue through bounded review-only policy and direct contracts.
5. Keep the tracked review-only reduction lane reproducible, explicit, and non-default.

## Phase A/A1 Execution Checklist

- [x] Preserve structured `PHRB` identity at load time instead of discarding it.
- [x] Separate native sampled records from compat low32 families in provider internals.
- [x] Add direct provider/package coverage for the preserved-identity seam.
- [x] Make runtime source policy explicit and thread it through runtime entrypoints.
- [x] Narrow explicit selected-package runtime lanes to `phrb-only` by policy.
- [ ] Widen structured sampled-object lookup beyond the current exact seam only where direct tests exist.
- [ ] Replace checksum-shaped primary lookup with structured sampled-object identity across the remaining runtime path.
- [ ] Make `.phrb` the only production runtime source.
- [ ] Move `.hts` / `.htc` to import-only status for the default runtime path.
- [ ] Preserve ordered-surface metadata as a runtime-native concept instead of selector hashes.
- [x] Ship the first `hts2phrb` skeleton over the existing pipeline.
- [ ] Strengthen `hts2phrb` until it is the clear common-case front door rather than a thin orchestration wrapper.
- [ ] Add at least one non-Paper-Mario zero-config converter proof.
- [x] Add representative-pack converter operational gates for timing, cache behavior, and output sizing.
- [ ] Keep first-load `.hts` to cached `.phrb` auto-conversion disabled until default-path promotion, then add direct tests for it.

### Delivery Rule

- Land runtime and converter work in measurable slices, not opaque rewrites.
- Each slice should preserve or improve active fixtures, add or strengthen direct tests, and leave the next step obvious.
- Tests ship with the slice, not later.
- Converter work can start early, but it stays downstream of the runtime contract rather than defining it.

## Phase A: Native Runtime Contract

### Goal

- Make `PHRB` the real runtime format instead of a compatibility wrapper around legacy keys.

### First Slice

Before any broad structured-key rollout:

1. Preserve structured `PHRB` identity at load time.
2. Separate native records from compatibility aliases internally.
3. Add direct provider/package tests for that seam.

This slice is intentionally smaller than a full runtime-key rewrite. Its job is to stop the runtime from discarding native identity before broader lookup changes are attempted.

### Required Changes

1. Make `.phrb` the only production runtime source in [`texture_replacement.cpp`](/home/auro/code/parallel-n64/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/texture_replacement.cpp).
2. Treat `.hts` and `.htc` as import-only inputs in the tooling path.
3. Replace provider lookup keyed by `checksum64 + formatsize + selector` with structured sampled-object identity.
4. Use the identity already emitted by the package tooling, including:
   - `fmt`
   - `siz`
   - `tile`
   - `tmem`
   - `line`
   - logical size
   - palette identity
5. Add `tlut_type` as a first-class runtime identity field if the evidence later requires it.
6. Preserve ordered-surface metadata at runtime instead of compiling it down to opaque selector hashes.

### Exit Criteria

- The provider can resolve native records without reconstructing legacy-style keys.
- `PHRB` loading uses structured sampled-object identity as the primary runtime key.
- Compatibility aliases are explicit secondary records, not the baseline key space.
- The runtime contract no longer depends on converter-side convenience decisions to express its identity model.

## Phase A1: Generic Conversion Front Door

### Goal

- Replace the current many-step legacy import experience with one generic conversion command while keeping the richer internal model.

### Required Changes

1. Keep one user-facing entrypoint: `hts2phrb`.
2. Keep it as orchestration over the richer internal package model, not a flat legacy-key emitter.
3. Support `.hts` and `.htc` as generic inputs and `.phrb` as the output artifact.
4. Make common-case conversion work without per-game manual intervention.
5. Emit structured `PHRB` records with all fields known at conversion time, leaving unknown fields explicit.
6. Emit warnings and diagnostics for ambiguous cases instead of broadening runtime behavior silently.
7. Keep enrichment and policy-backed import stages available behind the same front door when needed.
8. Support future optional enrichment inputs without changing the zero-config conversion path.

### Non-Goals

- Do not require users to understand the internal multi-tool pipeline.
- Do not collapse `PHRB` back into mostly legacy-shaped runtime keys.
- Do not treat auto-conversion as a substitute for fixing the provider/runtime contract.

### Exit Criteria

- One command converts a legacy pack into a canonical `PHRB` package.
- The converter can emit structured native identity plus explicit compatibility records, including partial structured records when that is the honest output.
- The front door has smoke, round-trip, and operational coverage.
- At least one non-Paper-Mario pack converts in zero-config mode without requiring new core runtime rules.

## Phase B: Scoped Compatibility Mode

### Goal

- Keep compatibility tools, but fence them away from the core product path.

### Required Changes

1. Keep CI low32 fallback behind explicit compatibility behavior only.
2. Keep proxy bindings and transport bridges as transitional import artifacts, not architectural defaults.
3. Document the sampled-object exact path as intentionally scoped while runtime coverage remains incomplete.
4. Do not widen fallback behavior until the native key path is stable and tested.
5. Keep CI palette parity and `LoadBlock` work as bounded investigations, not automatic architecture drivers.

### Exit Criteria

- Compatibility behavior can be disabled cleanly without changing native package semantics.
- Native package success on active fixtures does not depend on implicit compatibility broadening.

## Phase B1: Legacy Compatibility Investigations

### Goal

- Evaluate the strongest general-case ideas from legacy-pack parity work without replacing the native-first architecture.

### Investigation Discipline

- Keep investigations bounded and decision-oriented.
- If a partial fix helps, record the improvement, classify the remaining seam, and move on.
- Do not let per-family debugging silently become default-path architecture work.

### Investigation 1: CI Palette Parity

- Compare ParaLLEl CI palette inputs against legacy lookup expectations for the same runtime event.
- Keep any improvement as explicit compatibility or import guidance unless it cleanly becomes native identity.

### Investigation 2: `LoadBlock` Sampled-Shape Retry

- Measure the real miss class caused by upload-shape versus sampled-shape disagreement.
- Keep any retry path fenced as compatibility behavior unless it can be expressed cleanly in the native runtime contract.

### Investigation Exit Criteria

- The project can classify each result as:
  - native identity fact
  - bounded compatibility helper
  - dead end

## Phase B2: Identity Classification Gate

### Goal

- Force an explicit architectural decision after the two highest-value compatibility investigations complete.

### Required Decision

After validation on the active Paper Mario fixtures, classify CI palette parity and `LoadBlock` work as:

1. Native identity fact
2. Bounded compatibility helper
3. Dead end

### Decision Rules

- Native identity fact: canonical across games, not just a legacy lookup convention.
- Bounded compatibility helper: improves legacy-pack behavior but should stay explicit and secondary.
- Dead end: does not generalize cleanly, introduces false positives, or fails to improve results materially.

### Current Classification Outcomes

- CI palette parity currently classifies as bounded compatibility or import guidance, not native identity.
- Simple `LoadBlock` sampled-shape retry currently classifies as a dead end for the default runtime path.

### Exit Criteria

- Both investigations have written classification outcomes.
- No compatibility seam is promoted into canonical runtime identity without passing this gate.

## Phase C: Validation Breadth

### Goal

- Stop making format decisions from menu-heavy and single-game-heavy evidence alone.

### Required Changes

1. Keep title screen and file select strict.
2. Keep one deterministic non-menu Paper Mario authority fixture active.
3. Keep semantic hi-res evidence in pass/fail, not just as explanatory output.
4. Keep authority metadata internally consistent.
5. Validate the conversion path across the Paper Mario menu and non-menu authority set before widening scope.
6. Record at least one intentionally rejected unresolved family as negative data.
7. After the Paper Mario runtime picture is cleaner, add one second-game probe with a materially different runtime class profile.

### Exit Criteria

- The authority set includes at least one deeper non-menu state.
- Architectural changes are evaluated against runtime classes, not screenshot equality alone.
- Semantic hi-res evidence is a real gate.
- The native runtime contract has at least one non-Paper-Mario hi-res validation target before generality claims.

## Parallelism Rules

The following work can proceed in parallel once validation trust and the first runtime seam slice are in place:

- CI palette parity investigation
- `LoadBlock` investigation
- early `hts2phrb` skeleton and direct tests
- second-game fixture preparation after the Paper Mario authority set is stable

The following work must stay serial:

- validation trust before interpreting hit-rate movement
- classification before promotion
- Paper Mario full gate before default-path promotion
- second-game gate before generality claims

## Promotion Rule

No new behavior should be promoted to the default runtime path unless all of the following are true:

1. It improves active authority fixtures.
2. It keeps semantic hi-res evidence green.
3. It survives the classification gate.
4. It does not require game-specific runtime key rules.
5. It still fits the native-first runtime contract.
6. If it involves auto-conversion convenience, that convenience stays downstream of the runtime contract.

## Phase D: Restore Direct Tests

### Goal

- Recover the highest-value test discipline without reviving the failed branch architecture.

### Required Changes

1. Keep dedicated tests for:
   - `PHRB` parsing and loading
   - provider lookup behavior
   - selector-bearing native package records
   - compatibility alias fencing
   - converter smoke behavior
   - converter round-trip identity preservation
   - auto-conversion once it exists
2. Reuse ideas from the failed branch's provider tests, not its runtime mode matrix.
3. Keep focused tool tests for package emission and identity preservation.

### Exit Criteria

- Runtime and package regressions can be caught without a full emulator scenario run.
- Provider correctness is testable independently from Paper Mario fixture behavior.

## What To Revive From The Failed Attempt

- replacement-provider parser, decode, and lookup tests
- selected offline comparison and provenance tooling

## What Not To Revive

- runtime lookup-mode matrix
- ownership and consumer policy explosion
- frontend-exposed heuristic controls as product features
- permissive reinterpretation as the normal path

## Decision Gates

Do not declare the native runtime seam ready until all of the following are true:

1. `PHRB` is the default runtime contract.
2. Structured sampled-object lookup is primary.
3. Compatibility fallback is explicit and secondary.
4. One non-menu Paper Mario authority fixture is active.
5. Direct provider/package tests exist.
6. At least one second-game probe exercises the same contract without new core runtime key rules.
7. The legacy-to-`PHRB` conversion path is available through one generic entrypoint, with smoke and round-trip coverage.
8. The Phase B2 classification gate is complete for palette parity and `LoadBlock`.
9. Active authority metadata is internally consistent, and semantic hi-res evidence participates in pass/fail.
10. If default-path auto-conversion is enabled, it is covered by direct tests and does not change native package semantics.
11. Converter operational behavior is acceptable for representative packs.

## Immediate Next Step

- Keep the promoted enriched full-cache `PHRB` baseline green.
- Keep removing remaining checksum-shaped runtime seams without reopening deferred pool or source-backed work.
- Keep reducing converter ambiguity and overlay residue through the tracked review-only lane without silently promoting those reductions.
- Keep the zero-config compat-only lane explicit and green as fallback.
- Keep every skipped item in the deferred register above until it is completed or explicitly rejected by a gate decision.

## Outcome

If this plan succeeds, the project ends up with:

- a native-first `PHRB` runtime contract
- a generic one-command legacy conversion path
- explicit and fenced compatibility behavior
- validation that is broader than Paper Mario menus and stronger than screenshot hashes
- a path to more games that does not depend on per-game runtime hacks
