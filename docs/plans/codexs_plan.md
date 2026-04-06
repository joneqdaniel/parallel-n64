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

## Core Decision

The project should continue on the current imported-format and sampled-object path, but the next major work should be:

1. Make the native package contract authoritative at runtime.
2. Reduce compatibility logic to explicit fallback mode.
3. Broaden validation enough to justify the contract first within Paper Mario and then across at least one second game.

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

## Phase B: Scoped Compatibility Mode

### Goal

- Keep compatibility tools, but fence them off from the core product path.

### Required Changes

1. Keep CI low32 fallback behind explicit compatibility mode only.
2. Keep proxy bindings and transport bridges as transitional import artifacts, not architectural defaults.
3. Document the sampled-object exact path as intentionally scoped while runtime coverage is incomplete.
4. Do not widen fallback behavior until the native key path is stable and tested.

### Exit Criteria

- Compatibility behavior can be disabled cleanly without changing native package semantics.
- Native package success on active fixtures does not depend on implicit compatibility broadening.

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
5. After the first deeper Paper Mario authority is stable, add one second-game probe with a materially different texture profile.
6. Keep game-specific bridge or alias rules in import policy instead of allowing them to reshape the core runtime identity model.

### Exit Criteria

- At least one deeper non-menu state is part of the authority set.
- Architectural changes are evaluated against runtime classes, not only screenshot equality.
- The native runtime contract has at least one non-Paper-Mario validation target before being treated as generally shaped correctly.

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

## Immediate Next Step

- Start with Phase A and implement a native-first provider record path before adding more compatibility-oriented package promotion work.
