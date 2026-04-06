# Codex Runtime Redirect Plan

## Why This Exists

- The current project direction is better than the earlier failed attempt.
- The current runtime contract is still too compatibility-shaped for the long-term goal.
- The next milestone should stop expanding compatibility machinery and instead make the native package/runtime seam authoritative.
- Paper Mario is the first authority game because it has the best current evidence, not because the architecture should remain Paper Mario-specific.

## Short Verdict

- Keep the current repo direction.
- Do not revive the failed branch's runtime lookup-mode matrix.
- Redirect the next milestone toward a native-first `PHRB` runtime contract.
- Treat legacy-pack runtime parity work as bounded compatibility research, not as the primary architecture.
- Provide a single-command generic conversion path for legacy packs, but do not let that convenience define the canonical runtime identity model.

## Current Assessment

### What Is Working

- The project now treats Glide-era packs as import input instead of product truth.
- The renderer has a real sampled-object exact-lookup seam in [`rdp_renderer.cpp`](/home/auro/code/parallel-n64/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_renderer.cpp).
- The tooling now carries canonical sampled-object identity, ordered surfaces, policy-backed selection, and reproducible evidence artifacts.
- Validation and fixtures are much more disciplined than the earlier failed branch.
- Using Paper Mario first is a reasonable bootstrap strategy because it currently has the deepest local evidence base.

### What Is Still Wrong

- Runtime lookup is still centered on `checksum64 + formatsize + selector` in [`texture_replacement.cpp`](/home/auro/code/parallel-n64/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/texture_replacement.cpp).
- `PHRB` stores richer identity than the loader actually uses.
- The sampled-object exact path is still narrow and should be treated as scoped, not complete.
- Validation remains too concentrated on Paper Mario title/file-select to justify final architectural commitment or cross-game confidence.
- There are still likely general legacy-pack miss classes that should be investigated directly at runtime, especially CI palette parity and `LoadBlock` sampled-shape mismatch.

## Core Decision

The project should continue on the current imported-format and sampled-object path, but the next major work should be:

1. Make the native package contract authoritative at runtime.
2. Reduce compatibility logic to explicit fallback mode.
3. Broaden validation enough to justify the contract first within Paper Mario and then across at least one second game.
4. Investigate the highest-value general legacy-pack miss classes without letting them redefine the core runtime key model.
5. Collapse the current import experience into a generic user-facing conversion entrypoint.

The project should not spend the next cycle on:

- adding more selector heuristics
- widening proxy or bridge machinery as a primary path
- reviving frontend-exposed runtime lookup modes
- treating `.hts` and `.htc` as long-term runtime formats

## Phase A: Native Runtime Contract

### Goal

- Make `PHRB` the real runtime format instead of a compatibility wrapper around legacy keys.

### Required Changes

1. Make `.phrb` the only production runtime source in [`texture_replacement.cpp`](/home/auro/code/parallel-n64/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/texture_replacement.cpp).
2. Treat `.hts` and `.htc` as import-only inputs in tooling such as [`hires_pack_migrate.py`](/home/auro/code/parallel-n64/tools/hires_pack_migrate.py) and [`hires_pack_materialize_package.py`](/home/auro/code/parallel-n64/tools/hires_pack_materialize_package.py).
3. Replace provider lookup keyed by `checksum64 + formatsize + selector` with a structured sampled-object key.
4. Use the identity already emitted by [`hires_pack_emit_binary_package.py`](/home/auro/code/parallel-n64/tools/hires_pack_emit_binary_package.py), including:
   - `fmt`
   - `siz`
   - `tile`
   - `tmem`
   - `line`
   - `logical size`
   - palette identity
5. Add `tlut_type` as a first-class runtime identity field.
6. Preserve ordered-surface metadata at runtime instead of compiling it down to opaque selector hashes.

### Exit Criteria

- The provider can resolve native records without reconstructing legacy-style `Entry` keys.
- `PHRB` loading uses structured sampled-object identity as the primary runtime key.
- Compatibility aliases are explicit secondary records, not the baseline key space.

## Phase A1: Generic Conversion Front Door

### Goal

- Replace the current many-step legacy import experience with one generic conversion command while keeping the richer internal model.

### Required Changes

1. Add one user-facing conversion entrypoint such as `hts2phrb`.
2. Implement that entrypoint as an orchestration layer over existing import/build code where possible instead of replacing the internal model with a flat legacy-key emitter.
3. Support `.hts` and `.htc` as generic inputs and `.phrb` as the output artifact.
4. Ensure conversion succeeds without per-game manual intervention for the common case.
5. Emit structured `PHRB` records with all identity fields that are available at conversion time, and leave currently unknowable fields explicit rather than inventing them.
6. Emit warnings and diagnostics for ambiguous cases instead of silently broadening runtime behavior.
7. Keep policy-backed or enriched import stages available behind the same front door when the generic case is insufficient.
8. Support future optional enrichment inputs behind the same entrypoint, for example ROM-backed or policy-assisted augmentation, without changing the basic zero-config conversion path.

### Non-Goals

- Do not require users to understand the current multi-tool pipeline.
- Do not collapse `PHRB` into a container for mostly legacy-shaped runtime keys just to make conversion simpler.
- Do not turn auto-conversion convenience into a substitute for fixing the provider/runtime identity contract.
- Do not pretend currently unknown sampled-object fields are known just to make the first converter output look complete.

### Exit Criteria

- A user can run one command to convert a legacy pack into a runtime package.
- The generated package can carry structured native identity and explicit compatibility records, including partially populated structured records that are ready for later enrichment.
- The conversion entrypoint is generic even if the internals still use multiple stages.

## Phase B: Scoped Compatibility Mode

### Goal

- Keep compatibility tools, but fence them off from the core product path.

### Required Changes

1. Keep CI low32 fallback behind explicit compatibility mode only.
2. Keep proxy bindings and transport bridges as transitional import artifacts, not architectural defaults.
3. Document the sampled-object exact path as intentionally scoped while runtime coverage is incomplete.
4. Do not widen fallback behavior until the native key path is stable and tested.
5. Investigate two bounded runtime compatibility seams as explicit research tasks:
   - CI palette parity with GlideN64 or Rice-era lookup expectations
   - `LoadBlock` upload-shape versus sampled-shape reinterpretation on miss
6. Allow those compatibility investigations to ship only as explicit compat behavior unless they can be expressed cleanly without changing the native runtime identity model.

### Exit Criteria

- Compatibility behavior can be disabled cleanly without changing native package semantics.
- Native package success on active fixtures does not depend on implicit compatibility broadening.
- Palette-parity or `LoadBlock` compatibility work, if retained, is documented as secondary runtime behavior rather than the canonical identity path.

## Phase B1: Legacy Compatibility Investigations

### Goal

- Evaluate the strongest general-case ideas from legacy-pack parity work without replacing the native-first architecture.

### Investigation 1: CI Palette Parity

- Compare ParaLLEl CI palette CRC inputs against GlideN64-style lookup expectations for the same runtime event.
- Determine whether current `tlut_shadow` population or bank-selection semantics diverge in a way that explains active legacy-pack misses.
- If parity fixes improve legacy `.hts` behavior, keep that as explicit compatibility behavior or import guidance unless it cleanly matches the structured native identity model.

### Investigation 2: `LoadBlock` Sampled-Shape Retry

- Measure the real miss class caused by upload-shape versus sampled-shape disagreement.
- Prototype a miss-only retry path for `LoadBlock`-backed cases.
- Keep any such retry path fenced as compatibility behavior unless the same concept can be represented directly in the native package/runtime contract.

### Investigation Exit Criteria

- The project can say clearly whether palette parity and `LoadBlock` reinterpretation are:
  - required native identity facts
  - bounded compatibility helpers
  - or dead ends that should not shape the architecture
- If they are retained, the generic converter can incorporate them automatically without introducing game-specific policy as the normal path.

## Phase B2: Identity Classification Gate

### Goal

- Force an explicit architectural decision after the two highest-value compatibility investigations complete.

### Required Decision

After CI palette parity and `LoadBlock` sampled-shape work are validated on the active Paper Mario fixtures, classify each result as one of:

1. Native identity fact
2. Bounded compatibility helper
3. Dead end

### Decision Rules

- Classify it as a native identity fact only if it reflects the canonical texture identity ParaLLEl should honor across games, not just a legacy pack lookup convention.
- Classify it as a bounded compatibility helper if it materially improves legacy-pack behavior but should remain explicit secondary behavior.
- Classify it as a dead end if it does not generalize cleanly, introduces false positives, or does not materially improve results.

### Exit Criteria

- Both investigations have a written classification outcome.
- The converter and runtime plans reflect those classifications explicitly.
- No compatibility seam is promoted into canonical runtime identity without passing this gate.

## Phase C: Validation Breadth

### Goal

- Stop making format decisions from a menu-heavy and single-game-heavy evidence base.

### Required Changes

1. Promote one deterministic non-menu Paper Mario scene to an authoritative fixture.
2. Keep title and file-select strict fixtures as baseline gates.
3. Add class-based assertions on top of image hashes using the existing evidence output:
   - one texrect-dominated case
   - one block-dominated case
   - one CI or TLUT-sensitive case
4. Resolve authority-graph metadata drift where fixture hashes disagree across planning files and runtime env files.
5. Validate the generic conversion path across the Paper Mario title, file-select, and deeper non-menu fixture set before widening scope.
6. After the first deeper Paper Mario authority is stable, add one second-game probe with a materially different texture profile.
7. Keep game-specific bridge or alias rules in import policy instead of allowing them to reshape the core runtime identity model.

### Exit Criteria

- At least one deeper non-menu state is part of the authority set.
- Architectural changes are evaluated against runtime classes, not only screenshot equality.
- The generic conversion path works across both menu and non-menu Paper Mario authority scenes before cross-game claims are made.
- The native runtime contract has at least one non-Paper-Mario validation target before being treated as generally shaped correctly.
- The generic conversion entrypoint has been exercised on at least one non-Paper-Mario pack without requiring new core runtime key rules.

## Phase D: Restore Direct Tests

### Goal

- Recover the most valuable test discipline from the failed attempt without reviving its architecture.

### Required Changes

1. Add dedicated tests for:
   - `PHRB` parsing and loading
   - provider lookup behavior
   - selector-bearing native package records
   - compatibility alias fencing
2. Reuse ideas from the failed branch's replacement-provider tests, but not its runtime mode matrix.
3. Add focused tool tests for package emission and record identity preservation.

### Exit Criteria

- Runtime/package regressions can be caught without a full emulator scenario run.
- Provider correctness is testable independently from Paper Mario fixture behavior.

## What To Revive From The Failed Attempt

- replacement-provider parser/decode/lookup tests
- selected offline comparison and provenance tooling

## What Not To Revive

- runtime lookup-mode matrix
- ownership and consumer policy explosion
- frontend-exposed heuristic controls as product features
- permissive reinterpretation as the normal path

## Decision Gates

The project should not declare the native format/runtime seam ready until all of the following are true:

1. `PHRB` is the default runtime contract.
2. Structured sampled-object lookup is primary.
3. Compatibility fallback is explicit and secondary.
4. One non-menu Paper Mario authority fixture is active.
5. Direct provider/package tests exist.
6. At least one second-game probe exercises the same contract without adding new core runtime key rules.
7. The legacy-to-`PHRB` conversion path is available through one generic entrypoint.
8. The Phase B2 identity-classification gate has been completed for palette parity and `LoadBlock` reinterpretation.

## Immediate Next Step

- Start with Phase A and implement a native-first provider record path before adding more compatibility-oriented package promotion work.
- In parallel, run the two Phase B1 investigations to decide what compatibility behavior is worth preserving as explicit secondary support for legacy packs.
- Record the classification results in Phase B2 before promoting either seam into the converter or runtime contract.
- After the provider contract is clear enough, add Phase A1 as the user-facing wrapper so the import experience becomes one command instead of a research pipeline.
