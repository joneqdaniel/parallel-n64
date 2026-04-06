# Making Hi-Res Work for Any Game

## Situation Assessment

This project has spent significant effort on the right fundamental insight — that
ParaLLEl RDP (LLE) sees textures differently than Glide64/Rice (HLE) — but the
execution went sideways into bespoke per-game analysis tooling instead of making
the general case work first.

**What works today:**
- Legacy `.hts` pack lookup gets 91% hits on Paper Mario title screen (178/196)
- The Rice CRC texture hash is already correct (same algorithm, same RDRAM data)
- The PHRB binary format is well-designed for runtime consumption
- The fixture/scenario framework is solid for regression testing
- The renderer code is clean with a dual lookup path (authored + sampled)

**What doesn't work:**
- Paper Mario file-select only gets 50% hits (82/165) — CI palette mismatches
- `LoadBlock` shape mismatches (64x1 upload keyed differently than 16x16 sampled)
- The sampled-object lookup is behind a debug env var, not production
- 39 Python tools require ~15-25 person-days of manual work per game
- No path to "any game" — everything is Paper-Mario-specific

**Root cause of the gap:**
The texture CRC is fine. The problems are (1) palette CRC mismatch for CI textures,
and (2) upload-shape vs sampled-shape mismatch for LoadBlock textures. These are
general N64 problems, not Paper Mario problems, and should be solved generically.

---

## Strategy: Fix the Bugs, Build the Converter, Then Decide the Architecture

The project's previous 200-commit failure was caused by premature architecture:
redesigning the runtime contract before the actual identity bugs were understood.
This plan inverts that pattern — fix the concrete, measurable problems first, use
the results to make informed architectural decisions, and defer structural redesign
until evidence demands it.

**Sequencing principle:** Every step must produce a testable improvement or a
concrete decision. No step should be a multi-week refactor with no observable
outcome. If a step doesn't move hit rates or produce a classification verdict,
it doesn't belong in the early sequence.

**Runtime format:** PHRB is the right runtime format — it's cleaner, faster, and
carries richer identity than legacy `.hts`/`.htc`. But the path to PHRB must be a
**single generic converter** that works for any game, not a 39-tool pipeline
requiring manual policy per game.

**Architectural guardrail:** The converter and runtime must not collapse PHRB into
a container for mostly legacy-shaped runtime keys. Records must carry all identity
fields the format supports, even when the runtime initially keys on a subset. This
ensures the format is ready for structured sampled-object lookup when that ships
later, without requiring re-conversion.

**The tool:** `hts2phrb` — one command, one input, one output.

```
hts2phrb "PAPER MARIO_HIRESTEXTURES.hts" --output paper-mario.phrb
```

No policy files. No per-game tuning. No surface packages. Just conversion.

---

## Step 1: Match GlideN64's Palette CRC Exactly

**Problem:** ParaLLEl's CI palette CRC doesn't match what pack creators used.

**Root cause analysis:** GlideN64 computes the hi-res palette CRC like this:

```
// On LoadTLUT:
gDP.TexFilterPalette = raw RDRAM copy (2 bytes per entry, contiguous)

// On hi-res lookup (CI4):
palette_data = gDP.TexFilterPalette + (tile->palette << 4)   // 16 entries
rice_crc = RiceCRC32(palette_data, cimax+1, 1, 2, 32)

// On hi-res lookup (CI8):
palette_data = gDP.TexFilterPalette                           // 256 entries
rice_crc = RiceCRC32(palette_data, cimax+1, 1, 2, 512)

// Combined key:
checksum64 = (palette_rice_crc << 32) | texture_rice_crc
```

**What ParaLLEl does:** Uses `rice_crc32_wrapped` on `tlut_shadow` (also RDRAM bytes).
The algorithm is the same. The question is whether `tlut_shadow` contains the same
bytes as `TexFilterPalette` at lookup time.

**Key differences to investigate:**
1. `TexFilterPalette` is populated from raw RDRAM on LoadTLUT via simple `memcpy`
2. `tlut_shadow` is also populated from raw RDRAM, but the offset/range logic has
   been patched multiple times and may not match GlideN64's simpler `memcpy`
3. For CI4, GlideN64 indexes by `palette << 4` (16 entries x 2 bytes = 32 bytes),
   ParaLLEl indexes by `bank * 32` — should match if `palette == bank`
4. For CI8, GlideN64 uses the full `TexFilterPalette` (512 bytes),
   ParaLLEl uses `tlut_shadow` from offset 0 with stride 512

**Action items:**
- [ ] Add a debug comparison mode that logs both ParaLLEl's computed palette CRC
      and what GlideN64's algorithm would produce given the same RDRAM state
- [ ] Run on Paper Mario file-select and identify exactly where the CRCs diverge
- [ ] Fix `tlut_shadow` population to match `TexFilterPalette` semantics exactly
- [ ] Verify CI4 bank offset math matches GlideN64's `palette << 4` indexing
- [ ] Verify CI8 entry-count logic matches GlideN64's `cimax + 1` computation
- [ ] Validate: file-select hits should jump from 82 to ~150+ after fix

**Key files:**
- GlideN64 palette CRC: `~/code/gliden64-upstream/src/GLideNHQ/TxUtil.cpp:82-116`
- GlideN64 TexFilterPalette: `~/code/gliden64-upstream/src/gDP.cpp:758-767`
- GlideN64 hi-res lookup: `~/code/gliden64-upstream/src/Textures.cpp:1210-1228`
- ParaLLEl palette CRC: `parallel-rdp/rdp_hires_ci_palette_policy.hpp:549-577`
- ParaLLEl tlut_shadow: `parallel-rdp/rdp_renderer.cpp:4100-4150`
- ParaLLEl texture CRC: `parallel-rdp/texture_keying.hpp:30-58`

**Success criteria:** Paper Mario file-select CI palette CRC matches GlideN64's
computation for the same RDRAM state.

**If the fix is partial** (hits reach 60-65% instead of 85%+): do not spiral into
per-case debugging. Log the remaining misses, classify them by cause, and proceed
to Step 2. The classification gate at Step 2.5 will determine whether the partial
fix is a native identity fact or a dead end.

---

## Step 2: Add LoadBlock Dimension Reinterpretation

**Problem:** Some textures are uploaded via `LoadBlock` as e.g. 64x1 but sampled as
16x16 CI4 via `SetTile`/`SetTileSize`. The pack keys them as 16x16, ParaLLEl keys
them as 64x1.

**Why this happens:** `LoadBlock` treats TMEM as a flat buffer and uses `dxt` to
define the line stride for odd-line interleaving. The actual sampled dimensions come
from `SetTile`/`SetTileSize`, which may describe a completely different shape. Pack
creators (using Rice/Glide64) saw the texture as its final sampled shape, not as the
raw upload shape.

**This needs to be solved in two places:**

### 2a. In the runtime lookup (for direct `.hts` fallback during development)

When the primary RDRAM CRC lookup misses on a `LoadBlock` upload, compute the
sampled dimensions from the tile descriptor and retry:

```
if (miss && upload_was_loadblock) {
    sampled_w = (tile.sh - tile.sl + 4) >> 2;
    sampled_h = (tile.th - tile.tl + 4) >> 2;
    sampled_fmt = tile.fmt;
    sampled_siz = tile.siz;

    texture_crc = rice_crc32_wrapped(rdram, rdram_size, src_addr,
                                     sampled_w, sampled_h, sampled_siz,
                                     sampled_stride);
    retry_result = provider->lookup(checksum64, formatsize_from_sampled);
}
```

### 2b. In the generic converter (`hts2phrb`)

When emitting PHRB records from legacy pack entries, detect LoadBlock-shaped entries
(where the legacy key dimensions don't match what a LoadBlock upload would produce)
and emit records keyed to both the legacy shape AND the upload shape. This way the
PHRB runtime lookup hits regardless of which view the renderer uses.

**Action items:**
- [ ] Track which uploads are `LoadBlock` vs `LoadTile` (already partially done)
- [ ] Implement sampled-dimension retry in the runtime lookup path
- [ ] Implement dual-key emission in the converter
- [ ] Validate: the dominant 64x1 fs514 miss family should resolve
- [ ] Verify no false positives on title screen (which is already 91% hits)

**False positive risk:** Games with heavy LoadBlock traffic (Zelda OoT, GoldenEye)
could theoretically surface CRC collisions where the reinterpreted shape matches the
wrong texture. The retry-on-miss design limits this — only fires when the primary
lookup fails — but Step 6 must explicitly validate against this risk.

**Success criteria:** Paper Mario file-select block-class misses resolve.

---

## Step 2.5: Identity Classification Gate

After Steps 1-2 are validated on Paper Mario, explicitly classify the results.

**Are the palette CRC fix and LoadBlock reinterpretation:**

1. **Native identity facts** — meaning they represent how N64 textures actually work,
   and should be baked into the PHRB format and converter as canonical behavior.
2. **Bounded compatibility helpers** — meaning they're workarounds for legacy pack
   authoring conventions, and should stay as explicit secondary runtime behavior
   behind a mode flag, not baked into the default path.
3. **Dead ends** — meaning they don't materially improve hit rates or introduce
   false positives, and should be dropped.

### Classification Rules

- Classify as **native identity fact** only if it reflects canonical N64 texture
  identity across games — not just a legacy pack lookup convention.
- Classify as **bounded compatibility helper** if it materially improves legacy-pack
  behavior but should remain explicit secondary behavior.
- Classify as **dead end** if it does not generalize cleanly, introduces false
  positives, or does not materially improve results.

### What Happens After Classification

- **Native fact**: Baked into the converter as default behavior. Baked into the
  runtime as the primary lookup path. No mode flag needed.
- **Bounded helper**: Lives behind an explicit `--compat` flag in the converter
  and an explicit compatibility mode in the runtime. Not active by default.
  Documented as secondary behavior, not the canonical identity path.
- **Dead end**: Removed. No further work.

### Exit Criteria

- Both investigations have a written classification outcome with supporting data
  (hit rates before/after, false positive count, generality assessment).
- The converter and runtime plans reflect those classifications explicitly.
- No compatibility seam is promoted into canonical runtime identity without passing
  this gate.

---

## Step 3: Build the Generic Converter

**Goal:** A single tool that converts any `.hts`/`.htc` to `.phrb` with no per-game
configuration.

### Design Principles

**Structured records, not legacy repackaging.** The converter must NOT simply wrap
Rice CRC keys in PHRB packaging — that would make PHRB a glorified `.hts` wrapper.
Each emitted PHRB record carries **all identity fields the format supports**, even
if the runtime initially only keys on `checksum64 + formatsize` for lookup.

**Converter non-goals** (from Codex's plan, adopted as hard constraints):
- Do not collapse PHRB into a container for mostly legacy-shaped runtime keys just
  to make conversion simpler.
- Do not turn auto-conversion convenience into a substitute for fixing the
  provider/runtime identity contract.
- Do not pretend currently unknown sampled-object fields are known just to make the
  first converter output look complete.

### Record Structure

- **Populated from the legacy entry:** `sampled_low32` (= Rice texture CRC),
  palette CRC (corrected per classification gate), `formatsize`, dimensions, RGBA data
- **Populated as derivable defaults:** `fmt`, `siz` (extracted from `formatsize`)
- **Left as zero/unknown for now:** `tile`, `tmem offset`, `line stride`, `tlut_type`
- **Explicit flags:** which fields are populated vs zero-defaulted, so the runtime
  can distinguish "field is zero" from "field was not available at conversion time"

This means:
- Records are ready for structured sampled-object lookup when that ships later
- No re-conversion needed when the runtime key model evolves
- The converter is an orchestration layer, not a dumbed-down shortcut

### What it does:
1. Parse all entries from the legacy pack (reusing `hires_pack_common.py`)
2. For each entry, emit a PHRB record with all available identity fields
3. Apply palette CRC behavior per the classification gate outcome
4. For entries classified as LoadBlock-shaped, emit reinterpreted-dimension
   variants per the classification gate outcome
5. For CI entries with multiple palette variants in the pack, emit all variants
   as separate PHRB records (the runtime picks the matching one)
6. Emit warnings and diagnostics for ambiguous cases instead of silently
   broadening runtime behavior

### What it does NOT do:
- No per-game policy files
- No manual transport selection
- No surface package modeling
- No ordered-slot analysis
- No ROM scanning (that's a future enhancement via `--enrich` flag)

### Enrichment path (future, not required for initial converter):

The same `hts2phrb` front door should eventually support optional enrichment:

```
# Basic: generic conversion, works for any game
hts2phrb pack.hts -o pack.phrb

# Enriched: ROM-scan fills in tile/tmem/line/tlut_type fields
hts2phrb pack.hts --rom game.z64 -o pack.phrb

# Policy-assisted: for games with known ambiguities
hts2phrb pack.hts --policy game-policy.json -o pack.phrb
```

The basic path must work with zero extra inputs. Enrichment and policy are opt-in
for games that need them, accessed through the same front door.

### Ambiguity handling:
- If multiple legacy entries map to the same PHRB key, emit all of them and let
  the runtime pick the first match (or use replacement dimensions as tiebreaker)
- Log warnings for ambiguous cases so users can investigate if needed
- This handles 95%+ of real packs where entries are unambiguous

### Action items:
- [ ] Build `hts2phrb` as a single Python script reusing `hires_pack_common.py`
      and existing PHRB emission code from `hires_pack_emit_binary_package.py`
- [ ] Emit structured PHRB records with all available identity fields, not just
      legacy checksum64
- [ ] Test on Paper Mario pack — output should reproduce the current hit rates
- [ ] Test on a second game's pack (OoT, MM, SM64)
- [ ] Ensure the converter runs in under 60 seconds for typical pack sizes (~2GB)

**Success criteria:** `hts2phrb pack.hts -o pack.phrb` works for any game's pack,
and the output records carry structured identity ready for future runtime upgrades.

---

## Step 4: Broaden Validation Within Paper Mario

Before going cross-game, validate within Paper Mario beyond menu screens.

### Validation requirements:
- [ ] Promote one deterministic non-menu Paper Mario scene to an authoritative
      fixture (the `960`-frame timeout slice reaching `kmr_03` is already proven
      deterministic)
- [ ] Keep title and file-select strict fixtures as baseline gates
- [ ] Add class-based assertions on top of image hashes:
  - One texrect-dominated case (title screen strip replacement)
  - One block-dominated case (file-select CI4 block family)
  - One CI/TLUT-sensitive case (file-select palette-dependent textures)
- [ ] Verify the converted PHRB package matches or exceeds legacy `.hts` hit rates
      across all three fixture classes
- [ ] Make semantic hi-res evidence (from `hires-evidence.json`) part of the
      pass/fail gate, not just a sidecar artifact — assert on expected exact, compat,
      conflict, unresolved, or class-presence signals
- [ ] Resolve authority-graph and fixture metadata drift where expected capture hashes
      disagree across planning files, fixtures, and runtime env files

### Negative data requirement:
- [ ] Record at least one intentionally rejected fallback or unresolved family as
      explicit negative data before declaring the architecture ready. The test suite
      must prove it can say "no" as well as "yes."

**Success criteria:** Non-menu Paper Mario scene passes with converted PHRB.
Semantic evidence participates in gating. At least one negative case is documented.

---

## Step 5: Make PHRB the Default Runtime Path

**After** the converter is proven on Paper Mario menu + non-menu scenes:

- [ ] Make `.phrb` the default runtime format
- [ ] Add auto-conversion: if user provides `.hts`, convert to `.phrb` on first load
      and cache the result (like GlideN64's `.htc` compilation)
- [ ] Keep direct `.hts` loading as a development/debug fallback
- [ ] Remove debug env var gates — the improved lookup should be the default
- [ ] Document the user-facing workflow: drop pack in system dir, enable hi-res, play

### Compatibility fencing:
- [ ] Any behavior classified as "bounded compatibility helper" at Step 2.5 must
      live behind an explicit runtime mode flag, not in the default path
- [ ] Compatibility behavior must be disableable without changing native PHRB semantics
- [ ] Native package success on active fixtures must not depend on implicit
      compatibility broadening

**Success criteria:** Zero-configuration hi-res for Paper Mario with legacy pack.
Compatibility behavior, if any, is cleanly fenced.

---

## Step 6: Validate on a Second Game

**Problem:** All current validation is Paper Mario only. Need proof of generality.

### Requirements:
- [ ] Pick a second game with a well-known Rice-format hi-res pack
      (Zelda OoT or Mario 64 are good candidates — large community packs exist)
- [ ] The second game must exercise a **materially different runtime class profile**
      than Paper Mario — not just another texrect/UI-heavy scene. Look for games
      with heavy 3D texture use, multi-tile composites, or different CI/TLUT patterns.
- [ ] Build a minimal fixture (savestate + scenario) for one representative scene
- [ ] Run with auto-converted PHRB and the fixed lookup
- [ ] Compare hit rate against GlideN64 on the same scene
- [ ] Document any new miss classes that don't appear in Paper Mario
- [ ] Explicitly validate that LoadBlock reinterpretation does not produce false
      positives in the second game's texture traffic

### Gate:
The second game must work without adding new core runtime key rules. If it requires
game-specific logic, the converter or runtime has a gap that needs fixing
generically, not per-game.

**What "no per-game policy" means in practice:** The converter's zero-config path
must handle the second game. If ambiguous cases exist that the basic path cannot
resolve, those must be handled through the `--policy` enrichment flag — not by
adding game detection to the core converter or runtime. The `--policy` path is an
escape hatch for edge cases, not a requirement for normal operation.

**Success criteria:** Second game achieves comparable hit rate to GlideN64 with
zero game-specific tooling. The generic converter handles it with no new rules.

---

## Step 7: Add Direct Tests

Recover the most valuable test discipline from the failed attempt without reviving
its architecture.

### Test targets:
- [ ] PHRB parsing and loading (round-trip: emit → load → verify)
- [ ] Provider lookup behavior (exact hit, miss, CI fallback)
- [ ] Converter identity preservation (legacy entry → PHRB record → correct key)
- [ ] LoadBlock reinterpretation (known miss → retry → hit)
- [ ] Palette CRC computation (ParaLLEl vs GlideN64 parity)
- [ ] Selector-bearing native package records (if applicable after Step 8)
- [ ] Compatibility alias fencing (compat behavior does not fire when disabled)

### Design constraints:
- Tests must run without the emulator or a game ROM
- Reuse ideas from the failed branch's replacement-provider tests, but not its
  runtime mode matrix
- No ownership or consumer policy layering in test fixtures

**Success criteria:** Runtime/package regressions caught without full emulator runs.
Provider correctness is testable independently from Paper Mario fixture behavior.

---

## Step 8: Structured Sampled-Object Key Decision

After Steps 1-7, the runtime has working `checksum64 + formatsize` lookup with
corrected CRCs, a generic converter, and cross-game validation. Now decide whether
to redesign the provider lookup to use structured sampled-object keys.

### Decision inputs:
- What miss classes remain after CRC fixes and LoadBlock reinterpretation?
- Do any remaining misses require identity fields beyond `checksum64 + formatsize`?
- Does ROM-scan enrichment (filling in `tile`, `tmem`, `line`, `tlut_type`) resolve
  cases that the CRC-based path cannot?
- Is the remaining miss rate low enough that structured keys are an optimization
  rather than a necessity?

### If structured keys are needed:
- Redesign the provider lookup (Codex's Phase A) using the identity fields already
  carried in PHRB records — `fmt`, `siz`, `tile`, `tmem`, `line`, `logical size`,
  palette identity, `tlut_type`
- The converter already emits these fields (zero-defaulted when unknown), so no
  re-conversion is needed
- Build the ROM-scan enrichment path (`hts2phrb --rom game.z64`) to populate
  the currently-unknown fields
- Preserve `checksum64 + formatsize` as a compatibility fallback for records that
  lack structured fields

### If structured keys are not needed:
- Document why the CRC-based path is sufficient
- Keep the structured fields in PHRB records for future use
- Close this step with a written decision

### Other possible enhancements:
- **Native pack authoring**: Future pack creators could author directly against
  sampled-object identity for perfect LLE alignment. The PHRB format already
  supports this — it just needs documentation and tooling.
- **Performance**: PHRB's sorted numeric keys enable binary search at runtime,
  avoiding the Rice CRC computation on every draw call. This matters for
  performance-sensitive scenarios.

---

## What to Keep from Current Work

- **PHRB binary format** — becomes the runtime standard
- **Fixture/scenario framework** — essential for regression testing
- **Evidence bundle infrastructure** — useful for debugging new games
- **Rice CRC implementation** — already correct for textures
- **Renderer integration** — clean descriptor-indexed replacement path
- **`hires_pack_common.py`** — core parsing, reused by converter
- **Sampled-object identity model** — future ROM-scan enrichment path

## What to Deprioritize

- **38 of the 39 Python tools** — replace with single `hts2phrb` converter
- **Per-family transport policy** — manual curation doesn't scale
- **Surface package ordered-slot model** — over-engineered for the current problem
- **Paper Mario decomp-backed static scans** — useful research but not the fix path
- **Per-low32 import policies** — converter should handle this automatically
- **Proxy/bridge binding machinery** — unnecessary with correct CRC computation

## What to Revive from the Failed Attempt

- Replacement-provider parser/decode/lookup tests
- Selected offline comparison and provenance tooling

## What NOT to Revive

- Runtime lookup-mode matrix
- Ownership and consumer policy explosion
- Frontend-exposed heuristic controls as product features
- Permissive reinterpretation as the normal path

---

## Estimated Effort

| Step | Effort | Risk |
|------|--------|------|
| 1. Fix palette CRC | 2-4 days | Low — GlideN64 source is clear reference |
| 2. LoadBlock reinterpretation | 2-3 days | Medium — stride/dxt needs care |
| 2.5. Identity classification gate | 0.5 day | N/A — decision point |
| 3. Generic converter | 3-5 days | Low — reuses existing parsing code |
| 4. Paper Mario non-menu validation | 2-3 days | Low — fixtures already exist |
| 5. Default path promotion | 1-2 days | Low — mostly wiring and cleanup |
| 6. Second game validation | 2-3 days | Medium — new miss classes possible |
| 7. Direct tests | 2-3 days | Low — clear scope |
| 8. Structured key decision | 0.5-5 days | Depends on Step 1-7 results |

**Total: ~16-28 days to a working, tested, "any game" path with PHRB as runtime.**

---

## Decision Gates

The project should not declare the runtime ready until all of:

1. PHRB is the default runtime format with auto-conversion from `.hts`
2. Palette CRC behavior is classified and integrated per the gate at Step 2.5
3. LoadBlock reinterpretation is classified and integrated per the gate at Step 2.5
4. One non-menu Paper Mario fixture passes with converted PHRB
5. Semantic hi-res evidence participates in pass/fail gating
6. One second game works without game-specific rules, exercising a different
   runtime class profile than Paper Mario
7. Direct provider/package/converter tests exist
8. Compatibility behavior (if any) is explicitly fenced behind a mode flag
9. At least one unresolved or rejected case is documented as negative data
10. The Step 8 structured-key decision is recorded with supporting evidence

---

## Risk Mitigations

### If the palette CRC fix is partial (60-65% instead of 85%+):
The classification gate at Step 2.5 catches this. Do not spiral into per-case
debugging. Log the remaining misses by class, determine if `tlut_shadow` diverges
from `TexFilterPalette` for structural reasons (timing, partial TMEM updates,
multi-frame palette cycling), and classify accordingly. A partial fix that's a
native identity fact is still worth shipping — the remaining gap may require
structured keys (Step 8) rather than more CRC patching.

### If "no per-game policy" breaks on the second game:
This is a strong claim. Real packs have per-game quirks (duplicate Rice CRCs,
game-specific TLUT cycling). If the second game requires policy, the escape hatch
is the `--policy` enrichment flag — not new core runtime rules. If even the
enrichment flag is insufficient, that's a signal that the converter design needs
broadening, and the right response is to fix the converter generically.

### If LoadBlock reinterpretation produces false positives at scale:
The retry-on-miss design limits exposure, but games with heavy LoadBlock traffic
could surface collisions. Step 6 must explicitly test for this. If false positives
appear, the reinterpretation gets classified as a bounded compat helper (behind a
flag) rather than a native fact.

---

## Open Questions

1. **Does `tlut_shadow` actually contain different bytes than `TexFilterPalette`?**
   Step 1 will answer this definitively. If the bytes match, the palette CRC fix is
   trivial. If they don't, we need to understand exactly why.

2. **Are there games where LoadBlock reinterpretation produces false positives?**
   Step 2 should validate this on Paper Mario, Step 6 on a second game. The
   reinterpretation only fires on misses, so false positives would require a
   different texture with the same reinterpreted CRC.

3. **Is there a class of textures where neither Rice CRC nor reinterpretation works?**
   Copy-mode draws, framebuffer-derived textures, and procedurally generated content
   may fall into this category. These should be explicitly excluded from replacement
   rather than guessed at.

4. **Can auto-conversion at first load be fast enough?**
   A 2GB `.hts` pack needs to be parsed, CRC-corrected, and written as `.phrb` in
   a reasonable time. If this takes minutes, it should be a one-time operation with
   the result cached. If it takes seconds, it can happen transparently.

5. **What percentage of real packs have entries that genuinely need per-game policy?**
   If it's <5%, the generic converter is vindicated. If it's >15%, the `--policy`
   enrichment path becomes load-bearing and needs more design attention.
