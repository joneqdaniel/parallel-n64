# Scenario Runners

This directory is for deterministic end-to-end workflows.

Use it for:

- launching RetroArch/core/content with known settings
- loading savestates or replay checkpoints
- capturing frames, screenshots, and logs
- comparing outputs against expected results
- producing small reproducible reports

Do not use it for:

- storing large assets
- game-specific source instrumentation
- permanent research notes

Scenario runners should consume fixture manifests from [`tools/fixtures/`](/home/auro/code/parallel-n64/tools/fixtures) and write generated output to [`artifacts/`](/home/auro/code/parallel-n64/artifacts).

Current tracked scenario seeds:

- [`paper-mario-title-screen.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-title-screen.sh)
- [`paper-mario-title-screen.runtime.env`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-title-screen.runtime.env)
- [`paper-mario-file-select.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-file-select.sh)
- [`paper-mario-file-select.runtime.env`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-file-select.runtime.env)

Current Paper Mario runtime note:

- save/load command sequences now use log-gated startup readiness and explicit command acknowledgements instead of blind timing where possible
- the tracked title-screen scenario depends on the adapter disabling savestate thumbnails, which removes the current save-state crash seen on the Vulkan HW-frame path
- the tracked title-screen scenario depends on the adapter disabling RetroArch quit confirmation so a single `QUIT` command exits cleanly
- the tracked title-screen and file-select scenarios now use a trustworthy fixture-relative `frame=` clock
- the canonical steady-state Paper Mario workflow is `load savestate -> settle 3 frames -> capture`
- controller scripts remain in the repo as bootstrap paths for minting or replacing authoritative savestates
