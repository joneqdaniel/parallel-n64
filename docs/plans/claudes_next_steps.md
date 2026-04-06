# Claude's Next Steps: Making Hi-Res Work for Any Game

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

## Strategy: PHRB as Runtime Format, Generic Automatic Conversion

PHRB is the right runtime format — it's cleaner, faster, and carries richer identity
than legacy `.hts`/`.htc`. But the path to PHRB must be a **single generic converter**
that works for any game, not a 39-tool pipeline requiring manual policy per game.

The converter needs to solve two identity problems during conversion:

1. **Palette CRC**: Compute the palette CRC exactly as GlideN64 does, so CI texture
   entries in the legacy pack map to the correct runtime keys.
2. **LoadBlock dimensions**: Detect entries that were keyed by their sampled tile
   shape (how Rice/Glide64 saw them) vs their upload shape (how ParaLLEl sees the
   raw LoadBlock), and emit PHRB records with the correct identity for both views.

If the converter handles these two cases, most legacy pack entries convert 1:1 with
no ambiguity and no human intervention. The remaining edge cases (same Rice CRC used
with multiple SetTile configs) can be handled as automatic best-effort or documented
misses.

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

**Success criteria:** Paper Mario file-select block-class misses resolve.

---

## Step 2.5: Identity Classification Gate

After Steps 1-2 are validated on Paper Mario, explicitly classify the results:

**Are the palette CRC fix and LoadBlock reinterpretation:**
- **Native identity facts** — meaning they represent how N64 textures actually work,
  and should be baked into the PHRB format and converter as canonical behavior?
- **Bounded compatibility helpers** — meaning they're workarounds for legacy pack
  authoring conventions, and should stay as explicit secondary runtime behavior?
- **Dead ends** — meaning they don't materially improve hit rates or introduce
  false positives, and should be dropped?

The answer determines whether these fixes live in the converter (native facts),
the runtime fallback path (compat helpers), or nowhere (dead ends).

**Expected outcome:** Both are native identity facts. The palette CRC fix is
correcting a bug in ParaLLEl's CRC computation. The LoadBlock reinterpretation
reflects how the N64 hardware actually maps uploads to sampled tiles. Neither is
a compatibility hack — they're accuracy improvements.

---

## Step 3: Build the Generic Converter

**Goal:** A single tool that converts any `.hts`/`.htc` to `.phrb` with no per-game
configuration.

**What it does:**
1. Parse all entries from the legacy pack
2. For each entry, emit a PHRB record with:
   - `sampled_low32` = the legacy texture CRC (Rice CRC)
   - Palette CRC computed with corrected GlideN64-compatible algorithm
   - `formatsize` preserved from legacy entry
   - RGBA pixel data extracted and stored as raw blob
3. For entries that look like LoadBlock-shaped uploads (detectable from dimensions
   and formatsize), also emit a reinterpreted-dimension variant
4. For CI entries with multiple palette variants in the pack, emit all variants
   as separate PHRB records (the runtime picks the matching one)

**What it does NOT do:**
- No per-game policy files
- No manual transport selection
- No surface package modeling
- No ordered-slot analysis
- No ROM scanning (that's a future enhancement)

**Ambiguity handling:**
- If multiple legacy entries map to the same PHRB key, emit all of them and let
  the runtime pick the first match (or use replacement dimensions as tiebreaker)
- Log warnings for ambiguous cases so users can investigate if needed
- This handles 95%+ of real packs where entries are unambiguous

**Action items:**
- [ ] Build `hts2phrb` as a single Python script reusing `hires_pack_common.py`
- [ ] Test on Paper Mario pack — output should reproduce the current hit rates
- [ ] Test on a second game's pack (OoT, MM, SM64)
- [ ] Ensure the converter runs in under 60 seconds for typical pack sizes (~2GB)

**Success criteria:** `hts2phrb pack.hts -o pack.phrb` works for any game's pack.

---

## Step 4: Broaden Validation Within Paper Mario

Before going cross-game, validate within Paper Mario beyond menu screens.

**Action items:**
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

**Success criteria:** Non-menu Paper Mario scene passes with converted PHRB.

---

## Step 5: Make PHRB the Default Runtime Path

**After** the converter is proven on Paper Mario menu + non-menu scenes:

- [ ] Make `.phrb` the default runtime format
- [ ] Add auto-conversion: if user provides `.hts`, convert to `.phrb` on first load
      and cache the result (like GlideN64's `.htc` compilation)
- [ ] Keep direct `.hts` loading as a development/debug fallback
- [ ] Remove debug env var gates — the improved lookup should be the default
- [ ] Document the user-facing workflow: drop pack in system dir, enable hi-res, play

**Success criteria:** Zero-configuration hi-res for Paper Mario with legacy pack.

---

## Step 6: Validate on a Second Game

**Problem:** All current validation is Paper Mario only. Need proof of generality.

**Action items:**
- [ ] Pick a second game with a well-known Rice-format hi-res pack
      (Zelda OoT or Mario 64 are good candidates — large community packs exist)
- [ ] Build a minimal fixture (savestate + scenario) for one representative scene
- [ ] Run with auto-converted PHRB and the fixed lookup
- [ ] Compare hit rate against GlideN64 on the same scene
- [ ] Document any new miss classes that don't appear in Paper Mario

**Gate:** The second game must work without adding new core runtime key rules.
If it requires game-specific logic, the converter or runtime has a gap that needs
fixing generically, not per-game.

**Success criteria:** Second game achieves comparable hit rate to GlideN64 with
zero game-specific tooling.

---

## Step 7: Add Direct Tests

Recover the most valuable test discipline from the failed attempt without reviving
its architecture.

**Action items:**
- [ ] Add unit tests for PHRB parsing and loading (round-trip: emit → load → verify)
- [ ] Add unit tests for provider lookup behavior (exact hit, miss, CI fallback)
- [ ] Add unit tests for the converter (legacy entry → PHRB record identity)
- [ ] Add integration tests for LoadBlock reinterpretation (known miss → retry → hit)
- [ ] Add integration tests for palette CRC computation (ParaLLEl vs GlideN64 parity)

These tests should run without the emulator or a game ROM.

**Success criteria:** Runtime/package regressions caught without full emulator runs.

---

## Step 8: Decide What Else PHRB Needs

After Steps 1-7, reassess what the sampled-object model adds beyond the generic
converter. Possible enhancements:

- **ROM-scan enrichment**: A future tool could parse a game's ROM display lists and
  emit PHRB records with full sampled-object identity (tile state, TMEM layout).
  This would resolve the remaining ambiguous cases where Rice CRC is insufficient.
  But this is an enhancement, not a requirement.

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
| 6. Second game validation | 2-3 days | Low — just needs a pack and savestate |
| 7. Direct tests | 2-3 days | Low — clear scope |
| 8. PHRB enhancement decision | 0.5 day | N/A — decision point |

**Total: ~14-24 days to a working, tested, "any game" path with PHRB as runtime.**

---

## Decision Gates

The project should not declare the runtime ready until all of:

1. PHRB is the default runtime format with auto-conversion from `.hts`
2. Palette CRC matches GlideN64 for CI textures
3. LoadBlock reinterpretation is classified and integrated appropriately
4. One non-menu Paper Mario fixture passes with converted PHRB
5. One second game works without game-specific rules
6. Direct provider/package/converter tests exist
7. Compatibility behavior (if any) is explicitly fenced from the native path

---

## Relationship to Codex's Plan

This plan agrees with Codex on:
- PHRB should be the runtime format
- `.hts`/`.htc` are import inputs, not the product path
- Compatibility should be explicit and secondary
- Validation must broaden beyond Paper Mario menu scenes
- Direct tests should exist for provider/package behavior

This plan differs from Codex on:
- The path to PHRB is a **generic automatic converter**, not per-game tooling
- The palette CRC and LoadBlock fixes are **correctness improvements**, not
  "compatibility investigations" — they fix bugs in how ParaLLEl computes
  texture identity, matching what the N64 hardware actually does
- These fixes should be Step 1 (immediate, measurable), not Phase B1 (parallel
  research alongside architectural work)
- Structured sampled-object lookup is a future enhancement (ROM-scan enrichment),
  not a prerequisite for the runtime contract

The key constraint both plans must respect: **if it requires manual work per game,
it won't scale.** The converter must be fully automatic.

---

## Open Questions

1. **Does `tlut_shadow` actually contain different bytes than `TexFilterPalette`?**
   Step 1 will answer this definitively. If the bytes match, the palette CRC fix is
   trivial. If they don't, we need to understand exactly why.

2. **Are there games where LoadBlock reinterpretation produces false positives?**
   Step 2 should validate this. The reinterpretation should only fire on misses,
   so false positives would require a different texture with the same reinterpreted
   CRC, which is unlikely but possible.

3. **Is there a class of textures where neither Rice CRC nor reinterpretation works?**
   Copy-mode draws, framebuffer-derived textures, and procedurally generated content
   may fall into this category. These should be explicitly excluded from replacement
   rather than guessed at.

4. **Can auto-conversion at first load be fast enough?**
   A 2GB `.hts` pack needs to be parsed, CRC-corrected, and written as `.phrb` in
   a reasonable time. If this takes minutes, it should be a one-time operation with
   the result cached. If it takes seconds, it can happen transparently.
