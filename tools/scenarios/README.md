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

Current Paper Mario runtime note:

- save/load command sequences use explicit local waits between state operations because immediate follow-up commands are not yet stable
- the tracked title-screen scenario depends on the adapter disabling savestate thumbnails, which removes the current save-state crash seen on the Vulkan HW-frame path
- the tracked title-screen scenario depends on the adapter disabling RetroArch quit confirmation so a single `QUIT` command exits cleanly
