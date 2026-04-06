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

## Plan Authority

- This document is the controlling execution plan for the hi-res runtime/package direction.
- Other planning docs may provide implementation detail, experiments, or alternate reasoning, but when sequencing or architectural priorities conflict, this document wins.
- Companion plans are still useful:
  - converter and parity work can borrow concrete implementation ideas
  - validation and confidence docs still define supporting evidence expectations
  - import-model docs still describe useful internal scaffolding
- The purpose of this document is to keep all of that work pointed at one outcome instead of letting adjacent plans re-fragment the sequence.

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

## Execution Order

The intended order of work is:

1. Stabilize plan prerequisites and validation trust.
2. Land the smallest useful runtime/provider seam slice.
3. Run palette parity, `LoadBlock`, and converter-skeleton work in parallel.
4. Classify those investigations before promoting either seam.
5. Widen structured runtime lookup only where the classification and evidence say it is needed.
6. Promote the generic `hts2phrb` front door on top of the improved internals.
7. Prove the path across Paper Mario menu and non-menu authority scenes.
8. Make `PHRB` the default runtime path only after the Paper Mario gate is met.
9. Prove the same contract on a second game with a different runtime class profile.

The key sequencing rule is:

- converter convenience does not get to outrun the runtime contract
- compatibility investigations do not get to pre-decide the native identity model
- validation gates do not get to remain screenshot-only

## Immediate Priorities

If work starts now, the priority stack is:

1. Make the active validation set trustworthy by resolving authority metadata drift, activating one non-menu Paper Mario authority fixture, and making semantic hi-res evidence participate in pass/fail.
2. Fix the first provider/loader seam so `PHRB` is not reduced back to compatibility keys at load time.
3. Add direct provider/package tests for that seam slice.
4. Run the two highest-value investigations:
   - CI palette parity
   - `LoadBlock` sampled-shape reinterpretation
5. In parallel, build the earliest safe `hts2phrb` skeleton over the improved internals.
6. Capture classification results before allowing either seam into the canonical contract.

### Delivery Rule

- Phase A should land in measurable slices, not as a single opaque rewrite.
- Each slice should preserve or improve active fixture results, add or strengthen direct tests, and keep the next step obvious.
- Tests should be written alongside each slice and investigation, not deferred to the end of the phase.
- Good early slices include:
  - preserve structured `PHRB` identity at load time instead of discarding it
  - separate native records from compatibility aliases in provider internals
  - add provider/package tests before widening runtime lookup coverage
  - widen primary structured lookup only after the prior slices are stable
- The first useful Phase A slice is intentionally smaller than a full structured-key rollout.
- Converter work may start once that first seam slice lands, but it must remain downstream of validation trust and the initial provider/loader fix.

## Phase A: Native Runtime Contract

### Goal

- Make `PHRB` the real runtime format instead of a compatibility wrapper around legacy keys.

### First Slice

Before any broad structured-key rollout, land the smallest useful seam fix:

1. Preserve structured `PHRB` identity at load time instead of discarding it.
2. Separate native records from compatibility aliases internally.
3. Add direct provider/package tests for that seam.

Concretely, the first seam slice should be closer to a targeted loader/provider preservation fix than a lookup redesign:

- keep the current lookup behavior stable
- extend in-memory provider records so structured `PHRB` identity is preserved after load
- avoid changing primary indices until the preserved fields are test-covered and classification work has progressed

This is intentionally a low-risk enabling slice. Its job is to stop the runtime from throwing away native identity before broader lookup changes are considered.

This slice is the minimum runtime-contract change required before converter work or compatibility investigations are allowed to shape default behavior.

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
- The runtime contract no longer depends on converter-side convenience decisions to express its canonical identity model.
- The runtime contract reached that state through measurable slices rather than an untestable big-bang rewrite.
- The first seam slice preserved structured `PHRB` identity in memory before broader lookup redesign was attempted.

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
- The front door may ship before full structured lookup is the default runtime path, but it must remain a wrapper over the richer model rather than freezing a legacy-shaped contract.
- The earliest shippable form of the front door is a skeleton:
  - one command
  - structured records with known fields
  - ambiguity diagnostics
  - no unclassified compatibility behavior baked into default output

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

### Investigation Discipline

- Investigation work must stay bounded and decision-oriented.
- If an investigation yields a partial improvement, do not spiral into endless case-by-case debugging before the classification gate.
- The correct next step for a partial result is:
  1. record the measurable improvement
  2. classify the remaining misses by cause
  3. decide whether the seam looks native, compat, or dead-end
  4. move the sequence forward
- Investigation work is successful when it produces either:
  - a clear improvement with a defensible classification
  - or a clear rejection with enough evidence to stop investing

### Investigation 1: CI Palette Parity

- Compare ParaLLEl CI palette CRC inputs against GlideN64-style lookup expectations for the same runtime event.
- Determine whether current `tlut_shadow` population or bank-selection semantics diverge in a way that explains active legacy-pack misses.
- If parity fixes improve legacy `.hts` behavior, keep that as explicit compatibility behavior or import guidance unless it cleanly matches the structured native identity model.
- Working assumption:
  - palette parity is more likely to reveal a native identity bug than a mere compatibility nicety
  - it still must pass the classification gate before being declared canonical
- Priority:
  - this is the first identity investigation to run because it is the strongest candidate for a genuine native-identity correction rather than a legacy convenience rule
- Partial-result rule:
  - if the fix materially improves hit rates but does not close the seam completely, record the residual miss classes and proceed to classification instead of expanding into open-ended per-family debugging

### Investigation 2: `LoadBlock` Sampled-Shape Retry

- Measure the real miss class caused by upload-shape versus sampled-shape disagreement.
- Prototype a miss-only retry path for `LoadBlock`-backed cases.
- Keep any such retry path fenced as compatibility behavior unless the same concept can be represented directly in the native package/runtime contract.
- Working assumption:
  - a miss-only retry is compatibility behavior until proven otherwise
  - `LoadBlock` should not be promoted into canonical identity merely because it improves legacy-pack hit rate
- Partial-result rule:
  - if the retry improves known miss families but raises unresolved false-positive risk, stop at classification and second-game validation rather than widening the retry path by instinct

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
4. Make semantic hi-res evidence pass or fail, not just explanatory output. At minimum, require assertions over expected exact, compat, conflict, unresolved, or class-presence signals from `hires-evidence.json`.
5. Resolve authority-graph and fixture metadata drift where expected capture hashes or lineage data disagree across planning files, fixtures, and runtime env files.
6. Validate the generic conversion path across the Paper Mario title, file-select, and deeper non-menu fixture set before widening scope.
7. Record at least one intentionally rejected fallback or unresolved family as negative data before declaring the architecture ready.
8. After the first deeper Paper Mario authority is stable, add one hi-res-specific second-game probe with a materially different runtime class profile, not just another texrect or UI-heavy scene.
9. Keep game-specific bridge or alias rules in import policy instead of allowing them to reshape the core runtime identity model.

### Exit Criteria

- At least one deeper non-menu state is part of the authority set.
- Architectural changes are evaluated against runtime classes, not only screenshot equality.
- Authority metadata and expected captures are internally consistent across the active Paper Mario authority set.
- The generic conversion path works across both menu and non-menu Paper Mario authority scenes before cross-game claims are made.
- Semantic hi-res evidence is part of the gate, not just a sidecar artifact.
- The native runtime contract has at least one non-Paper-Mario hi-res validation target before being treated as generally shaped correctly.
- The second-game validation exercises a runtime class not already dominant in the active Paper Mario authority scenes.
- The generic conversion entrypoint has been exercised on at least one non-Paper-Mario pack without requiring new core runtime key rules.
- At least one unresolved or intentionally rejected fallback case remains explicitly documented as negative data.

## Parallelism Rules

The following work can proceed in parallel after validation trust and the first runtime seam slice are in place:

- CI palette parity investigation
- `LoadBlock` retry investigation
- early `hts2phrb` skeleton work
- direct test authoring
- second-game fixture preparation once the Paper Mario authority set is stable

The following work must remain serial:

- validation trust before interpreting hit-rate movement
- classification before promotion
- targeted structured-key widening before declaring runtime-contract correctness
- Paper Mario full gate before default-path promotion
- second-game gate before claiming generality

## Promotion Rule

No new behavior should be promoted to the default runtime path unless all of the following are true:

1. It improves active authority fixtures.
2. It does not break semantic hi-res evidence expectations.
3. It survives the classification gate.
4. It does not require game-specific runtime key rules.
5. It still fits the native-first runtime contract.

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
9. Active authority metadata is internally consistent, and semantic hi-res evidence participates in pass/fail gating.

## Immediate Next Step

- Start with validation trust preflight: resolve authority drift, activate one non-menu Paper Mario authority, and make semantic hi-res evidence a real gate.
- Next, land the first Phase A seam slice: preserve structured `PHRB` identity at load time, separate native versus compat records, and add direct provider/package tests.
- Then run the Phase B1 investigations in parallel with an early Phase A1 `hts2phrb` skeleton.
- Record the classification results in Phase B2 before promoting either seam into the converter or runtime contract.
- Only after that widen structured lookup, complete the front door, pass the Paper Mario full gate, and promote `PHRB` to default.

## Outcome

If this plan succeeds, the project ends up with:

- a native-first `PHRB` runtime contract
- a generic one-command legacy conversion path
- explicit and fenced compatibility behavior
- validation that is broader than Paper Mario menus and stronger than screenshot hashes
- a path to more games that does not depend on per-game runtime hacks
