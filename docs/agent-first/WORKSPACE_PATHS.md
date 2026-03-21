# Workspace Paths

This document records the current machine-specific workspace layout.

For now, this project assumes work happens on this PC only.
If that changes later, this file should become the source of truth for local path assumptions and migration notes.

## Primary Repo

- `parallel-n64`: `/home/auro/code/parallel-n64`

## External Repos And Local References

- `RetroArch`: `/home/auro/code/RetroArch`
  Current role: frontend/tooling patch target for agent-first control, capture, logging, and orchestration.

- `papermario-dx`: `/home/auro/code/paper_mario/papermario-dx`
  Current role: semantic game-state reference, fixture research target, and possible game-side telemetry/instrumentation target.

- `emulator_references`: `/home/auro/code/emulator_references`
  Current role: local reference implementations from other emulator projects.

- `n64_docs`: `/home/auro/code/n64_docs`
  Current role: local N64 behavior and hardware documentation reference set.

- `parallel-n64-failed-attempt`: `/home/auro/code/parallel-n64-failed-attempt`
  Current role: historical worktree used to study the failed hi-res attempt.

## Local Assets And Generated Output

- local testing and research assets: `/home/auro/code/parallel-n64/assets`
  Notes: gitignored, machine-local, currently used for ROMs and hi-res texture assets.

- generated workflow artifacts: `/home/auro/code/parallel-n64/artifacts`
  Notes: gitignored except for the tracked README.

## Path Assumptions

- These paths are currently treated as canonical for planning and tooling work on this machine.
- Scripts and manifests should prefer references to this document or clearly named variables over silently hardcoding new paths in multiple places.
- If a script must assume a local path, keep the assumption explicit and easy to override.

## Current Dependencies To Keep In Mind

- `parallel-n64` depends operationally on the local `RetroArch` checkout for frontend/tooling work.
- `parallel-n64` depends operationally on the local `papermario-dx` checkout for fixture analysis and potential game-side debug work.
- research and planning currently depend on the local `emulator_references` and `n64_docs` trees.

## Maintenance Rule

When a new external repo, local corpus, or machine-specific dependency becomes part of the workflow, add it here before relying on it in plans or tooling.
