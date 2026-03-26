# N64 Identity Breakthrough Plan

## Purpose

- Turn the latest N64 research into an implementation plan
- Reduce the current “many misses, too many plausible causes” problem into a small set of explicit workstreams
- Keep ParaLLEl aligned with sampled N64 behavior instead of widening runtime heuristics

## Core Thesis

The likely breakthrough is not a smarter wildcard.

It is a more faithful definition of the texture object ParaLLEl should consider authoritative:

- post-load sampled tile
- logical palette/TLUT view
- relevant tile window and sampler state
- explicit provenance for load/copy/framebuffer classes

## Main Risks We Are Addressing

- keying on raw upload blobs instead of sampled texture meaning
- conflating CI4 and CI8 palette semantics
- hashing expanded TMEM TLUT state instead of logical palette entries
- treating copy / texrect / BG-copy / framebuffer-derived content as if it were authored replacement authority
- hardening compatibility before exact identity is defensible

## Workstreams

### 1. Exact Identity Audit

Goal:
- make the exact replacement key match the sampled N64 object more closely

Required fields to audit or carry explicitly:
- sampled format and size
- direct vs CI
- TLUT enabled and TLUT type
- tile window / origin
- TMEM base address and line/stride
- CI4 palette bank
- clamp / mirror / mask / shift
- upload provenance: `LoadTile` vs `LoadBlock`

Immediate deliverables:
- a written field matrix of what the current runtime key does and does not include
- a written field matrix of what the research says should matter
- one explicit delta list between the two

Exit signal:
- we can point to the exact fields missing from the current identity model instead of just saying “CI/TLUT seems wrong”

### 2. Provenance Classification

Goal:
- separate authored replacement-authority from non-authoritative or high-risk source classes

Classes to distinguish:
- authored RDRAM texture load
- copy-mode / texrect / BG-copy style path
- framebuffer-derived texture or readback path
- uncertain / sync-sensitive / transient load state

Immediate deliverables:
- bundle-visible provenance logging for strict fixtures
- explicit classification reasons for misses or suppressed replacement

Exit signal:
- a miss can be explained as either “authored texture identity gap” or “non-authoritative source class,” not just “lookup failed”

### 3. CI/TLUT Exactness

Goal:
- replace the current palette-side approximation with a more logical N64 view

Required design rules:
- CI4 and CI8 are separate identity models
- CI4 includes palette-bank semantics
- CI8 ignores CI4-style bank semantics
- logical palette entries matter more than expanded TMEM bytes
- `tlut_type` is identity-relevant

Immediate deliverables:
- explicit logical TLUT view in diagnostics
- comparison against the current `tlut_shadow` / `tlut_tmem_shadow` path
- one narrow implementation pass on exact CI identity, not compat

Exit signal:
- either exact CI hits improve on strict fixtures, or we can prove the remaining gap is still format/import-policy rather than exact palette modeling

### 4. Sampler-State Preservation

Goal:
- prove whether replacement rendering is preserving the original RDP sampling state

State to inspect:
- `SL/TL/SH/TH`
- clamp / mirror / mask / shift
- filter mode
- copy mode vs normal textured draw
- any relevant LOD state for later fixtures

Immediate deliverables:
- bundle-visible sampler-state diagnostics for strict fixtures
- one conclusion per strict fixture:
  - preserved correctly
  - preserved with caveats
  - not yet preserved

Exit signal:
- we know whether “same texel source, different visible result” is happening because of identity or because the replacement path is not preserving draw-time sampling behavior

### 5. Imported Compatibility Policy

Goal:
- keep compatibility explicit and policy-driven, not implicit runtime guesswork

Rules:
- exact lookup remains tier 1
- compatibility remains named tier 2
- ambiguous families stay import-policy problems, not silent runtime widening

Current leading example:
- the strict file-select `8x16` CI neighborhood now looks per-low32, not family-wide

Immediate deliverables:
- preserve the current mixed low32 policy as review material
- do not harden it as default runtime behavior yet

Exit signal:
- compatibility rules are easier to explain than to misuse

## Execution Order

1. Provenance logging on the strict title and file-select fixtures
2. Exact identity field audit against the current runtime key
3. CI/TLUT logical-view redesign in diagnostics
4. One narrow exact-path CI implementation pass
5. Re-validate strict title and file select
6. Use one deeper non-menu Paper Mario state only as a confidence check

## Immediate Tickets

### Ticket 1: Provenance Evidence

Add bundle-visible evidence for:
- load op
- cycle/copy mode
- TLUT enabled / type
- tile line/address
- whether the source looks framebuffer-derived or not

Success:
- strict fixture misses can be bucketed by provenance class

### Ticket 2: Exact Key Delta Sheet

Write down:
- what the current ParaLLEl exact key includes
- what the new research says it should include
- which missing fields are most likely to explain current CI/menu misses

Success:
- one short actionable delta sheet exists in docs

### Ticket 3: Logical TLUT Diagnostic Path

Add a diagnostic view that models:
- CI4 banked logical palette entries
- CI8 logical palette entries
- TLUT type

Success:
- strict bundle diagnostics can compare current shadow-based CRCs against a logical-palette view

### Ticket 4: Copy / Texrect Classification

Detect and report whether the current strict misses are normal textured draws or copy/texrect-style draws.

Success:
- early UI misses stop being ambiguous between “identity bug” and “wrong provenance class”

## What This Plan Explicitly Avoids

- broadening low-32 fallback further
- promoting mixed selector policy into default runtime behavior
- reviving generic block-shape normalization
- committing a new format schema before the exact/provenance work proves what the authoritative object really is

## Phase Gate

We should not commit to a new ParaLLEl-owned format until:

- exact identity gaps are described concretely
- provenance classes are visible in evidence bundles
- CI/TLUT exactness has had one honest redesign pass
- copy / texrect behavior has been classified for strict fixture misses
- imported compatibility policy is still explicit rather than hidden in runtime lookup
