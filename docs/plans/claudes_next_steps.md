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
general N64 problems, not Paper Mario problems, and should be solved at runtime.

---

## Strategy: Fix the Runtime, Not the Pack

GlideN64 already makes these packs work. The packs were authored against Rice/Glide64
CRC computation. ParaLLEl should compute the same CRCs from the same data, then
handle the remaining edge cases with a general runtime fallback.

**Do NOT** build more per-game conversion tooling.
**DO** fix the runtime lookup to handle the general cases automatically.

---

## Step 1: Match GlideN64's Palette CRC Exactly

**Problem:** ParaLLEl's CI palette CRC doesn't match what pack creators used.

**Root cause analysis:** GlideN64 computes palette CRC like this:

```
// On LoadTLUT:
gDP.TexFilterPalette = raw RDRAM copy (2 bytes per entry, contiguous)
gDP.paletteCRC16[pal] = CRC_CalculatePalette(0xFFFFFFFF, &TMEM[256 + pal*16], 16)
gDP.paletteCRC256 = CRC_Calculate(0xFFFFFFFF, paletteCRC16, sizeof(u64)*16)

// On hi-res lookup (CI4):
palette_data = gDP.TexFilterPalette + (tile->palette << 4)   // 16 entries
rice_crc = RiceCRC32(palette_data, cimax+1, 1, 2, 32)

// On hi-res lookup (CI8):
palette_data = gDP.TexFilterPalette                           // 256 entries
rice_crc = RiceCRC32(palette_data, cimax+1, 1, 2, 512)

// Combined key:
checksum64 = (palette_rice_crc << 32) | texture_rice_crc
```

Note: `CRC_CalculatePalette` is used for internal caching, NOT for hi-res lookup.
The hi-res lookup uses `RiceCRC32` on `TexFilterPalette` (RDRAM bytes), NOT on TMEM.

**What ParaLLEl does:** Uses `rice_crc32_wrapped` on `tlut_shadow` (also RDRAM bytes).
The algorithm is the same. The question is whether `tlut_shadow` contains the same
bytes as `TexFilterPalette` at lookup time.

**Key differences to investigate:**
1. `TexFilterPalette` is populated from raw RDRAM on LoadTLUT
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

**Success criteria:** Paper Mario file-select CI textures match with legacy `.hts`
pack, no per-game tooling or PHRB packages required.

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

**Proposed runtime fix:** When the primary RDRAM CRC lookup misses on a `LoadBlock`
upload, compute the sampled dimensions from the tile descriptor and retry:

```
if (miss && upload_was_loadblock) {
    // Get sampled dimensions from SetTile/SetTileSize state
    sampled_w = (tile.sh - tile.sl + 4) >> 2;
    sampled_h = (tile.th - tile.tl + 4) >> 2;
    sampled_fmt = tile.fmt;
    sampled_siz = tile.siz;

    // Recompute Rice CRC with sampled dimensions and the same RDRAM data
    texture_crc = rice_crc32_wrapped(rdram, rdram_size, src_addr,
                                     sampled_w, sampled_h, sampled_siz,
                                     sampled_stride);

    // Retry lookup with sampled-shape key
    retry_result = provider->lookup(checksum64, formatsize_from_sampled);
}
```

**Important:** This is a general N64 property, not game-specific. Any game that uses
`LoadBlock` for CI4/CI8 textures will have this mismatch.

**Action items:**
- [ ] Track which uploads are `LoadBlock` vs `LoadTile` (already partially done)
- [ ] On miss, compute sampled dimensions from tile descriptor state
- [ ] Recompute Rice CRC with sampled dimensions and correct stride
- [ ] Retry pack lookup with the reinterpreted key
- [ ] Validate: the dominant 64x1 fs514 miss family should resolve
- [ ] Verify no false positives on title screen (which is already 91% hits)

**Success criteria:** Paper Mario file-select block-class misses resolve with legacy
`.hts` pack, no PHRB package required.

---

## Step 3: Make the Fixed Lookup the Default Path

**Problem:** The sampled-object lookup and various compatibility tiers are behind
env vars (`PARALLEL_RDP_HIRES_SAMPLED_OBJECT_LOOKUP`, `PARALLEL_RDP_HIRES_CI_COMPAT`,
etc.). Users can't benefit from fixes without knowing magic incantations.

**Action items:**
- [ ] After Steps 1-2 are validated, make the improved lookup the default
- [ ] The primary path should be: exact Rice CRC (with corrected palette) first,
      then LoadBlock reinterpretation as automatic fallback
- [ ] Remove or demote the debug-only env var gates
- [ ] Legacy `.hts` packs should "just work" when `hirestex=enabled`

**Success criteria:** A user drops a Paper Mario `.hts` pack in the system directory,
enables hi-res textures, and gets correct replacement on title + file-select without
any special configuration.

---

## Step 4: Validate on a Second Game

**Problem:** All current validation is Paper Mario only. Need proof of generality.

**Action items:**
- [ ] Pick a second game with a well-known Rice-format hi-res pack
      (Zelda OoT or Mario 64 are good candidates — large community packs exist)
- [ ] Build a minimal fixture (savestate + scenario) for one representative scene
- [ ] Run with legacy `.hts` pack and the fixed lookup from Steps 1-2
- [ ] Compare hit rate against GlideN64 on the same scene
- [ ] Document any new miss classes that don't appear in Paper Mario

**Success criteria:** Second game achieves comparable hit rate to GlideN64 with
zero game-specific tooling.

---

## Step 5: Decide What to Do with the PHRB/Sampled-Object Path

After Steps 1-4, reassess. The PHRB path and sampled-object model may still be
valuable for:

- **Performance**: Pre-resolved lookups avoid runtime CRC computation
- **Correctness**: Cases where the Rice CRC path is fundamentally ambiguous
  (same upload data used with different SetTile configs in the same frame)
- **New packs**: Future pack creators could author directly against sampled-object
  identity for perfect LLE alignment

But it should be **optional optimization**, not the required path. The system must
work with legacy `.hts` packs out of the box.

**Decision criteria for promoting PHRB:**
- Are there real games where Steps 1-2 don't achieve acceptable hit rates?
- Is the remaining miss class large enough to justify per-game PHRB conversion?
- Can the conversion be automated enough to not require manual policy authoring?

---

## What to Keep from Current Work

- **Fixture/scenario framework** — essential for regression testing
- **PHRB binary format** — well-designed, keep as optional fast path
- **Evidence bundle infrastructure** — useful for debugging new games
- **Rice CRC implementation** — already correct for textures
- **Renderer integration** — clean descriptor-indexed replacement path
- **Sampled-object identity model** — correct architectural insight, useful for
  edge cases and future native packs

## What to Deprioritize

- **39-tool Python conversion pipeline** — don't invest more here until runtime is fixed
- **Per-family transport policy** — manual curation doesn't scale
- **Surface package ordered-slot model** — over-engineered for the current problem
- **Paper Mario decomp-backed static scans** — useful research but not the fix path
- **Per-low32 import policies** — runtime should handle this automatically

---

## Estimated Effort

| Step | Effort | Risk |
|------|--------|------|
| 1. Fix palette CRC | 2-4 days | Low — GlideN64 source is clear reference |
| 2. LoadBlock reinterpretation | 2-3 days | Medium — need to handle stride/dxt correctly |
| 3. Default path promotion | 1 day | Low — mostly removing env var gates |
| 4. Second game validation | 2-3 days | Low — just needs a pack and a savestate |
| 5. PHRB reassessment | 1 day | N/A — decision point, not implementation |

**Total: ~8-12 days to a working "any game" legacy pack path.**

Compare with the current trajectory: 15-25 days per game with manual tooling.

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
