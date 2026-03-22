# Adapters

This directory is for wrapper glue that connects this repo to external projects and local tooling.

Expected adapter targets include:

- RetroArch command/control helpers
- Paper Mario debug/instrumentation helpers
- local environment discovery
- artifact collection and normalization

Current tracked adapter seeds:

- [`retroarch_stdin_session.sh`](/home/auro/code/parallel-n64/tools/adapters/retroarch_stdin_session.sh)

Current RetroArch adapter notes:

- the adapter refuses to start if any other `retroarch` process is already running
- the adapter now also holds a runtime lock so concurrent tracked launches cannot race past the singleton check
- runtime launches are standardized as fullscreen borderless windows for consistent local capture framing
- commands are sent serially over the stdin command interface
- `WAIT <seconds>` is a local adapter pseudo-command and is not forwarded to RetroArch
- `WAIT_STATUS_FRAME <state> <min_frame> <timeout_seconds>` is a local adapter pseudo-command for frame-aware waits based on `GET_STATUS`
- `WAIT_CORE_MEMORY_HEX <address> <number_of_bytes> <expected_hex> <timeout_seconds>` is a local adapter pseudo-command for exact RAM-signature waits
- `SNAPSHOT_CORE_MEMORY <label> <address> <number_of_bytes>` is a local adapter pseudo-command that captures a `READ_CORE_MEMORY` reply into a bundle trace file
- the adapter disables RetroArch quit confirmation in its per-run appendconfig so a single tracked `QUIT` command exits deterministically
- the adapter disables savestate thumbnails in its per-run appendconfig because that frontend path currently destabilizes ParaLLEl-RDP save-state runs
- the adapter disables RetroArch widgets and screenshot/save-state notifications in tracked runs so capture bytes remain stable
- the current RetroArch stdin agent command surface includes explicit pause, frame-step, savestate-load-paused, and input-port control commands
- tracked Paper Mario flows now use a log-gated startup handoff instead of blind startup sleeps
- when a core does not publish a libretro memory map, the local RetroArch build now falls back to `RETRO_MEMORY_SYSTEM_RAM` for `READ_CORE_MEMORY`

Adapters should translate between systems.
They should not become the main source of truth for renderer correctness or scene semantics.

If an adapter starts carrying major project logic, move that logic into:

- the relevant implementation repo
- a fixture manifest
- or a planning document under [`docs/`](/home/auro/code/parallel-n64/docs)
