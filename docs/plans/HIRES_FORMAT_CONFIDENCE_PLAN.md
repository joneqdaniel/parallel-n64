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
- at least one deeper non-menu Paper Mario authority state
- at least one representative block-dominated case

The goal is not “many scenes.” The goal is “enough distinct runtime classes that the format is not menu-overfit.”

Current positive direction:

- a bounded title-screen timeout path now reaches non-menu callbacks without any populated savefile dependency
- that path is currently the best candidate for the first deeper non-menu Paper Mario authority

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

### Research Phase 0: N64 Identity Constraints

Goal:
- establish the N64-side rules that the new format must not violate

Primary sources:
- local N64 documentation in `/home/auro/code/n64_docs`
- decomp-backed Paper Mario observations only as supporting evidence, not as the rule source

Questions to answer:
- what exact texture identity is implied by TMEM, TLUT, CI4/CI8, `LoadTile`, `LoadBlock`, texrect, and related RDP behavior
- which palette/TLUT bytes are semantically relevant for replacement identity
- when is runtime reinterpretation justified by real N64 transfer semantics, and when is it just emulator policy

Expected outputs:
- concise constraints we should preserve in ParaLLEl
- explicit notes on what the format must encode versus what can remain compatibility policy
- explicit notes on block-class and CI/TLUT identity boundaries

Exit signal:
- we can explain the N64-side identity constraints the new format is trying to respect

### Research Phase 1: Emulator And Pack-Model Comparison

Goal:
- understand how other emulators separate exact identity, compatibility matching, and imported or legacy pack models

Primary sources:
- local emulator references in `/home/auro/code/emulator_references`
- official or primary implementation sources already mirrored there

Questions to answer:
- how do other emulators define exact replacement identity
- how do they handle paletted / TLUT-backed textures
- how do they separate runtime lookup from imported or legacy pack policy
- what compatibility rules are explicit versus hidden heuristics

Expected outputs:
- emulator-by-emulator comparison of replacement identity and import model shape
- concrete patterns we should reuse
- concrete anti-patterns we should avoid

Exit signal:
- we can justify why the new ParaLLEl format is closer to an exact-authoritative model than Glide-era pack behavior

### Research Phase 2: Targeted Re-Research

Goal:
- resolve specific ambiguous families or policy questions as they appear

Use this phase when:
- a family remains ambiguous after import review
- a block-class behavior still lacks N64-side justification
- a compatibility rule looks plausible but not defensible

Expected outputs:
- narrowly scoped answers tied to a specific family, runtime class, or policy question

Exit signal:
- the ambiguous question is either resolved or explicitly left unresolved in the format/policy layer

## Initial Research Conclusions

The first explicit research pass across local N64 docs and emulator references already narrows the format direction materially.

### From N64 Documentation

- The new format should describe the post-load sampled texture object, not just the raw upload blob.
- Exact identity should preserve:
  - sampled format (`fmt/siz`, direct vs CI, TLUT type)
  - logical texel payload
  - logical palette payload
  - sampler state such as tile window, line/stride, palette selector for CI4, and wrap/clamp/mirror/mask/shift
- CI4 and CI8 should not be treated as the same kind of palette identity:
  - CI4 depends on the selected 16-entry palette
  - CI8 depends on the logical TLUT contents addressed directly
- `LoadTile` and `LoadBlock` are semantically different upload paths, and their provenance is valuable diagnostic or exactness data even when sampled output may sometimes coincide.
- `LoadTLUT` expands entries in TMEM, so exact palette identity should be based on logical palette entries, not on the expanded TMEM image.
- `texrect` is a draw use of a tile, not a different texture object; reuse across texrect variants belongs in compatibility policy, not exact identity.

### From Emulator Comparison

- Exact identity should separate base texel identity from palette/TLUT identity, then combine them for authoritative lookup.
- Used palette span or effective palette selection is a better exactness model than a blunt full-palette hash.
- Palette bank/select belongs in identity when the hardware model makes it meaningful.
- Exact lookup should remain tier 1; compatibility lookup should be explicit tier 2.
- Imported legacy behavior should remain visibly legacy and must not redefine the canonical ParaLLEl identity.
- Wildcards, broad low-entropy hashes, and silent relaxations are all anti-patterns for an accuracy-first format.

### Immediate Format Implications

- The canonical ParaLLEl format should be structured and metadata-rich, not filename-only.
- The default runtime policy should be `exact-only`.
- Imported Glide-era packs should be migration input into explicit compatibility aliases, not the spec itself.
- CI/TLUT compatibility should stay explicit and named; it should not be allowed to blur the exact identity model.
- Block-class reinterpretation should stay diagnostic until it has clear N64-side justification.

### Latest Research Synthesis

The newest full-docs research pass across `/home/auro/code/n64_docs` sharpens what “exact identity” likely needs to mean for ParaLLEl:

- The authoritative object is the post-load sampled tile, not the raw upload blob.
- `SetTile` state is part of texture meaning:
  - `fmt/siz`
  - TMEM `address`
  - TMEM `line`
  - CI4 `palette`
  - clamp / mirror / mask / shift
- `SetTileSize` and `LoadTile` also change meaning because the sampler shifts coordinates, subtracts the tile upper-left, and then applies clamp/mirror/mask.
- `LoadBlock` provenance matters:
  - `dxt`
  - odd-line word swapping
  - 64-bit padding requirements
  - possible wrap/corruption cases
  - render-useless tile-size side effects during the load itself
- `LoadTLUT` is not a raw byte copy:
  - entries are expanded in high TMEM
  - CI4 and CI8 have different palette semantics
  - `tlut_type` changes final sampled meaning
  - CI4 palette-bank selection is identity-relevant
- Copy / texrect / BG-copy paths are first-class identity/provenance concerns:
  - copy mode has different sampling rules
  - copy mode ignores some normal-texture semantics
  - many UI paths may be running through copy-style behavior rather than “normal textured draw” behavior
- Framebuffer-derived textures are normal N64 behavior and should not be treated as authored replacement-authority by default.

The practical implication is that many apparent misses may not be “wrong texture pack data” in the simple sense. Some are likely:
- CI/TLUT identity mismatches
- copy-mode / texrect provenance mismatches
- non-authoritative framebuffer / streaming / upload-side artifacts
- source-side low32 families that the legacy format collapses too aggressively

So the breakthrough direction is not “widen heuristics until more hits appear.” It is:
- make exact identity more faithful to the sampled N64 object
- explicitly classify non-authoritative source classes
- keep imported compatibility policy separate and reviewable

### Conversion Guardrails From The HLE-to-LLE Report

The new conversion analysis in [hle-to-lle-conversion-plan.md](/home/auro/code/parallel-n64/docs/plans/hires-conversion-analysis/hle-to-lle-conversion-plan.md) and [palette-crc-transform-analysis.md](/home/auro/code/parallel-n64/docs/plans/hires-conversion-analysis/palette-crc-transform-analysis.md) changes the next-step plan, but not the core architecture.

Adopted:
- a three-tier conversion split:
  - Tier 1 pure-math bridge generation
  - Tier 2 ROM/display-list scan as the main resolver
  - Tier 3 runtime observation only for leftovers
- direct testing of the entry-count palette CRC path as a likely bridge candidate
- explicit ROM/display-list tooling as a first-class workstream instead of treating runtime bridge recording as the default path

Not adopted as-is:
- the claim that the gap is already “narrow” enough to treat legacy CRC equality as native identity
- the claim that entry-count palette identity already holds without strict-bundle validation
- partial conversion output with guessed `tmem_offset`, `tmem_stride`, or sampled dimensions as runtime-ready records

Planning rule change:
- Tier 1 outputs are candidate-generation artifacts only unless every native-key field is independently resolved.
- Tier 2 is now the preferred path for resolving `SetTile`, `SetTileSize`, and `LoadBlock` ambiguity.
- Tier 3 runtime bridge recording remains necessary, but only after static resolution paths are exhausted.

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
5. Run explicit subagent-backed research phases against N64 docs and emulator references as part of the normal confidence loop.
6. Preserve unresolved families aggressively until the new evidence base is stronger.

## Working Rule

- The new format should be committed only when the evidence says “this matches ParaLLEl better,” not when the tooling merely says “this is expressible.”
