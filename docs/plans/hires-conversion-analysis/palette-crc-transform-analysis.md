# Palette CRC Transform Analysis

## The Problem

Legacy hi-res packs key CI textures by `(texture_crc, palette_crc)` where both are
Rice CRC32 values computed from **RDRAM data**. ParaLLEl RDP computes palette CRC
from a **TLUT shadow** that reflects TMEM state after LOAD_TLUT processing.

The question: can we compute one from the other without running the game?

## GLideN64 Palette CRC Path

Source: `gliden64/src/Textures.cpp:1154-1225` and `gliden64/src/GLideNHQ/TxUtil.cpp:82-116`

```
1. _loadHiresTexture() reads palette from gDP.TexFilterPalette
2. For CI4: paladdr = gDP.TexFilterPalette + (palette_bank * 32)  [32 bytes = 16 entries * 2]
3. For CI8: paladdr = gDP.TexFilterPalette                        [512 bytes = 256 entries * 2]
4. Scans texture indices to find cimax (highest used index)
5. Computes: RiceCRC32(paladdr, cimax+1, 1, 2, palette_stride)
   - CI4: palette_stride = 32 (16 entries * 2 bytes)
   - CI8: palette_stride = 512 (256 entries * 2 bytes)
```

gDP.TexFilterPalette contains the **raw RDRAM 16-bit palette entries** in their
original order. These are the same bytes that were at the RDRAM address pointed to
by SET_TEXTURE_IMAGE before LOAD_TLUT was issued.

## ParaLLEl Palette CRC Path

Source: `parallel-rdp/rdp_hires_ci_palette_policy.hpp`

### Entry-count variant (current default):
```
compute_hires_ci_palette_crc_for_entries():
  CI4: rice_crc32_wrapped(tlut_shadow, 512, bank*32, entries, 1, 2, 32)
  CI8: rice_crc32_wrapped(tlut_shadow, 512, 0, entries, 1, 2, 512)
```

### Sparse/used-indices variant:
```
compute_hires_ci_palette_crc_for_used_indices():
  Packs only referenced palette entries into a contiguous buffer
  Runs rice_crc32 on the packed buffer
```

### TMEM variant:
```
compute_hires_ci_palette_crc_for_entries_tmem():
  CI4: rice_crc32_wrapped(tlut_tmem_shadow, 2048, bank*128, entries, 1, 2, 128)
  CI8: rice_crc32_wrapped(tlut_tmem_shadow, 2048, 0, entries, 1, 2, 2048)
```

## The Transform Question

### tlut_shadow (RDRAM-side)

ParaLLEl maintains `tlut_shadow[512]` — a 512-byte buffer that stores the **raw
RDRAM palette entries** copied during LOAD_TLUT processing. Each entry is 2 bytes
(16-bit), stored in the same order as RDRAM.

This is essentially the same data as `gDP.TexFilterPalette` in GLideN64.

**If ParaLLEl's tlut_shadow is byte-identical to GLideN64's TexFilterPalette,
then the entry-count palette CRC should match directly** — both run Rice CRC32
over the same bytes with the same parameters.

### tlut_tmem_shadow (TMEM-side)

ParaLLEl also maintains `tlut_tmem_shadow[2048]` — a 2048-byte buffer that stores
palette data as it appears in TMEM after LOAD_TLUT expansion. Each logical 16-bit
entry is expanded to 8 bytes (quadrupled) in TMEM.

This is NOT what GLideN64 uses for hi-res lookup. The TMEM CRC will NOT match.

## Key Question: Is tlut_shadow == TexFilterPalette?

### How tlut_shadow is populated (rdp_renderer.cpp:3888-3933):

```cpp
for (uint32_t i = 0; i < count; i++) {
    const uint16_t word = emulate_load_tlut_entry_word(cpu_rdram, ...);
    // Write to RDRAM-side shadow
    tlut_shadow[palette_entry_base * 2 + i * 2 + 0] = uint8_t(word & 0xff);
    tlut_shadow[palette_entry_base * 2 + i * 2 + 1] = uint8_t(word >> 8);
}
```

### How TexFilterPalette is populated (GLideN64 gDP.cpp:965-1006, gDPLoadTLUT):

```cpp
// Reads palette entries from RDRAM at textureImage.address
// Copies them into gDP.TexFilterPalette at the tile's TMEM offset
// Each entry is a raw 16-bit value
```

Both read the same RDRAM address, both store raw 16-bit entries. The byte order
should match if both use the same endianness convention.

## Conclusion

**For the entry-count CRC variant**, the transform should be an identity:

```
GLideN64:  RiceCRC32(TexFilterPalette + bank*32, cimax+1, 1, 2, 32)  [CI4]
ParaLLEl:  rice_crc32_wrapped(tlut_shadow, 512, bank*32, entries, 1, 2, 32)  [CI4]
```

If `entries == cimax+1` and `tlut_shadow[bank*32..] == TexFilterPalette[bank*32..]`,
these produce the same CRC.

**The mismatch we're seeing** likely comes from:
1. ParaLLEl using a different entry count than GLideN64's cimax+1
2. ParaLLEl using the TMEM shadow instead of the RDRAM shadow
3. Byte-order differences in the shadow population
4. ParaLLEl using the sparse variant instead of the entry-count variant

**For offline conversion**, this means:
- We can compute the legacy palette CRC from the RDRAM data (same algorithm as GLideN64)
- We can compute the ParaLLEl entry-count CRC from the same data (should match)
- We can compute the ParaLLEl sparse CRC by scanning the texture indices in the pack
- The bridge is mathematical, not observational
