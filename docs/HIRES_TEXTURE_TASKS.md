# Hi-Res Texture Task Tracker

## Decisions
- Target: latest hardware only.
- GPU requirement: descriptor indexing path only.
- Fallback behavior: auto-disable feature when required GPU features are missing.
- Local texture cache artifacts (`*.htc`, `*.hts`) are ignored in git.

## Milestones
- [x] M0: Repo hygiene for local packs (`.gitignore` update).
- [x] M1: Core options and runtime plumbing (`hires_*` toggles + path).
- [x] M2: Replacement provider module (`.htc` + `.hts` parse + decode).
- [ ] M3: Keying replication + logging harness (`checksum64`, `formatsize`, match logs).
- [ ] M4: GPU registry (bindless descriptor pool + lazy upload).
- [ ] M5: Shader texel-stage late swap (before combiner).
- [ ] M6: CI/TLUT correctness for palette-influenced keys.
- [ ] M7: Mips/LOD/filtering + memory budget controls.
- [ ] M8: Validation + performance pass + docs.

## Status Update Format
I will post updates in this format as work progresses:
- `Phase`: current milestone ID.
- `Done`: what was completed since the last update.
- `Changed`: exact files touched.
- `Validated`: build/tests/manual checks run.
- `Next`: immediate next implementation step.

## Change Log
- 2026-03-04: Created tracker and aligned scope to latest-hardware-only descriptor-indexing path.
- 2026-03-04: Added ignore rules for local hires cache artifacts in `.gitignore`.
- 2026-03-04: Added M1 plumbing for hi-res options (`enabled`, `filter`, `srgb`, cache path) from libretro options to paraLLEl runtime globals.
- 2026-03-04: Began M2 by reverse-checking `.hts` layout from the Paper Mario pack (header + `storagePos`, indexed `key -> offset|formatsize`, per-entry payload with dimensions/metadata + zlib blob).
- 2026-03-04: Completed M2 standalone loader in paraLLEl-RDP (`texture_replacement.*`) with `.hts` index parsing, `.htc` gzip-record parsing, `(checksum64, formatsize)` lookup (with wildcard fallback), zlib blob handling, and decode to canonical RGBA8.
- 2026-03-04: Added non-Windows `-lz` link flag for paraLLEl builds to satisfy loader zlib usage.
- 2026-03-04: Validated M2 on local `PAPER MARIO_HIRESTEXTURES.hts` (loaded 15159 entries; lookup + RGBA8 decode succeeded on sampled key).
- 2026-03-04: Started M3 integration: wired cache provider into `CommandProcessor`, added renderer-side TLUT shadowing, `formatsize` keying, per-tile replacement key state, and debug logging/counters for key hit/miss tracing.
- 2026-03-04: M3 build validation passed (`make HAVE_PARALLEL=1 HAVE_PARALLEL_RSP=1`) and default local smoke test passed.
- 2026-03-04: Forcing `parallel-n64-gfxplugin = "parallel"` currently triggers an early runtime core dump in local smoke runs before keying logs can be validated; key matching validation remains pending until this runtime path is stable.
