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
- [x] M3: Keying replication + logging harness (`checksum64`, `formatsize`, match logs).
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
- 2026-03-04: Stabilized forced `parallel` startup path by guarding `plugin_start_gfx()` against null function pointers and defaulting to a valid compiled GFX plugin when an unavailable/stale plugin selection is requested.
- 2026-03-04: Revalidated M1/M2 under forced `parallel` + `parallel` RSP:
  - hi-res `disabled`: 20s smoke passed (`lookups=0 hits=0 misses=0 provider=off`).
  - hi-res `enabled` with Paper Mario pack: 20s smoke passed with cache load and live matches (`15159` entries loaded; `lookups=31902 hits=18376 misses=13526 provider=on`).
- 2026-03-04: Added local hi-res texture unit tests and runner:
  - `tests/hires_textures/hires_keying_test.cpp` validates `formatsize`, wrapped reads, CRC behavior, and CI max-index helpers.
  - `tests/hires_textures/hires_replacement_provider_test.cpp` validates `.htc` + `.hts` cache load, lookup, wildcard formatsize fallback, and RGBA8 decode using generated fixtures.
  - Run commands:
    - `./run-tests.sh`
    - `cmake -S . -B build/ctest`
    - `cmake --build build/ctest --parallel`
    - `ctest --test-dir build/ctest --output-on-failure`
- 2026-03-04: Revalidated after keying helper refactor and tests:
  - `make HAVE_PARALLEL=1 HAVE_PARALLEL_RSP=1` passes.
  - `timeout --signal=INT --kill-after=5 20s ./run-n64.sh -- --verbose` with forced `parallel` + hi-res `enabled` passes (`lookups=31902 hits=18376 misses=13526 provider=on`).
- 2026-03-04: Marked M3 complete after runtime hit/miss validation and local unit coverage for keying and replacement provider decode paths.
- 2026-03-04: Promoted local M3 tests to first-class CMake/CTest targets for the fork (`cmake -S . -B build/ctest` + `ctest --test-dir build/ctest`).
- 2026-03-04: Added `run-build.sh` helper for consistent local core builds with this fork's defaults (`HAVE_PARALLEL=1`, `HAVE_PARALLEL_RSP=1`).
