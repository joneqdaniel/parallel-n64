# Emulator Test Tiers

This repo uses tiered, local-only emulator-behavior test gates to separate required checks from heavier optional checks.

## Local Commands

- Required gate (PR-safe):
  - `./run-tests.sh --profile emu-required`
- Optional conformance gate:
  - `./run-tests.sh --profile emu-conformance`
- Optional dump-replay gate (provisions validator if missing):
  - `./run-dump-tests.sh --provision-validator`
- Optional combined non-required gate:
  - `./run-tests.sh --profile emu-optional`

## Profiles

- `all`: full CTest run (default)
- `emu-required`: `emu.unit.*`
- `emu-optional`: `emu.conformance.*` + `emu.dump.*`
- `emu-conformance`: `emu.conformance.*`
- `emu-dump`: `emu.dump.*`

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
