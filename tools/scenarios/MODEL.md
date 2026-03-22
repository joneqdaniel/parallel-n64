# Scenario Model

This directory uses one runtime model for tracked emulator fixtures.

## Core Rule

- steady-state fixture runs should use `load savestate -> settle 3 frames -> capture`
- controller scripting is a bootstrap tool for minting or replacing authoritative savestates

## Authority Modes

- `authoritative`
  Use the canonical savestate for the target fixture.
- `bootstrap`
  Use an earlier authoritative state plus deterministic controller input to reach or rebuild a later state.
- `auto`
  Prefer the canonical savestate when present, otherwise fall back to the bootstrap path.

## Fixture Status

- `active`
  The fixture has a runnable steady-state path and should produce evidence bundles.
- `planned`
  The fixture is intentionally part of the ladder, but its bootstrap route or authoritative state is not ready yet.
  Planned fixtures should still exist in the authority graph so lineage decisions are explicit before implementation starts.

## Bundle Contract

Every tracked scenario bundle should record:

- requested authority mode
- used authority mode
- authority graph path and authority node id
- authoritative state path and hash when present
- bootstrap state path and hash when present
- active state path and hash
- ROM hash
- pack hash when present
- the post-load settle frame count
- semantic scene traces when stable addresses are known and the frontend can read memory safely

## Frame Contract

- tracked scenarios rely on the fixture-relative RetroArch `GET_STATUS frame=` clock
- the canonical capture point for savestate-backed Paper Mario fixtures is `frame=3` after load
- when bootstrap logic is used, the bundle should still preserve the steady-state state/hash information needed to remint or verify the later authority
- tracked fixtures should point at a machine-readable authority graph so lineage is not hidden in free-form notes
- planned ladder steps should still have explicit graph nodes, fixture manifests, and remint-script placeholders

## Reminting

- reminting should happen through dedicated helper scripts, not ad hoc command sequences
- remint helpers should verify the rebuilt state against a known canonical capture hash before replacing the tracked authority

## Build Rule

- use [run-build.sh](/home/auro/code/parallel-n64/run-build.sh) for the core build path
- use the local [RetroArch build](/home/auro/code/RetroArch/retroarch) for tracked runtime scenarios
- emulator-facing scenario runs are serial; the adapter should enforce this with both a process check and a runtime lock
