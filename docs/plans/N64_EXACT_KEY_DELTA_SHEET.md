# N64 Exact Key Delta Sheet

## Purpose

- Make the current ParaLLEl exact hi-res key explicit
- Compare it against the latest N64 identity research
- Name the highest-probability gaps behind the current Paper Mario CI/menu misses

## Current ParaLLEl Exact Key

Current exact lookup is effectively:

- `checksum64 = compose_hires_checksum64(texture_crc, palette_crc)`
- `formatsize = formatsize_key(meta.fmt, meta.size)`

Current source:

- [rdp_renderer.cpp](/home/auro/code/parallel-n64/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_renderer.cpp)
- [rdp_hires_ci_palette_policy.hpp](/home/auro/code/parallel-n64/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_hires_ci_palette_policy.hpp)

What that means today:

- `texture_crc` is computed from the raw RDRAM upload bytes selected by:
  - source base address
  - `key_width_pixels`
  - `key_height_pixels`
  - source VRAM bpp
  - source row stride
- `palette_crc` is only populated for CI textures when TLUT shadow state is valid
- `formatsize` comes from the sampled tile format/size

## What The Current Exact Key Includes

Directly included:

- raw uploaded texel bytes for the selected source rectangle
- CI palette influence through the current shadow-based palette CRC
- sampled tile `fmt`
- sampled tile `siz`
- CI4 palette bank input through `meta.palette` inside the current palette-CRC path

Implicitly but not explicitly named:

- width/height only affect lookup through the raw texel CRC input
- source row stride only affects lookup through the raw texel CRC input

## What The Current Exact Key Does Not Include Explicitly

- `LoadTile` vs `LoadBlock` provenance
- copy-cycle vs normal textured draw provenance
- framebuffer-derived vs authored-RDRAM source classification
- `tlut_type`
- TMEM base address as a first-class identity field
- TMEM line/stride as a first-class identity field
- tile window origin as a first-class identity field
- clamp / mirror / mask / shift as first-class identity fields
- `SetTileSize` sampled window semantics as first-class identity fields
- texrect / BG-copy style path classification

## What The Research Says Should Matter

The latest `n64_docs` pass points at the post-load sampled tile as the authoritative object, not the raw upload blob alone.

High-confidence identity fields:

- sampled `fmt` / `siz`
- CI vs direct
- TLUT enabled
- `tlut_type`
- CI4 palette bank semantics
- TMEM address
- TMEM line/stride
- tile window / origin
- clamp / mirror / mask / shift
- upload provenance: `LoadTile` vs `LoadBlock`

High-confidence provenance classes:

- authored RDRAM texture load
- copy / texrect / BG-copy style path
- framebuffer-derived or readback-derived source

## Highest-Probability Gaps Right Now

### 1. We May Still Be Keying The Wrong Object

Current exact lookup is still dominated by raw upload bytes plus the current palette CRC.

Research direction:

- the N64 texture object is closer to the sampled tile after load semantics
- `SetTile`, `SetTileSize`, TMEM address/line, and sampler state can change meaning without changing the raw upload blob

Why this matters for current misses:

- it explains why repeated CI/menu misses can survive many CRC experiments

### 2. `tlut_type` Is Missing From Exact Identity

Current palette CRC computation does not take `tlut_type`.

Research direction:

- the same TLUT words can decode differently under RGBA16 vs IA16 TLUT interpretation

Why this matters:

- exact CI identity can be wrong even when the raw palette bytes are “correct”

### 3. TMEM / Sampler State Are Only Side Conditions Today

Current exact lookup does not carry TMEM address, TMEM line, or sampler-state fields explicitly.

Research direction:

- those fields affect the sampled result and should not be treated as mere logging/debug context

Why this matters:

- current Paper Mario menu misses may be “same upload, different sampled object”

### 4. Provenance Is Not Part Of The Acceptance Story Yet

Current lookup does not distinguish authored texture classes from copy-cycle or framebuffer-derived content.

Research direction:

- copy / texrect / BG-copy and framebuffer-derived content should be explicit provenance classes

Why this matters:

- some “missing textures” may not be authored replacement candidates at all

## Current Conclusion

The likely next breakthrough is not a broader compatibility rule.

It is:

1. make provenance visible in strict bundles
2. make CI/TLUT identity more logical
3. move exact lookup closer to the sampled N64 object
4. keep compatibility/import policy explicit for the remaining ambiguous families

## Immediate Follow-On Work

- use the new provenance logging on strict title/file fixtures
- add a logical TLUT diagnostic view that includes `tlut_type`
- compare the current exact key against one sampler-aware candidate model before changing default runtime behavior
