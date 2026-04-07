# Hi-Res Runtime Primary Plan

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

## Repo Integration Requirements

- The repo entrypoints must treat this document as the primary plan:
  - [`README.md`](/home/auro/code/parallel-n64/README.md)
  - [`AGENTS.md`](/home/auro/code/parallel-n64/AGENTS.md)
  - [`docs/README.md`](/home/auro/code/parallel-n64/docs/README.md)
  - [`docs/plans/README.md`](/home/auro/code/parallel-n64/docs/plans/README.md)
  - [`docs/plans/PHASE_OVERVIEW.md`](/home/auro/code/parallel-n64/docs/plans/PHASE_OVERVIEW.md)
  - [`docs/PROJECT_STATE.md`](/home/auro/code/parallel-n64/docs/PROJECT_STATE.md)
- Historical, research, or supporting docs may remain, but they should not present themselves as the active direction unless they explicitly supersede this document.
- The repo should not retain duplicate “active direction” plan docs that compete with this one for sequencing authority.
- The user-facing story should remain coherent across the repo:
  - runtime target: `PHRB`
  - legacy input path: `.hts` / `.htc`
  - public conversion front door: `hts2phrb`
  - auto-conversion convenience only after the promotion gate

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
- Validation is still too Paper-Mario-heavy and too shallow in runtime-class breadth to justify final architectural commitment or cross-game confidence.
- There are still likely general legacy-pack miss classes that should be investigated directly at runtime, especially CI palette parity and `LoadBlock` sampled-shape mismatch.

## Current Implementation State

### Completed Slices

- Validation trust is partially live:
  - semantic hi-res evidence now participates in pass/fail on the active title-screen and file-select fixtures
  - authority metadata drift on the active menu fixtures is corrected and covered by a direct contract test
- The first provider/loader seam preservation slice is in:
  - structured `PHRB` identity is preserved in memory instead of being discarded at load time
  - direct provider/package coverage now exists for that preserved identity
  - native sampled records now have a dedicated structured provider index instead of relying on reverse scans over compatibility-shaped storage
  - CI low32 fallback families are now explicitly compat-only and no longer silently read native `PHRB` sampled records
- The exact sampled-object seam is now improved:
  - the renderer can prefer structured provider lookup on exact sampled-object matches instead of relying only on recomposed legacy-style keys
  - the seam now reaches texrects plus the current narrow single-texture triangle case, and the active file-select / `kmr_03 ENTRY_5` authorities stayed runtime-neutral under that widening
- The earliest safe conversion front door exists:
  - `hts2phrb` is live as a wrapper over the current import/build pipeline
  - deterministic singleton proxy groups can be auto-selected without widening default runtime behavior
  - smoke coverage exists for the current skeleton path
  - round-trip coverage now proves the emitted `PHRB` record preserves the structured identity and asset metadata carried through migration, binding, and materialization
- The first CI palette investigation slice is complete enough to bound the next step:
  - the obvious palette-CRC and TLUT-shadow candidates have been tested
  - the remaining gap still needs formal classification instead of open-ended per-family debugging
- Validation breadth is no longer menu-only:
  - the first deterministic non-menu Paper Mario authority fixture is now active at `kmr_03 ENTRY_5`
  - the fixture is savestate-backed, semantically gated in both `off` and `on`, and records the earlier live timeout-probe hash as lineage evidence instead of confusing it with the savestate steady-state capture
- Native selected-package review is now explicit on deeper validation bundles:
  - timeout selected-package summaries now keep exact-hit, exact-miss, conflict-miss, and unresolved-miss counts together instead of collapsing back to hits versus misses only
  - sampled selector review can now classify top conflict/unresolved families against a package loader manifest as `absent-from-package`, `present-selector-conflict`, or stronger matches
  - the same review can now also classify whether absent families still have legacy transport candidates or are already candidate-free under the current `.hts` transport model
- Native pool-conflict diagnostics are now part of the runtime contract:
  - the provider keeps a family-level native sampled index in addition to exact selector keys
  - direct provider/package coverage now proves that multi-selector sampled families stay visible as pools without silently collapsing selector conflicts
  - sampled exact-miss debug logging can now report whether the runtime is looking at an absent family, a selector conflict, or a native pool conflict, along with the preserved `policy_key` and `sampled_object_id`
- Mixed-source runtime precedence is now explicit:
  - cache-directory loading now prefers `PHRB` records over legacy `.hts` / `.htc` duplicates regardless of filename sort order
  - direct provider coverage now proves mixed cache directories keep compat entries available without allowing them to override duplicate `PHRB` keys by load-order accident
  - the provider now also keeps explicit native-checksum and compat-checksum duplicate indices, so exact duplicate families can be addressed intentionally instead of only through “latest entry wins” behavior
  - practical consequence: compat exact helpers and compat low32 unique lookup now stay inside the compat pool even when a native `PHRB` duplicate with the same checksum is present
  - the renderer now mirrors that split for CI fallback descriptors as well, so compat-selected checksum keys get their own resident-image cache namespace and decode path instead of slipping back through the generic/native descriptor cache
  - proof bundle: [`20260406-225500-title-timeout-selected-package-compat-resolver-split/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-225500-title-timeout-selected-package-compat-resolver-split/validation-summary.md)
  - current effect: the explicit selected-package `PHRB` lane stays hash-identical and `phrb-only`, while mixed-cache compat CI resolutions are fenced away from native duplicate descriptor reuse
- The first intentionally rejected family case is now explicit negative data:
  - re-adding `28916d63` to the active `1b85` gameplay package increases native exact hits and converts many `960`-frame misses into selector conflicts
  - but it revives the previously dropped strict title/file hashes and leaves the `960` gameplay image unchanged
  - practical consequence: `28916d63` stays rejected for promotion in the current active package context unless new evidence changes that verdict
- The bounded `LoadBlock` investigation now has explicit decision artifacts:
  - the dominant file-select `64x1 fs514` loadblock family classifies as `no-simple-loadblock-retry`
  - the title `2048x1 fs515` loadblock family lands on the same outcome
  - those results now live in dedicated offline analyzer reports instead of only in free-form notes

### Still Open

- Structured sampled-object lookup is now indexed natively inside the provider, but it is not yet the primary runtime key across the full renderer path.
- `.phrb` is not yet the only production runtime source.
- Ordered-surface runtime preservation is not complete.
- `tlut_type` is not yet a first-class runtime identity field.
- The current timeout worklist is now led by sampled families that are absent from the active package, especially the dominant `2cycle` triangle families `91887078`, `6af0d9ca`, and `e0d4d0dc`.
- The timeout worklist is now split more sharply:
  - the dominant absent `2cycle` triangle families `91887078`, `6af0d9ca`, and `e0d4d0dc` are already candidate-free under the current legacy `.hts` transport model
  - `28916d63` remains absent from the active package, but it is candidate-backed negative data rather than an open promotion target
- The remaining active-package seam on the current `960` bundle is `1b8530fb`, but it now classifies more narrowly as a `present-pool-selector-conflict`.
  - practical consequence: this is not a simple one-record selector alias; any future attempt to close it must preserve the pool semantics instead of collapsing `33` candidates onto one selector.
  - the fresh runtime review artifact now makes that deferment explicit instead of implicit:
    - markdown: [`20260406-174541-title-timeout-selected-package-family-runtime/on/timeout-960/traces/hires-sampled-selector-review.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-174541-title-timeout-selected-package-family-runtime/on/timeout-960/traces/hires-sampled-selector-review.md)
    - json: [`20260406-174541-title-timeout-selected-package-family-runtime/on/timeout-960/traces/hires-sampled-selector-review.json`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-174541-title-timeout-selected-package-family-runtime/on/timeout-960/traces/hires-sampled-selector-review.json)
    - current recommendation: `defer-runtime-pool-semantics` because the active package exposes `33` candidate selectors while the runtime miss stream still presents a family-level selector with `0` matching selectors.
- The exact sampled runtime path no longer re-enters the provider through checksum-shaped decode after a native sampled lookup succeeds.
  - `rdp_renderer.cpp` now resolves exact sampled descriptors through a direct sampled-entry decode path, using the same resident-image cache key but bypassing checksum-index re-selection.
  - latest proof bundle: [`20260406-180724-title-timeout-selected-package-direct-sampled-decode/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-180724-title-timeout-selected-package-direct-sampled-decode/validation-summary.md)
  - current outcome: the rendered `960` frame stays byte-identical to the prior bundle and the `Pool Families` recommendation for `1b8530fb` is unchanged.
  - note: small exact-unresolved deltas have not stayed stable across equivalent selected-package reruns. The same `960` frame and semantic state have now reproduced with totals of `90877`, `90885`, and one earlier `90869`, all on the same `phrb-only` lane. Treat those low-count triangle shifts as non-gating telemetry until a change survives repeated reruns with a real behavioral delta.
- Runtime summary logs can now report how hybrid the loaded provider still is.
  - `log_hires_summary()` now includes total entries, native-sampled vs compat entry counts, sampled-family counts, compat-low32 family counts, and per-source entry counts (`.phrb`, `.hts`, `.htc`).
  - practical consequence: the next runtime-source narrowing step can be measured directly instead of inferred.
- Selected-package validation summaries now surface that provider composition directly.
  - fresh proof bundle: [`20260406-194500-title-timeout-selected-package-provider-summary/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-194500-title-timeout-selected-package-provider-summary/validation-summary.md)
  - current outcome on the active `960` package probe: `source_mode=phrb-only`, `entries=195`, `native_sampled=195`, `compat=0`, `sampled_families=10`, `sources(phrb=195, hts=0, htc=0)`.
  - selected-package timeout validation now enforces that contract directly instead of only reporting it: explicit selected-package probes fail if `source_mode` drifts away from `phrb-only` or if native sampled / `PHRB` entry counts fall to zero.
- The explicit selected-package authority lane is now proven across Paper Mario menu and non-menu authorities without changing the default legacy authority lane.
  - proof bundle: [`20260406-201200-selected-package-authorities/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-201200-selected-package-authorities/validation-summary.md)
  - current outcome: title screen, file select, and `kmr_03 ENTRY_5` all pass semantically under an explicit selected `PHRB` package with `source_mode=phrb-only`, `entries=195`, and `native_sampled=195`.
  - runtime-conformance coverage now exists for that lane through `emu.conformance.paper_mario_selected_package_authorities`, gated behind `EMU_ENABLE_RUNTIME_CONFORMANCE=1`.
- The deeper selected-package timeout lane is now also in runtime conformance instead of being manual-only.
  - proof bundle: [`20260406-231500-title-timeout-selected-package-native-probe-family/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-231500-title-timeout-selected-package-native-probe-family/validation-summary.md)
  - current outcome: the `960` probe still lands on `state_init_world` / `state_step_world`, `kmr_03`, `entry 5`, with `source_mode=phrb-only`, `on_hash=664c0d0784f12cdd6424bce6ae53e828bb08da22a66db0a50f08d6e2de97b3d9`, and the active `1b8530fb` pool-family deferment unchanged.
  - runtime-conformance coverage now exists for that lane through `emu.conformance.paper_mario_selected_package_timeout_validation`, gated behind `EMU_ENABLE_RUNTIME_CONFORMANCE=1`.
- Fresh authority reruns make the current runtime split explicit:
  - the active title-screen, file-select, and `kmr_03 ENTRY_5` authorities still run through the legacy default pack path with `source_mode=legacy-only`, `native_sampled=0`, and `sources(phrb=0, hts=15168, htc=0)`
  - practical consequence: provider-composition minima are now available to the fixture gate, but they should not be promoted into the active authority envs until those authorities intentionally move onto a `PHRB` runtime lane or the default-path promotion phase starts
- Second-game validation has not started.

## Deferred Work Register

Any work item skipped to keep the current slice bounded must stay listed here until it is either completed, explicitly rejected, or moved behind a later gate with evidence.

| Deferred item | Why deferred now | Reactivate when |
|---|---|---|
| Widen structured sampled-object lookup beyond the current exact seam | The runtime now preserves native identity, but broader lookup widening should follow classification rather than outrun it. | After the Phase B2 gate and direct tests show which structured fields must become primary. |
| Make `.phrb` the only production runtime source and treat `.hts` / `.htc` as import-only | The conversion front door and default-path promotion are not ready yet, so runtime source narrowing would outrun the user path. | After Paper Mario breadth passes and the front door is ready to carry the common case. |
| Add `tlut_type` as a first-class runtime identity field | The current palette work has not finished classifying which palette facts are truly canonical. | When the palette classification gate shows that `tlut_type` is required for native identity, not just legacy parity. |
| Preserve ordered-surface metadata as a runtime-native concept instead of selector hashes | The first seam slices focused on exact sampled identity and provider preservation, not selector-bearing runtime promotion. | After the structured runtime key space is stable enough to carry richer ordered-surface state without guesswork. |
| Implement runtime pool semantics for `present-pool-selector-conflict` families like `1b8530fb` | The provider can now describe native pool conflicts directly, but the current evidence still says fixed-slot replay is the wrong behavior for the rotating-stream-edge-dwell case. | After a pool-preserving selector model is defined and direct runtime evidence says it improves the seam without regressing strict authorities. |
| Enable first-load `.hts` to cached `.phrb` auto-conversion | Auto-conversion is a user convenience, not a sequencing shortcut, and enabling it earlier would blur runtime-contract readiness. | Only during default-path promotion, with direct auto-conversion tests and cache-behavior coverage. |
| Promote native-`PHRB` provider-composition minima into the active authority fixtures | The fixture gate can now verify source mode and native/compat counts, but the active title/file-select/`kmr_03` authorities still intentionally validate the legacy default `.hts` runtime path. | After the authority lane itself moves to explicit `PHRB` inputs or the default runtime path promotion begins. |
| Start second-game validation | Cross-game claims are not useful until the Paper Mario menu and non-menu authority set is stable and classification-backed. | After the Paper Mario breadth gate is green and the runtime contract is stable enough to test without new core rules. |
| Treat representative-pack converter performance and cache behavior as a promotion gate | Correctness and bounded ambiguity came first; operational expectations are only meaningful once the skeleton front door is stable. | Before default-path promotion and before auto-conversion is enabled. |

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
- Do not introduce first-load `.hts` to `.phrb` auto-conversion before the default-promotion stage; early convenience must not reshape sequencing or runtime semantics.

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
- The converter has explicit smoke coverage:
  - Paper Mario pack converts end-to-end and reproduces current expected authority behavior
  - at least one non-Paper-Mario pack converts in zero-config mode without requiring new core runtime rules
- The converter has explicit round-trip coverage:
  - legacy entry to `PHRB` record to load path preserves expected key fields and classification-backed behavior
- The converter has explicit operational coverage:
  - conversion time and cache behavior are measured for representative pack sizes before default-path promotion
  - the front door remains usable for typical packs, not just technically correct
- Partial structured records are allowed:
  - converted records may carry only the fields knowable at conversion time
  - partial records do not block the runtime from preferring richer native records when those records exist

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

### Current Classification Outcomes

- CI palette parity currently classifies as a bounded compatibility or import diagnostic, not a native identity fact.
  - raw TLUT entry-count variants, sparse used-index hashing, and emulated loaded-TLUT views did not close the remaining misses
  - the remaining seam looks more like inherited legacy-pack identity mismatch than a small runtime CRC-formula bug
  - practical consequence: do not keep widening palette-formula work in the default runtime path; keep it as explicit compat or import-side guidance unless new evidence overturns this
- `LoadBlock` sampled-shape retry currently classifies as a dead end for simple contiguous runtime retry.
  - the dominant file-select `64x1 fs514` family and title `2048x1 fs515` family both classify as `no-simple-loadblock-retry`
  - neither produced exact-surface or area-preserving reinterpretation hits in the active pack under the current bounded analyzer
  - practical consequence: do not add a permissive simple `LoadBlock` retry path to the default runtime contract

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
6. If it involves auto-conversion convenience, that convenience remains downstream of the runtime contract and does not alter native package semantics.

## Phase D: Restore Direct Tests

### Goal

- Recover the most valuable test discipline from the failed attempt without reviving its architecture.

### Required Changes

1. Add dedicated tests for:
   - `PHRB` parsing and loading
   - provider lookup behavior
   - selector-bearing native package records
   - compatibility alias fencing
   - converter smoke behavior for zero-config `hts2phrb`
   - converter round-trip preservation of emitted identity fields
   - auto-conversion from `.hts` input to cached `.phrb` output once default promotion work begins
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
7. The legacy-to-`PHRB` conversion path is available through one generic entrypoint, with smoke and round-trip coverage.
8. The Phase B2 identity-classification gate has been completed for palette parity and `LoadBlock` reinterpretation.
9. Active authority metadata is internally consistent, and semantic hi-res evidence participates in pass/fail gating.
10. If default-path auto-conversion is enabled, it is covered by direct tests and does not change native package semantics.
11. Converter operational behavior is acceptable for representative packs, including documented timing and cache expectations.

## Immediate Next Step

- The semantic hi-res gate, the first provider preservation slice, direct provider/package coverage, the earliest `hts2phrb` skeleton, the first CI palette pass, the first non-menu Paper Mario authority fixture, and the initial Phase B2 classifications are already in.
- The provider now also separates native sampled records from explicit compat low32 families:
  - structured sampled lookup no longer depends on reverse scans over all entries
  - compat low32 fallbacks no longer use native `PHRB` sampled records as if they were compatibility families
- The provider can now also describe sampled native families without changing behavior:
  - multi-selector native families stay visible as pools instead of collapsing into exact selector misses
  - sampled exact-miss debug logs can now report the preserved `policy_key`, `sampled_object_id`, selector counts, and whether the family is a pool
- Selected-package timeout validation now also preserves the conflict/unresolved split, and sampled selector review can classify the main families against the current loader manifest.
- The current runtime source split is now explicit instead of inferred:
  - active Paper Mario authorities are still `legacy-only`
  - selected-package timeout validation is `phrb-only`
  - selected-package authority validation is also now `phrb-only` across title screen, file select, and `kmr_03 ENTRY_5`
  - do not promote native-`PHRB` provider-composition minima into the active authority envs until the authority lane itself moves
- The timeout selected-package review path can now also tell whether each family still has legacy transport candidates:
  - the dominant absent triangle families `91887078`, `6af0d9ca`, and `e0d4d0dc` are now explicitly candidate-free under the current `.hts` transport model
  - `28916d63` stays candidate-backed negative data, not an open transport mystery
- The first negative-data package experiment is now settled:
  - `28916d63` add-back is rejected in the current active package context because it changes the strict title/file authorities while leaving the `960` gameplay image unchanged
- The next open work is to apply those classifications to the runtime contract:
  - do not add simple `LoadBlock` retry behavior to the default path
  - do not keep widening palette CRC formula variants as if they were native identity fixes
- Continue with targeted structured runtime/package work only where direct tests and current classifications support it:
  - do not keep treating candidate-free absent families as if they were one transport-policy tweak away from promotion
  - treat `present-pool-selector-conflict` families like `1b8530fb` as a later runtime/pool-semantics task, not as a naive selector-alias task
  - keep the generated `Pool Families` review artifact current when that deferment changes, so runtime pool work only resumes from an explicit recommendation rather than from stale memory
  - use the explicit selected-package authority lane as the current `PHRB` correctness proof instead of reading the legacy default authorities as if they had already moved
  - the next actionable package/runtime work now needs either a new candidate source for the candidate-free triangle families or a bounded pool-semantics design for `1b8530fb`
- Keep every skipped item in the deferred register above until it is either completed or explicitly rejected by a gate decision.

## Outcome

If this plan succeeds, the project ends up with:

- a native-first `PHRB` runtime contract
- a generic one-command legacy conversion path
- explicit and fenced compatibility behavior
- validation that is broader than Paper Mario menus and stronger than screenshot hashes
- a path to more games that does not depend on per-game runtime hacks
