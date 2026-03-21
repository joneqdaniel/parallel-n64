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
- runtime launches are standardized as fullscreen borderless windows for consistent local capture framing
- commands are sent serially over the stdin command interface
- `WAIT <seconds>` is a local adapter pseudo-command and is not forwarded to RetroArch
- the adapter disables savestate thumbnails in its per-run appendconfig because that frontend path currently destabilizes ParaLLEl-RDP save-state runs
- Paper Mario save/load flows currently require explicit waits after `SAVE_STATE` and `LOAD_STATE_SLOT 0` while we still rely on timing rather than explicit completion signals

Adapters should translate between systems.
They should not become the main source of truth for renderer correctness or scene semantics.

If an adapter starts carrying major project logic, move that logic into:

- the relevant implementation repo
- a fixture manifest
- or a planning document under [`docs/`](/home/auro/code/parallel-n64/docs)
