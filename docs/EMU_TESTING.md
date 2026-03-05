# Emulator Test Tiers

This repo uses tiered, local-only emulator-behavior test gates to separate required checks from heavier optional checks.

## Local Commands

- Required gate (PR-safe):
  - `./run-tests.sh --profile emu-required`
- Optional conformance gate:
  - `./run-tests.sh --profile emu-conformance`
- Optional runtime lavapipe conformance gate:
  - `./run-tests.sh --profile emu-runtime-conformance`
- Optional dump-replay gate (provisions validator if missing):
  - `./run-dump-tests.sh --provision-validator`
- Optional strict dump-composition gate:
  - `./run-dump-tests.sh --strict-composition`
- Optional combined non-required gate:
  - `./run-tests.sh --profile emu-optional`
- Optional TSAN race check tier (local debug):
  - `./run-tests.sh --profile emu-tsan`

## Profiles

- `all`: full CTest run (default)
- `emu-required`: `emu.unit.*`
- `emu-optional`: `emu.conformance.*` + `emu.dump.*`
- `emu-conformance`: `emu.conformance.*`
- `emu-runtime-conformance`: runtime lavapipe conformance (`runtime_smoke_lavapipe` + `lavapipe_frame_hash` + `lavapipe_vi_filters_hash` + `lavapipe_vi_filters_mixed_hash` + `lavapipe_vi_downscale_hash`) with opt-in env automatically set
- `emu-dump`: `emu.dump.*`
- `emu-tsan`: `emu.unit.command_ring_policy` + `emu.unit.worker_thread` with ThreadSanitizer flags

## Triage Flow

1. Re-run the failing tier with output:
   - `./run-tests.sh --profile <profile> -- --output-on-failure`
2. For dump failures, run validator directly:
   - `rdp-validate-dump <dump>.rdp`
   - `rdp-validate-dump <dump>.rdp --sync-only`
3. If only optional tiers fail, keep required tier green and file follow-up with:
   - failing test name
   - ROM/dump used
   - commit SHA
   - platform + Vulkan driver string

## Notes

- `emu.dump.*` is skip-by-default without `rdp-validate-dump`.
- Baseline fixture is committed at `tests/rdp_dumps/baseline_minimal_eof.rdp`.
- Remote CI enforcement is intentionally disabled for now; run tiers locally.
- `emu-tsan` runs a compiler/runtime preflight first; if TSAN is unsupported locally it exits with a clear skip message.
- Set `EMU_TSAN_FORCE=1` to bypass preflight and force TSAN execution.
- Randomized ingest fuzz tests are deterministic by default and log their seed.
- Set `EMU_FUZZ_SEED=<value>` (hex or decimal) to reproduce/override `emu.unit.rdp_command_ingest` fuzz runs.
