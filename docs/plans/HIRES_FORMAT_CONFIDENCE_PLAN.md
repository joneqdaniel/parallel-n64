# Hi-Res Format Confidence Plan

## Purpose

- Define the exact evidence we need before committing to a ParaLLEl-owned hi-res format
- Keep the format aligned with ParaLLEl and closer to N64/LLE semantics instead of inheriting Glide-era ambiguity
- Prevent the project from hardening a format around a narrow or misleading set of observations

## Core Position

- We are not designing a new format because the old one is inconvenient
- We are designing a new format because the inherited Glide-era format appears to encode policy and ambiguity that do not map cleanly to ParaLLEl's more N64-like runtime model
- The new format should make exact identity easier, compatibility explicit, and ambiguity visible

## Confidence Standard

We should feel confident in a new format only when all of the following are true:

1. We understand the exact runtime identity we want ParaLLEl to honor.
2. We know which legacy families are deterministic, which are constrained-compatibility cases, and which remain ambiguous.
3. We have enough bundle-backed evidence that the format is not overfit to one narrow Paper Mario menu state.
4. We can import legacy data into the new representation without losing provenance.
5. We can explain why the new format is more accurate for ParaLLEl than the legacy one.

## Format Goals

- Exact matching should be authoritative.
- Compatibility should be explicit, named, and reviewable.
- Ambiguous legacy families should be represented as unresolved import-time decisions, not hidden runtime guesses.
- Provenance from legacy packs must be preserved.
- The format must support deterministic debugging and evidence generation.
- The format must be practical to migrate from existing Glide-era packs.

## Non-Goals

- We are not trying to preserve every legacy wildcard behavior.
- We are not trying to make runtime heuristics smarter and smarter until textures appear.
- We are not trying to finalize a schema before the evidence base is broad enough.

## What Data We Need

### 1. Runtime Identity Data

We need bundle-backed evidence for:

- texture CRC / checksum identity
- requested `formatsize`
- runtime mode (`tile`, `block`, and any future relevant classes)
- runtime dimensions before replacement
- palette / TLUT identity as currently observed
- sparse palette usage
- emulated-TMEM palette view
- replacement dimensions chosen by the legacy pack family

This is the minimum required to say what ParaLLEl is actually asking for.

### 2. Family Classification Data

For every important observed family we need to know:

- does it resolve exactly
- is it deterministic under a constrained compatibility rule
- is it ambiguous under the inherited format
- what candidate variant groups exist
- what evidence favors or disfavors each candidate

### 3. Coverage Breadth Data

We need more than the current local file-select neighborhood.

Minimum target breadth before format commitment:

- title screen strict fixture
- file select strict fixture
- multiple deterministic file-select branch states
- at least one deeper non-menu Paper Mario authority state once available
- at least one representative block-dominated case

The goal is not “many scenes.” The goal is “enough distinct runtime classes that the format is not menu-overfit.”

### 4. Negative Data

We need explicit proof for what does **not** work:

- CRC variants that fail
- TLUT representations that fail
- fallback rules that are too permissive
- branch states that do not widen the family set
- legacy families that remain unresolved even after new evidence

This matters because the wrong format often looks plausible until the rejected evidence is forgotten.

### 5. Import Feasibility Data

We need to prove that migration is practical:

- legacy cache provenance is preserved
- imported records can point back to source checksums and assets
- deterministic families import cleanly
- ambiguous families survive as explicit decisions
- policy decisions can be attached without mutating source packs

## Evidence Program

### Workstream A: Broaden The Observed Family Set

Goal:
- expand the CI and non-CI family set gradually from authoritative states

Needed work:
- continue deterministic file-select probe exploration
- mint the next authoritative Paper Mario state(s)
- capture at least one non-menu state with real hi-res evidence
- explicitly record when a new branch does not add a new family

Exit signal:
- we are no longer learning only from one tiny file-select neighborhood

### Workstream B: Tighten Exact Identity

Goal:
- know what the exact ParaLLEl-side identity should be before encoding it into a format

Needed work:
- keep auditing CI/TLUT semantics
- separate exact identity from compatibility identity in the docs and tools
- keep block-class analysis separate from CI-family analysis

Exit signal:
- we can state the exact runtime fields the new format should treat as authoritative

### Workstream C: Stress The Import Model

Goal:
- prove the imported representation can express what we need without hiding ambiguity

Needed work:
- keep emitting imported indices from real bundles
- keep generating review artifacts and subset artifacts
- add more deterministic families to policy only when evidence is strong
- keep ambiguous families unresolved until they truly deserve selection

Exit signal:
- imported records, compatibility aliases, unresolved families, and selector policy feel sufficient for the observed evidence set

### Workstream D: Validate The Migration Story

Goal:
- make sure the new format is adoptable, not just theoretically cleaner

Needed work:
- keep migration tooling first-class
- preserve source provenance in every imported slice
- define the future “full import” path clearly
- make sure artists would not need to manually rebuild entire packs

Exit signal:
- we can describe a credible legacy-to-new-format transport utility path end to end

## Proposed Decision Gates

### Gate 1: Evidence Breadth Gate

Do not finalize the format while:

- the observed family set is still dominated by one small menu neighborhood
- we do not yet have at least one deeper non-menu Paper Mario authority
- we have not yet observed a representative block-heavy state beyond the current strict fixture evidence

### Gate 2: Identity Gate

Do not finalize the format while:

- exact ParaLLEl identity is still underspecified
- CI/TLUT exactness is still being conflated with compatibility behavior
- block reinterpretation rules are still hypothetical rather than justified

### Gate 3: Import Gate

Do not finalize the format while:

- deterministic and ambiguous families are not clearly separated
- policy is carrying too much unexplained judgment
- imported subsets still hide provenance or family structure

### Gate 4: Accuracy Gate

Do not finalize the format unless we can explain:

- why the new format maps better to ParaLLEl than Glide-era identity
- what exact behaviors are authoritative
- what compatibility tiers remain allowed
- what ambiguity is intentionally preserved as unresolved

## What “Enough Data” Looks Like

We should consider format commitment only when this checklist is true:

- multiple authoritative Paper Mario states have been observed, not just title/file-select neighborhood states
- the observed family set includes deterministic families, constrained-compatibility families, and at least one still-ambiguous family
- the current import tools can emit review artifacts and imported subsets for the key observed families
- policy entries exist only for families with strong bundle-backed evidence
- unresolved families are still visible and not being quietly collapsed
- we can explain the exact runtime identity fields the format is meant to preserve
- we can explain the migration path from legacy packs

## Current Assessment

Right now we are not ready to commit to the final format.

Why:

- the current model is promising, but still narrow
- the evidence base is broader than before, but still centered on Paper Mario file-select exploration
- we have enough data to shape the format direction
- we do not yet have enough data to lock the full schema with confidence

## Immediate Next Steps

1. Keep using the file-select probe path to widen the observed family set, but bias toward branch changes rather than repeated nearby pulses.
2. Mint the next authoritative Paper Mario state that is outside the current menu neighborhood.
3. Capture at least one additional family class from a deeper state before treating the format as near-final.
4. Keep refining the exact-vs-compatibility boundary in the import model.
5. Preserve unresolved families aggressively until the new evidence base is stronger.

## Working Rule

- The new format should be committed only when the evidence says “this matches ParaLLEl better,” not when the tooling merely says “this is expressible.”
