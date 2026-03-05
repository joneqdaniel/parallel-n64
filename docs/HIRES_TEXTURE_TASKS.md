# Hi-Res Texture Task Tracker

## Decisions
- Target: latest hardware only.
- GPU requirement: descriptor indexing path only.
- Fallback behavior: auto-disable feature when required GPU features are missing.
- Local texture cache artifacts (`*.htc`, `*.hts`) are ignored in git.

## Milestones
- [x] M0: Repo hygiene for local packs (`.gitignore` update).
- [ ] M1: Core options and runtime plumbing (`hires_*` toggles + path).
- [ ] M2: Replacement provider module (`.htc` + `.hts` parse + decode).
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
