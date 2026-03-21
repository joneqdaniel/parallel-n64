# Parallel N64 Hi-Res / Scaling Project Notes

This document is the running record of current thinking for the hi-res texture and scaling work in this repo.

It is intentionally not a final implementation plan. The goal is to collect what we know, what we suspect, what we learned from past work, and what constraints should shape the multi-phase plans we create later.

## Why This Exists

We spent significant time trying to make stable hi-res texture support and proper scaling happen in this codebase and did not get the result we wanted.

This restart should not behave like a normal feature branch. It should behave like a renderer program:

- preserve baseline stability
- learn from the failed attempt
- improve confidence and observability before major implementation
- split hard problems into testable phases
- keep enough flexibility to adapt if new evidence changes the approach

## Core Goals

- Load hi-res textures that scale properly with resolution.
- Keep baseline core behavior intact when hi-res/scaling support is disabled.
- Stay as close as practical to the standard renderer path when features are enabled, while accepting that enabled hi-res support is no longer pure LLE.
- Make the feature stable enough for real gameplay, not just isolated demos.
- Build the tooling needed for autonomous and semi-autonomous debugging, including save-state-driven testing and repeatable scene capture.

## Non-Negotiable Constraints

- If the new support is disabled, behavior should remain as close as possible to the standard stable renderer path.
- Any divergence from standard behavior must be deliberate, observable, and attributable.
- We should not force large architectural changes outside the video core unless there is a clear blocker.
- We should favor deterministic reproduction over ad hoc manual testing.
- We should not confuse "detected replacement texture" with "correctly integrated replacement texture."

## Current Working View

The current hi-res implementation should be treated as a prototype / spike, not a stable base that only needs polishing.

Reasons:

- The hook for enabling/disabling hi-res replacement is fairly contained.
- The renderer does perform hi-res keying and cache lookup.
- However, the current code does not yet look like a complete end-to-end replacement path.
- Several signs point to "lookup and metadata plumbing started" rather than "replacement rendering is fully integrated."

This is important because it changes the mindset:

- We should reuse the useful separation and cleanup work already done.
- We should not assume the current branch is close to feature-complete.
- We should be ready to redesign the hi-res path while keeping the repo cleanup and testability improvements.

## Current Code Observations

### 1. Gating Is in Better Shape Than the Feature Itself

The hi-res enable path is gated from the frontend/config side in files such as:

- `mupen64plus-video-paraLLEl/rdp.cpp`
- `mupen64plus-video-paraLLEl/parallel.cpp`
- `libretro/libretro.c`
- `mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_device.cpp`

That is good news. It supports the requirement that the disabled path should remain intact and that the feature can stay opt-in.

### 2. The Current Renderer Path Appears Partial

The current renderer performs hi-res lookup during texture upload/keying.

Observed behavior:

- A replacement provider is attached to the renderer.
- Texture CRC / key computation is performed.
- A lookup is attempted against the replacement cache.
- Hit/miss information is tracked per tile.

Concerns:

- `ReplacementMeta.orig_w` and `ReplacementMeta.orig_h` do not appear to be populated in the current lookup path.
- `decode_rgba8()` exists in the replacement provider, but at the time of review it does not appear to have any call sites.
- The lookup result metadata appears underused after the hit/miss decision.

Working interpretation:

- We likely have the beginning of a replacement identification system.
- We do not yet appear to have a fully wired replacement upload/bind/sample/render pipeline.
- This likely explains why the feature did not reach stable behavior even after serious effort.

### 3. Hi-Res Support and Resolution Scaling Are Related but Not the Same Problem

We should separate:

- hi-res replacement texture support
- texture scaling / texrect / LOD / coordinate behavior under increased internal resolution

These two features interact, but they should not be planned as one indivisible implementation blob.

If we combine them too early, we increase ambiguity:

- Was a bug caused by replacement texture identity?
- By replacement upload?
- By sampler state?
- By UV normalization?
- By texrect math?
- By internal upscaling?
- By VI presentation?

We need a shared foundation, but separate phases.

## What Looks Worth Keeping

- The repo cleanup and refactoring work that improved readability and isolated logic into more testable policy layers.
- The existing test runner and local tiering model.
- The dump capture and replay validation direction.
- The decision to work from a cleaner point in history instead of piling onto a chaotic branch.

The project should build on these, not discard them.

## Tooling Assessment

There is already more structure here than a typical emulator fork:

- `run-tests.sh` provides local CTest orchestration and profiles.
- `docs/EMU_TESTING.md` documents test tiers and local workflows.
- `tests/emulator_behavior/` contains a non-trivial unit and behavior test surface.
- `tools/capture-rdp-dump.sh` shows that capture/replay workflows are already part of the repo story.

However, there is still a major confidence gap for this project.

### Tooling Gaps That Matter

- No obvious root-level formatting/lint flow for the C/C++ renderer code.
- No obvious root-level `clang-tidy` / `cppcheck` / static analysis workflow.
- No visible coverage-oriented workflow for the policy/testable logic that has already been extracted.
- Existing tests are useful, but they are not yet a dedicated hi-res/scaling confidence harness.
- We need faster scene reproduction and comparison loops built around savestates and known game points.
- Agents need one-command workflows for:
  - launch
  - load state / reach scene
  - toggle feature
  - capture frame or dump
  - compare against baseline
  - emit logs with enough context to explain divergence

### Conclusion on Tooling

Tooling is not overhead for this effort. Tooling is part of the implementation.

If we want agents to make repeated renderer changes safely, we need deterministic feedback that is:

- local
- fast
- reproducible
- scoped to the feature area
- understandable when it fails

## Suggested Project Shape

This should be approached in layers.

### Layer 0: Guardrails and Reproducibility

Before serious feature implementation, improve:

- formatting/lint/static-analysis entry points
- sanitizer coverage where practical
- save-state-based scene reproduction
- frame capture and comparison utilities
- feature-flag-driven logging and metrics

This does not mean a giant cleanup detour. It means building only the guardrails that directly support hi-res/scaling work.

### Layer 1: Observability Before Behavior Change

Before trying to render replacement textures correctly, make it easy to answer:

- what texture was keyed?
- what CRC / palette CRC / formatsize was used?
- was there a cache hit?
- what tile / TMEM / texrect state was active?
- what original dimensions were inferred?
- what replacement dimensions were selected?
- what scaling factor and sampler decisions were in effect?

If we cannot observe those things cheaply, we will repeat the same debugging failures.

### Layer 2: Native-Resolution Replacement First

Do not start with "perfect hi-res under every upscale mode."

Instead:

- prove replacement identity
- prove replacement loading
- prove replacement upload/bind/use
- prove correct sampling at native/internal-1x behavior first

Only after this is stable should we widen the feature surface.

### Layer 3: Resolution Interaction

After native-resolution replacement is stable, then address:

- internal upscaling interaction
- texrect behavior
- texture coordinate mapping
- texture LOD behavior
- filtering and mip behavior
- framebuffer / VI presentation interactions

This is likely the real heart of the project.

### Layer 4: Runtime Stability and Game Matrix

Once the model is correct in focused scenes:

- expand game coverage
- collect save states for known difficult cases
- build a curated compatibility matrix
- separate "known acceptable divergence" from "regression"

## Architecture Direction

Current opinion:

- Keep the disabled path as close as possible to baseline behavior.
- Isolate enabled-path logic behind early, explicit gates.
- Prefer small, explicit interfaces between:
  - keying
  - replacement lookup
  - replacement upload/registry
  - mapping from original texture semantics to replacement texture semantics
  - scaling / texrect / LOD policies

The most important architectural rule is this:

We should make the enabled path explainable.

If a replacement texture is used, we should be able to explain:

- why it matched
- what original texture semantics it replaced
- how dimensions were mapped
- what coordinate/scaling rules were applied
- why the final output differs from baseline

If we cannot explain that chain, the implementation is not ready.

## On Using Other Emulators and Documentation

We should absolutely use other emulators and N64 documentation as references.

But we should use them carefully:

- use them to understand texture identity, TLUT behavior, texrect behavior, UV math, LOD choices, and pack conventions
- do not blindly transplant architecture that assumes a different renderer model
- document where we intentionally follow another implementation and where we intentionally diverge

External references should guide us, not replace thinking.

## On Forking Other Parts of the Stack

We may need forks outside the video core, including RetroArch or adjacent tooling, for autonomous testing and debugging.

Current opinion:

- do not fork higher in the stack until we can point to a concrete blocker
- prefer thin harnesses and wrappers first
- fork only where it materially improves deterministic reproduction or feature observability

Possible reasons to fork later:

- automated scene navigation
- scripted savestate load pipelines
- richer debug controls
- better frame capture hooks
- agent-friendly input / launch / capture orchestration

But that should be a justified expansion, not the first move.

## Risks

- Repeating a feature-first approach without stronger observability.
- Treating hi-res replacement and scaling as one monolithic implementation.
- Accidentally destabilizing baseline renderer behavior in the disabled path.
- Spending too long on generalized cleanup that does not directly support the renderer goals.
- Importing assumptions from other emulators that do not fit ParaLLEl-RDP's constraints.
- Underestimating texrect / LOD / coordinate edge cases.

## Open Questions

- What exact failure modes did the previous implementation hit in practice?
- Which games/scenes are the best canonical save-state fixtures for this project?
- What pack/cache format should be treated as the initial supported target?
- How much of the current replacement cache format is worth preserving?
- Where should replacement image residency and lifetime be managed?
- What is the cleanest contract between replacement texture semantics and the existing renderer/shader path?
- Which scaling bugs belong to the standard renderer versus the new feature path?

## Immediate Direction Before Multi-Phase Planning

The next step should not be "jump into implementation."

The next step should be:

1. Keep enriching this document with findings from local code review and past lessons.
2. Identify the exact status of the current hi-res prototype, including what is incomplete versus what is merely unstable.
3. Define the minimum tooling upgrades needed for safe planning.
4. Build the first stable problem statement for:
   - hi-res replacement correctness
   - scaling correctness
   - disabled-path invariants
5. Turn those into multiple multi-phase plans and choose the one with the best stability/confidence profile.

## Current Bottom Line

This project is viable.

But it should be treated as:

- a renderer redesign in a constrained area
- supported by tooling and deterministic testing
- staged across multiple phases
- aggressively protective of the disabled baseline path

The prior year of work was not wasted. It produced cleaner code, better separation, and better knowledge of what does not work. That is exactly the material we should use to make a stronger plan now.
