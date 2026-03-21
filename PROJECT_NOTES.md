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

## Research Sweep: Cross-Emulator Patterns and N64 Behavior

This section captures findings from the local reference trees:

- `/home/auro/code/emulator_references`
- `/home/auro/code/n64_docs`

The goal of this sweep was not to copy another emulator architecture blindly. The goal was to identify stable patterns that transfer well to Parallel N64, and to identify N64-specific behavior that makes some generic emulator patterns unsafe.

### Cross-Emulator Patterns That Transfer Well

Across DuckStation, PCSX2, PPSSPP, Flycast, Dolphin, and Azahar, the strongest shared pattern is this:

- keep enhancement systems narrowly scoped
- integrate them at one explicit renderer boundary
- preserve baseline/native behavior when the feature is disabled

That pattern shows up in different forms, but the architectural conclusion is consistent.

#### 1. Texture Replacement Should Be Its Own Subsystem

The strongest references here are:

- `duckstation-upstream/src/core/gpu_hw_texture_cache.cpp`
- `pcsx2-upstream/pcsx2/GS/Renderers/HW/GSTextureReplacements.cpp`
- `ppsspp-upstream/GPU/Common/TextureReplacer.cpp`
- `flycast-upstream/core/rend/CustomTexture.cpp`

Shared lessons:

- replacement discovery/loading should not be scattered across draw code
- replacement metadata, indexing, decode, reload, and dump policy should live together
- async disk/decode work should happen off the render thread
- GPU upload/final binding should still be injected through the renderer thread / renderer-owned boundary

This argues for a Parallel N64 design where hi-res replacement is a distinct subsystem with explicit responsibilities:

- key generation / identity
- replacement metadata/index lookup
- CPU-side decode/cache
- GPU residency/registry
- policy for reload / dumping / budget / eviction

#### 2. Texture Upscaling Must Be Separate From Internal Resolution Scaling

The cleanest references here are:

- `flycast-upstream/core/rend/TexCache.cpp`
- `duckstation-upstream/src/core/gpu_hw_shadergen.cpp`
- PCSX2 upscaling-fix model in the GS renderer stack

Shared lesson:

- texture upscaling is not the same problem as render/output/internal-resolution scaling

This is directly relevant to Parallel N64. If we merge these concepts too early, we lose the ability to answer whether a bug comes from:

- replacement texture identity
- replacement sampling
- texrect coordinate math
- internal upscaling math
- VI presentation behavior

This reinforces the project direction already suspected locally:

- hi-res replacement
- texture upscaling
- internal RDP upscaling
- VI presentation scaling

should be treated as distinct systems with explicit handoff points.

#### 3. Capture, Dump, and Screenshot Paths Should Be Renderer-Owned Services

The strongest references here are:

- `dolphin-upstream/Source/Core/VideoCommon/FrameDumper.cpp`
- `dolphin-upstream/Source/Core/VideoCommon/Present.cpp`
- `azahar-upstream/src/video_core/renderer_base.h`
- `azahar-upstream/src/video_core/renderer_opengl/frame_dumper_opengl.cpp`
- `ppsspp-upstream/Core/Screenshot.cpp`
- `pcsx2-upstream/pcsx2/GS/Renderers/Common/GSRenderer.cpp`

Shared lessons:

- UI code should request capture, not perform capture directly
- presentation policy should be separated from capture mechanics
- async readback/encode should be the default
- capture requests should be scheduled and deterministic

For Parallel N64, that suggests:

- frame capture should hang off a renderer-owned interface
- capture should understand whether it is grabbing:
  - native RDP output
  - upscaled RDP output
  - VI-processed output
  - dump/replay validation output
- capture should be scriptable and safe for automation

#### 4. Minimal Replayable Graphics Artifacts Are Critical

The strongest references here are:

- `pcsx2-upstream/pcsx2/GSDumpReplayer.cpp`
- `dolphin-upstream/Source/Core/Core/FifoPlayer/FifoRecorder.cpp`
- `duckstation-upstream/src/duckstation-regtest/regtest_host.cpp`
- `parallel-rdp_README.md` in local docs

Shared lesson:

- renderer work becomes dramatically more tractable when bugs can be replayed from a minimal graphics artifact instead of full gameplay repro

For Parallel N64, the direct analogue is not GS dump or GC/Wii FIFO capture. The analogue is:

- RSP/RDP command-stream-centered replay
- tightly scoped memory/TMEM/TLUT state capture
- embedded preview screenshots for triage

This is an argument for expanding the existing dump/replay story rather than treating it as optional tooling.

#### 5. Enhancement Features Should Stay Explicitly Opt-In and Isolated

The strongest references here are:

- `dolphin-upstream/Source/Core/VideoCommon/GraphicsModSystem/Runtime/GraphicsModManager.cpp`
- `duckstation-upstream/src/core/gpu_hw.cpp`
- `pcsx2-upstream/pcsx2/VMManager.cpp`

Shared lessons:

- enhanced paths should be activated deliberately
- replay/debug modes may need different guardrails than regular emulation
- native/baseline paths should not be contaminated by enhancement-specific assumptions

This matches one of the core non-negotiables for this project:

- when the feature is disabled, the core should behave like the stable baseline path

### Cross-Emulator Patterns That Do Not Transfer Cleanly

Some useful patterns should only transfer at the architectural level, not at the implementation level.

Examples:

- PS1/PS2-specific texture identifiers, VRAM hashes, CLUT naming, half-pixel offsets, and palette-draw hacks do not transfer to N64 directly.
- GameCube/Wii FIFO recording is not directly reusable. The transferable idea is minimal graphics repro capture, not the exact recorder format.
- GL-mailbox and PBO frame-dumper implementations in Azahar transfer as async readback ideas, not as concrete implementation templates.
- Hash-only replacement schemes are risky for N64 because raw texel bytes are not enough when TLUT/TMEM semantics matter.
- Generic "modern bilinear" assumptions do not transfer because N64 texture filtering behavior is special.

### N64 Behavior Findings That Matter Most

The doc sweep sharpened several areas that are likely to dominate correctness work.

#### 1. Texrects Are the Highest-Risk Primitive For Hi-Res Scaling

The most important references are:

- `n64brew_Reality_Display_Processor_Commands.html`
- `official_manual/.../gSPTextureRectangle.htm`

Important behavior:

- texrect coordinates and texture coordinates use fixed-point formats with non-trivial rounding behavior
- `COPY` / `FILL` and `1-cycle` / `2-cycle` do not agree on lower-right edge behavior
- `COPY` mode has step-size requirements tied to fetch width

Implication:

- keeping texrects at native resolution is not just a hack; it is likely a correctness-preserving strategy for a large class of HUD/sprite/menu behavior

This supports the current existing quirk in `rdp_tex_rect_policy.hpp`.

#### 2. TMEM / Tile / TLUT State Is Part Of Texture Meaning

The most important references are:

- `n64brew_Reality_Display_Processor_Commands.html`
- `official_manual/.../pro14/14-03.htm`
- `official_manual/.../qa/graphics/texture.htm`

Important behavior:

- TMEM is only 4 KB and layout-sensitive
- tile fields are not cosmetic metadata; they change how texture data is interpreted
- CI/TLUT behavior changes the semantic identity of what is sampled
- `LoadBlock`, `LoadTile`, and `LoadTLUT` all have fragile edge conditions

Implication:

- hi-res replacement identity for N64 cannot be a naive decoded-texture hash
- replacement keys must account for TLUT/palette state where relevant
- this validates the current direction of shadowing TLUT state and including palette CRC in lookup keys

#### 3. N64 Filtering Is Not Generic Bilinear

The most important references are:

- `official_manual/.../pro14/14-01.htm`
- `official_manual/.../gDPSetTextureFilter.htm`

Important behavior:

- `G_TF_BILERP` is the characteristic N64 3-point triangular filter
- some exact averaging behavior is a special case rather than the default

Implication:

- enhanced replacement/upscale paths cannot assume modern GPU bilinear is visually equivalent
- if we bind hi-res textures and sample them with ordinary bilinear while the original content expected N64 filtering behavior, edges, UI, and mip transitions will drift

#### 4. LOD And Mip Behavior Is Tile-Relative

The most important references are:

- `official_manual/.../tutorial/graphics/9/9_3.htm`
- `official_manual/.../tutorial/graphics/9/9_6.htm`
- `official_manual/.../tutorial/graphics/9/9_7.htm`
- `official_manual/.../gDPSetTextureLOD.htm`

Important behavior:

- LOD chooses relative tile pairs, not generic image mips in the modern sense
- detail/sharpen behavior depends on neighboring tile layout
- texrect behavior can differ from ordinary primitive assumptions

Implication:

- future hi-res replacement support should expect LOD-sensitive content to require more than a flat single-texture replacement model
- grouping or expressing replacement assets relative to primitive-tile/mip relationships may become necessary

#### 5. VI Is The Real Presentation Stage

The most important references are:

- `n64brew_Video_Interface.html`
- local `video_interface.*` and `vi_*policy*` files in Parallel N64

Important behavior:

- VI applies final scaling and presentation behavior
- VI is responsible for resample/AA/divot/dedither/gamma/interlace-domain effects
- `ORIGIN`, `WIDTH`, `X_SCALE`, `Y_SCALE`, and field handling all matter directly
- mid-frame VI changes matter

Implication:

- hi-res RDP work must not bypass VI semantics
- keeping RDP enhancement separate from VI scanout/presentation is the right direction
- any stable design must continue to treat VI as the final authority on presentation behavior

### Strongest Direct Implications For Parallel N64

At this point, the strongest actionable conclusions are:

- Treat hi-res replacement as a dedicated subsystem, not a scattered renderer feature.
- Treat texture upscaling, internal RDP upscaling, and VI presentation scaling as separate systems.
- Keep texrect/native-resolution behavior as an explicit correctness mode, likely on by default for risky paths.
- Continue including TLUT/palette state in replacement identity.
- Do not assume modern bilinear filtering is acceptable for enhanced paths.
- Treat renderer-owned async capture and minimal replay artifacts as first-class infrastructure, not optional tooling.
- Prefer per-game/per-scene fix metadata over global hacks when upscale correctness diverges.
- Build automation around deterministic capture, replay, savestates, and preview images.

### Most Useful Reference Files To Revisit Later

For texture replacement / upscaling architecture:

- `/home/auro/code/emulator_references/duckstation-upstream/src/core/gpu_hw_texture_cache.cpp`
- `/home/auro/code/emulator_references/pcsx2-upstream/pcsx2/GS/Renderers/HW/GSTextureReplacements.cpp`
- `/home/auro/code/emulator_references/ppsspp-upstream/GPU/Common/TextureReplacer.cpp`
- `/home/auro/code/emulator_references/flycast-upstream/core/rend/TexCache.cpp`
- `/home/auro/code/emulator_references/flycast-upstream/core/rend/CustomTexture.cpp`

For capture / dump / automation / replay:

- `/home/auro/code/emulator_references/dolphin-upstream/Source/Core/VideoCommon/FrameDumper.cpp`
- `/home/auro/code/emulator_references/dolphin-upstream/Source/Core/Core/FifoPlayer/FifoRecorder.cpp`
- `/home/auro/code/emulator_references/duckstation-upstream/src/duckstation-regtest/regtest_host.cpp`
- `/home/auro/code/emulator_references/pcsx2-upstream/pcsx2/GSDumpReplayer.cpp`
- `/home/auro/code/emulator_references/ppsspp-upstream/headless/Headless.cpp`
- `/home/auro/code/emulator_references/azahar-upstream/src/video_core/renderer_base.h`

For N64 behavior:

- `/home/auro/code/n64_docs/n64brew_Reality_Display_Processor_Commands.html`
- `/home/auro/code/n64_docs/n64brew_Reality_Display_Processor_Pipeline.html`
- `/home/auro/code/n64_docs/n64brew_Video_Interface.html`
- `/home/auro/code/n64_docs/official_manual/N64OnlineManuals51/n64man/gsp/gSPTextureRectangle.htm`
- `/home/auro/code/n64_docs/official_manual/N64OnlineManuals51/pro-man/pro14/14-01.htm`
- `/home/auro/code/n64_docs/official_manual/N64OnlineManuals51/pro-man/pro14/14-02.htm`
- `/home/auro/code/n64_docs/official_manual/N64OnlineManuals51/pro-man/pro14/14-03.htm`

### New Planning Bias From This Research

This research changes the planning bias in a few important ways.

Before this sweep, a reasonable fear was that the project might need one giant, tightly coupled rendering redesign.

After this sweep, the better bias is:

- design a narrow replacement subsystem
- preserve texrect/native correctness aggressively
- make scaling behavior explicit rather than implicit
- push capture/replay/testing infrastructure much earlier in the project
- treat VI as a hard boundary
- accept that some feature areas may need per-game/per-scene policy rather than one universal rule

That is a much more manageable shape than a single monolithic "hi-res plus scaling" implementation.
