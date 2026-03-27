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

Current artifact:
- `traces/hires-evidence.json` now records `sampler_usage` from draw-time tile state
- verified early-fixture result:
  - file select (`20260326-sampler-check-2`) top visible copy-mode bucket is a repeated texrect sampler regime:
    - `fmt=2 siz=1 stride=296 sl=0 tl=0 sh=1180 th=20`
    - `mask_s/t=0`, `shift_s/t=0`
    - `clamp_s/t=1`, `mirror_s/t=0`
    - `66` events
  - title screen (`20260326-sampler-check`) shows the same top copy-mode texrect regime even more strongly:
    - same `fmt=2 siz=1 stride=296 sl=0 tl=0 sh=1180 th=20`
    - same clamp/mirror/mask/shift state
    - `132` events
  - title screen also has a second large non-copy texrect regime:
    - `fmt=0 siz=3 stride=400 sl=0 tl=0 sh=796 th=4`
    - same fully clamped, unmasked window style
    - `106` events
  - practical implication: the current early-scene visible path collapses to a few repeated sampled-object regimes rather than a broad sampler-state explosion

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

Current artifact:
- `traces/hires-evidence.json` provenance summaries on strict bundles
- the focused `64x1 fs514` row probe is now captured in [hires-block-family-report.md](/home/auro/code/parallel-n64/artifacts/paper-mario-file-select-block-family-probe/on/20260326-live-1/traces/hires-block-family-report.md)
  - `21` unique addresses
  - dominant address delta `0x80`, matching the observed `128`-byte row span
  - consistent zero-padded row envelope with active bytes clustered in the middle
  - no exact duplicate row payloads
  - current implication: the dominant miss family behaves more like contiguous row slices from a larger authored surface than random transient data
- the first sampled-object confirmation pass now exists at [20260327-sampled-object-probe](/home/auro/code/parallel-n64/artifacts/paper-mario-file-select/on/20260327-sampled-object-probe)
  - the reviewed artifact is [hires-sampled-object-review.md](/home/auro/code/parallel-n64/artifacts/paper-mario-file-select/on/20260327-sampled-object-probe/traces/hires-sampled-object-review.md)
  - dominant upload-side families collapse into two sampled draw-side CI4 texrect objects (`16x16@stride8` and `64x16@stride32`)
  - neither sampled key exists in the active legacy pack index
  - current implication: the new-format/import problem is now concrete, not hypothetical; ParaLLEl needs canonical sampled-object IDs plus explicit legacy alias transport

### Ticket 2: Exact Key Delta Sheet

Write down:
- what the current ParaLLEl exact key includes
- what the new research says it should include
- which missing fields are most likely to explain current CI/menu misses

Success:
- one short actionable delta sheet exists in docs

Current artifact:
- [N64 Exact Key Delta Sheet](/home/auro/code/parallel-n64/docs/plans/N64_EXACT_KEY_DELTA_SHEET.md)

### Ticket 3: Logical TLUT Diagnostic Path

Add a diagnostic view that models:
- CI4 banked logical palette entries
- CI8 logical palette entries
- TLUT type

Success:
- strict bundle diagnostics can compare current shadow-based CRCs against a logical-palette view

Current artifact:
- `ci_palette_probe.logical_views` in strict `hires-evidence.json` bundles

### Ticket 4: Copy / Texrect Classification

Detect and report whether the current strict misses are normal textured draws or copy/texrect-style draws.

Success:
- early UI misses stop being ambiguous between “identity bug” and “wrong provenance class”

Current artifact:
- `traces/hires-evidence.json` now records `draw_usage` summaries on strict bundles
- verified early-fixture result:
  - file select (`20260326-draw-class-check`) is draw-class dominated by `texrect` (`194/252` draw-usage lines)
  - its strongest visible copy-mode replacement bucket is `draw_class=texrect cycle=copy copy=1 ... texel0_hit=1 texel1_hit=1` with `68` events
  - title screen (`20260326-draw-class-check`) shows the same structure more strongly: `texrect` dominates (`254/370` draw-usage lines), and the leading bucket is the same copy-mode texrect hit pattern with `136` events
  - practical implication: the visible early-scene hi-res path is not just “tile hits”; it is strongly texrect-driven, especially in copy mode
  - the stricter texel-linked follow-up on file select (`20260326-texel-link-check`) narrows the miss side too:
    - the dominant no-hit texrect regime is the `64x1 fs514` block family directly
    - a smaller repeated mixed texrect regime carries the ambiguous `8x16 fs258` CI family
    - so the remaining early texrect work is now concretely split between those two lookup families rather than one vague texrect bucket

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
