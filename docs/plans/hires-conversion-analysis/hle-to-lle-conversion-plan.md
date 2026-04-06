# Plan: HLE-to-LLE Hi-Res Texture Pack Conversion (Revised)

## Context

ParaLLEl RDP is an LLE N64 video plugin. Legacy hi-res texture packs were authored
for HLE plugins (Rice/GLideN64). The project needs a native pack format keyed by
canonical sampled-object identity, plus conversion tooling from legacy packs.

## Key Discovery: GLideN64's Hi-Res CRC Uses RDRAM, Not TMEM

GLideN64 has two CRC paths (see `gliden64/src/Textures.cpp`):
- **Internal cache** (`_calculateCRC` line 1837): CRC from **TMEM** — `src = (u64*)&TMEM[tMem]`
- **Hi-res lookup** (`_loadHiresTexture` line 1154): CRC from **RDRAM** — `addr = (u8*)(RDRAM + info.texAddress)`

Legacy packs are keyed by the **RDRAM-side Rice CRC**. ParaLLEl also computes its
hi-res CRC from RDRAM at load time. The texture CRCs should match directly.

## The Actual Gap Is Narrow

| Component | GLideN64 source | ParaLLEl source | Match? |
|-----------|----------------|-----------------|--------|
| Texture CRC (LOAD_TILE) | RDRAM bytes | RDRAM bytes | **Yes** |
| Texture CRC (LOAD_BLOCK) | RDRAM bytes (ReverseDXT) | RDRAM bytes | **Yes** |
| Palette CRC (CI) | TexFilterPalette (RDRAM copy) | tlut_shadow (RDRAM copy) | **Should match** |
| Width/Height | From gDP tile state | From LoadTileInfo/TileMeta | **Need mapping** |
| tmem_offset / stride | Not in legacy key | From SET_TILE | **New field** |

The only genuinely new fields in the native key are tmem_offset, stride, and sampled
dimensions — and these come from SET_TILE/SET_TILE_SIZE commands in the ROM's display lists.

---

## Three-Tier Conversion (Minimize Runtime Requirement)

### Tier 1: Pure Math — No ROM Needed (~80%+ of pack entries)

**For non-CI textures:**
- `native_texture_crc == legacy_texture_crc` (same RDRAM data, same algorithm)
- `native_palette_crc = 0` (no palette)
- `formatsize` preserved from legacy key
- Remaining fields (tmem_offset, stride, sampled_width, sampled_height): derive from
  format/size/total_bytes. For LOAD_TILE, dimensions match directly. For LOAD_BLOCK,
  enumerate plausible (width, height) factorizations of `total_texels`.

**For CI textures:**
- `native_texture_crc == legacy_texture_crc` (texture index bytes match)
- Palette CRC: if native key uses the same entry-count approach as GLideN64 (CRC over
  entries 0..cimax from RDRAM palette data), it matches the legacy CRC directly.
  No transform needed — the inputs are identical.

**What this doesn't resolve:**
- Exact tmem_offset and tmem_stride (requires SET_TILE from display list)
- Exact sampled dimensions for LOAD_BLOCK (multiple factorizations possible)
- One-to-many mappings (same RDRAM data loaded with different SET_TILE configs)

### Tier 2: ROM Display List Scan — Resolves Ambiguity

**What it does:**
1. Load the ROM binary
2. Find F3DEX2 display list entry points
3. For each display list, trace the command sequence:
   - `gDPSetTextureImage` → record RDRAM address, width, format, size
   - `gDPSetTile` → record tmem_offset, stride, format, size, palette
   - `gDPLoadTile/LoadBlock/LoadTLUT` → record load type, coordinates
   - `gDPSetTileSize` → record sampled bounds
   - `gSP*Triangle / gSPTextureRectangle` → record that this tile was drawn
4. For each texture setup sequence, compute Rice CRC from ROM data at the RDRAM address
5. Match against legacy pack entries by CRC
6. Record SET_TILE parameters → complete the native key

**Implementation**: Based on Rice's RSP parser already in the repo (`gles2rice/src/RSP_Parser.cpp`
with F3DEX2 handlers in `RSP_GBI2.h`). Paper Mario uses F3DEX2 microcode.

**Paper Mario advantage**: Decompilation at `~/code/paper_mario/` gives source-level
display list definitions we could cross-reference.

**What this resolves:**
- Exact tmem_offset and tmem_stride for every statically-defined texture
- Exact sampled dimensions for LOAD_BLOCK reinterpretations
- One-to-many mappings (same texture data with different tile configs)

### Tier 3: Runtime Observation — Edge Cases Only

For textures not found in static ROM data:
- Runtime-generated display lists (particle effects, procedural geometry)
- Framebuffer-derived textures
- Custom microcode sequences

Run the game with bridge recording, capture `(legacy_key, native_key)` pairs.
This should be a small fraction of any pack.

---

## Step 1: Define the Native Sampled-Object Key

**File to create**: `parallel-rdp/rdp_hires_native_key.hpp`

```cpp
struct SampledObjectKey {
    uint32_t sampled_texture_crc;   // Rice CRC32 (matches legacy for LOAD_TILE)
    uint32_t sampled_palette_crc;   // Entry-count variant (matches legacy directly)
    uint16_t formatsize;            // (siz << 8) | fmt
    uint16_t tmem_offset;           // From SET_TILE
    uint16_t tmem_stride;           // From SET_TILE (line field)
    uint16_t sampled_width;         // From SET_TILE_SIZE or texture dims
    uint16_t sampled_height;        // From SET_TILE_SIZE or texture dims
};
```

**Design decision: use entry-count palette CRC, not sparse.**
This matches GLideN64's approach (CRC over entries 0..cimax) and means the palette
CRC is identical for the vast majority of CI textures. No transform needed.

---

## Step 2: Offline Conversion Tool (Tier 1 + Tier 2)

**File to create**: `tools/hires_convert_pack.py`

```
python3 tools/hires_convert_pack.py \
  --cache "PAPER MARIO_HIRESTEXTURES.hts" \
  [--rom "Paper Mario (USA).z64"]  \
  --output-dir native-pack/
```

ROM is optional — without it, Tier 1 math handles most entries; with it, Tier 2
fills in exact SET_TILE parameters and resolves ambiguous LOAD_BLOCK dimensions.

**Pipeline internally:**

### Phase A: Load legacy pack index
- Parse `.hts` entries via `hires_pack_common.parse_cache_entries()`
- For each entry: extract checksum64, formatsize, replacement dimensions

### Phase B: Pure math bridge (Tier 1)
For each legacy entry:
1. `texture_crc = checksum64 & 0xFFFFFFFF`
2. `palette_crc = (checksum64 >> 32) & 0xFFFFFFFF`
3. `native_texture_crc = texture_crc` (identity — same RDRAM data)
4. `native_palette_crc = palette_crc` (identity — same entry-count approach)
5. `formatsize` preserved
6. `tmem_offset, tmem_stride, sampled_w, sampled_h` = derive from format/size or mark UNKNOWN

### Phase C: ROM display list scan (Tier 2, if ROM provided)
1. Parse ROM for F3DEX2 display lists
2. For each texture setup sequence:
   - Compute Rice CRC from ROM data at the SetTextureImage address
   - Match against legacy entries by texture_crc
   - Record SET_TILE fields (tmem_offset, line/stride)
   - Record SET_TILE_SIZE dimensions
3. Fill in UNKNOWN fields from Phase B

### Phase D: Classify and emit
- **Complete**: All native key fields resolved → emit to native manifest
- **Partial**: CRC matches but no SET_TILE info → emit with defaults (tmem_offset=0,
  stride derived from dims). These will work for textures that always load to the
  same TMEM location, which is the common case.
- **Unresolved**: Rare — flag for Tier 3 observation

### Phase E: Build native pack
- Emit `native-manifest.json` keyed by SampledObjectKey
- Decode and emit RGBA8 assets from legacy cache
- Optionally emit PHRB v2 binary

---

## Step 3: ROM Display List Scanner

**File to create**: `tools/hires_rom_texture_scan.py`

Lightweight F3DEX2 command tracer. Does NOT run the game.

**Input**: N64 ROM (.z64/.n64/.v64)
**Output**: JSON list of texture setup records with Rice CRCs + SET_TILE state

**Implementation approach:**
- Scan ROM for F3DEX2 command signatures
- State machine tracking: SetTextureImage → SetTile → Load* → SetTileSize → Draw
- Compute Rice CRC for each identified texture region
- Cross-reference against legacy pack entries

**Key dimension relationships from GLideN64 source** (for matching):
- LOAD_TILE width: `min(info.width, info.texWidth)` with mask/clamp (Textures.cpp:897)
- LOAD_BLOCK width: `g_TI.dwWidth << info.dwSize >> tile.size` (Rice RDP_Texture.h:180)
- LOAD_BLOCK height: `info.th - info.tl + 1` (Rice RDP_Texture.h:186)
- BPL for LOAD_BLOCK: `ReverseDXT(dxt)` or `tile.line << 3` (GLideN64 Textures.cpp:1199-1206)

---

## Step 4: Runtime Bridge Recording (Tier 3 Fallback)

Extend the sampled-object probe in `rdp_renderer.cpp:1765-1881`:
- Lift CI-only and TexRect-only restrictions
- Emit bridge JSON for ALL texture types
- Activate via `PARALLEL_RDP_HIRES_BRIDGE_RECORD=1`
- This is now the last resort, not the primary conversion path

---

## Step 5: Native Runtime Loader + Dual-Provider Fallback

**NativeReplacementProvider** with draw-time lookup:
1. Compute SampledObjectKey from active tile state at draw time
2. Look up in native pack (binary search on key hash)
3. If hit → bind Vulkan descriptor
4. If miss → legacy provider already bound at upload time (fallback)

This enables incremental adoption — native pack handles converted entries,
legacy pack handles the rest, both can coexist.

---

## Step 6: PHRB v2 Binary Format

Extend existing PHRB emitter with v2 record table keyed by SampledObjectKey.
Records sorted by key hash for binary search at load time.

---

## Execution Order

| Phase | What | ROM? | Runtime? |
|-------|------|------|----------|
| **A** | Define SampledObjectKey | No | No |
| **B** | Pure-math bridge tool (Tier 1) | No | No |
| **C** | ROM display list scanner (Tier 2) | Yes | No |
| **D** | Combined offline converter | Optional | No |
| **E** | PHRB v2 format + native pack emitter | No | No |
| **F** | Native runtime loader | No | No |
| **G** | Draw-time lookup in renderer | No | No |
| **H** | Runtime bridge recording (Tier 3) | No | Yes |

**Phases A-B** validate immediately against known Paper Mario fixtures.
**Phase C** enriches with exact SET_TILE parameters from ROM.
**Phases D-G** are the production pipeline.
**Phase H** is the fallback for edge cases.

---

## Verification

1. **Tier 1 math**: Verify `legacy_texture_crc == sampled_texture_crc` for known
   Paper Mario hits (compare existing probe upload_low32 vs sampled_low32 data)

2. **Palette CRC**: Verify entry-count palette CRC from tlut_shadow matches legacy
   palette_crc for known CI hits

3. **ROM scan**: Cross-reference scanned textures against known hit/miss keys from
   strict fixture bundles

4. **Round-trip**: Convert Paper Mario pack offline → load native → verify strict
   fixture `on`-mode hashes match (`ba91ffce...` title, `8a90f787...` file-select)

---

## Key Files

| File | Role |
|------|------|
| `gliden64/src/Textures.cpp:1154-1255` | GLideN64 hi-res CRC path (RDRAM source — key discovery) |
| `gliden64/src/Textures.cpp:1837-1874` | GLideN64 internal CRC (TMEM source — different!) |
| `gliden64/src/GLideNHQ/TxUtil.cpp:82-116` | Rice CRC checksum64 with palette |
| `gliden64/src/gDP.cpp:681-963` | GLideN64 LoadTile/LoadBlock/LoadTLUT handlers |
| `parallel-rdp/rdp_hires_ci_palette_policy.hpp` | ParaLLEl palette CRC variants |
| `parallel-rdp/rdp_renderer.cpp:1765-1881` | Sampled-object probe (draw-time) |
| `parallel-rdp/rdp_renderer.cpp:3594-3950` | Load-time processing + TLUT shadow |
| `gles2rice/src/RSP_Parser.cpp` | Rice F3DEX2 display list parser (reusable) |
| `gles2rice/src/RSP_GBI2.h` | F3DEX2 command handlers |
| `tools/hires_pack_common.py` | Legacy pack parsing infrastructure |

## Analysis Files

| File | Content |
|------|---------|
| `/tmp/hires-conversion-analysis/palette-crc-transform-analysis.md` | Palette CRC GLideN64 vs ParaLLEl comparison |
| `/home/auro/.claude/plans/eager-sprouting-summit.md` | Original plan (observation-first approach) |
