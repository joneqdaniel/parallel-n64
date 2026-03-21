# Adapters

This directory is for wrapper glue that connects this repo to external projects and local tooling.

Expected adapter targets include:

- RetroArch command/control helpers
- Paper Mario debug/instrumentation helpers
- local environment discovery
- artifact collection and normalization

Current tracked adapter seeds:

- [`retroarch_stdin_session.sh`](/home/auro/code/parallel-n64/tools/adapters/retroarch_stdin_session.sh)

Adapters should translate between systems.
They should not become the main source of truth for renderer correctness or scene semantics.

If an adapter starts carrying major project logic, move that logic into:

- the relevant implementation repo
- a fixture manifest
- or a planning document under [`docs/`](/home/auro/code/parallel-n64/docs)
