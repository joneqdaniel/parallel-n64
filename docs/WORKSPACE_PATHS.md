# Workspace Paths

This document records the current machine-specific workspace layout.

For now, this project assumes work happens on this PC only.
If that changes later, this file should become the source of truth for local path assumptions and migration notes.

## Primary Repo

- `parallel-n64`: `/home/auro/code/parallel-n64`

## External Repos And Local References

- `RetroArch`: `/home/auro/code/RetroArch`
  Current role: frontend/tooling patch target for agent-first control, capture, logging, and orchestration.

- `RetroArch runtime binary`: `/home/auro/code/RetroArch/retroarch`
  Current role: canonical local RetroArch executable used by Phase 0 tracked scenario paths on this machine.

- `papermario-dx`: `/home/auro/code/paper_mario/papermario-dx`
  Current role: semantic game-state reference, fixture research target, and possible game-side telemetry/instrumentation target.

- `papermario`: `/home/auro/code/paper_mario/papermario`
  Current role: upstream Paper Mario decomp/reference checkout for vanilla code and symbol/layout comparison alongside `papermario-dx`.

- `emulator_references`: `/home/auro/code/emulator_references`
  Current role: local reference implementations from other emulator projects.

- `n64_docs`: `/home/auro/code/n64_docs`
  Current role: local N64 behavior and hardware documentation reference set.

- `parallel-n64-failed-attempt`: `/home/auro/code/parallel-n64-failed-attempt`
  Current role: historical worktree used to study the failed hi-res attempt.

- `oot`: `/home/auro/code/oot`
  Current role: zeldaret/oot decomp reference checkout (shallow). Staged for cross-game validation and source-level texture identity research.

- `sm64`: `/home/auro/code/sm64`
  Current role: n64decomp/sm64 decomp reference checkout (shallow). Staged for cross-game validation and source-level texture identity research.

## Local Assets And Generated Output

- local testing and research assets: `/home/auro/code/parallel-n64/assets`
  Notes: gitignored, machine-local, currently used for ROMs and hi-res texture assets.
  Current contents:
  - `PAPER MARIO_HIRESTEXTURES.hts` — authority Paper Mario pack (Rice CRC, old format `0x40a20000`)
  - `SUPER MARIO 64_HIRESTEXTURES.hts` — SM64 Reloaded v2.6.0 HD (Rice CRC, GlideN64 format `0x08000000`, 2530 entries)
  - `THE LEGEND OF ZELDA_HIRESTEXTURES.hts` — OoT Reloaded v11.0.0 HD (Rice CRC, GlideN64 format `0x08000000`, 43267 entries)
  - `Paper Mario (USA).zip`, `Super Mario 64 (USA).zip`, `Legend of Zelda, The - Ocarina of Time (USA).zip` — ROMs
  Note: GlideN64 HTS packs use Rice CRC computed from RDRAM. The GlideN64-compat draw-time CRC fallback (auto-enabled via source mode `all`) resolves this mismatch at runtime. SM64 confirmed working end-to-end (HTS → PHRB → runtime hits, 6599 compat hits in 30s boot). OoT confirmed working end-to-end (43K entries, 8.9GB PHRB, streaming metadata-only load, 46751 compat hits including CI palette CRC in 45s boot).

- generated workflow artifacts: `/home/auro/code/parallel-n64/artifacts`
  Notes: gitignored except for the tracked README.

## Path Assumptions

- These paths are currently treated as canonical for planning and tooling work on this machine.
- Scripts and manifests should prefer references to this document or clearly named variables over silently hardcoding new paths in multiple places.
- If a script must assume a local path, keep the assumption explicit and easy to override.

## Current Dependencies To Keep In Mind

- `parallel-n64` depends operationally on the local `RetroArch` checkout for frontend/tooling work.
- `parallel-n64` depends operationally on the local `papermario-dx` checkout for fixture analysis and potential game-side debug work.
- `parallel-n64` now also depends on the local `papermario` checkout for upstream vanilla-reference comparison when DX-specific relocation or symbol drift makes `papermario-dx` insufficient.
- research and planning currently depend on the local `emulator_references` and `n64_docs` trees.

## Maintenance Rule

When a new external repo, local corpus, or machine-specific dependency becomes part of the workflow, add it here before relying on it in plans or tooling.
