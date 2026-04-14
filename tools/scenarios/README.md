# Scenario Runners

This directory is for deterministic end-to-end workflows.

The shared runtime contract is documented in [MODEL.md](/home/auro/code/parallel-n64/tools/scenarios/MODEL.md).

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
- [`paper-mario-kmr-03-entry-5.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-kmr-03-entry-5.sh)
- [`paper-mario-kmr-03-entry-5.runtime.env`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-kmr-03-entry-5.runtime.env)
- [`paper-mario-file-select-input-probe.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-file-select-input-probe.sh)
- [`paper-mario-file-select-block-family-probe.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-file-select-block-family-probe.sh)
- [`paper-mario-file-select-tile-family-probe.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-file-select-tile-family-probe.sh)
- [`paper-mario-title-timeout-probe.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-title-timeout-probe.sh)
- [`paper-mario-phrb-authority-validation.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-phrb-authority-validation.sh)
- [`paper-mario-full-cache-phrb-authority-validation.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-full-cache-phrb-authority-validation.sh)
- [`paper-mario-full-cache-phrb-zero-config-refresh.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-full-cache-phrb-zero-config-refresh.sh)
- [`paper-mario-full-cache-phrb-authority-refresh.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-full-cache-phrb-authority-refresh.sh)
- [`paper-mario-selected-package-authority-validation.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-selected-package-authority-validation.sh)
- [`paper-mario-savefile-start.runtime.env`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-savefile-start.runtime.env)
- [`paper-mario-hos-05-entry-3.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-hos-05-entry-3.sh)
- [`paper-mario-hos-05-entry-3.runtime.env`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-hos-05-entry-3.runtime.env)
- [`remint-paper-mario-file-select-authority.sh`](/home/auro/code/parallel-n64/tools/scenarios/remint-paper-mario-file-select-authority.sh)
- [`remint-paper-mario-kmr-03-entry-5-authority.sh`](/home/auro/code/parallel-n64/tools/scenarios/remint-paper-mario-kmr-03-entry-5-authority.sh)
- [`remint-paper-mario-hos-05-entry-3-authority.sh`](/home/auro/code/parallel-n64/tools/scenarios/remint-paper-mario-hos-05-entry-3-authority.sh)
- [`stage-paper-mario-savefile.sh`](/home/auro/code/parallel-n64/tools/scenarios/stage-paper-mario-savefile.sh)

## Active Paper Mario Lanes

- [`paper-mario-title-screen.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-title-screen.sh), [`paper-mario-file-select.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-file-select.sh), and [`paper-mario-kmr-03-entry-5.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-kmr-03-entry-5.sh) are the repo-default authority fixtures. Their normal `on` runs now require a promoted enriched full-cache `PHRB` and fail closed if that runtime artifact is missing.
- [`paper-mario-phrb-authority-validation.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-phrb-authority-validation.sh) is the shared Paper Mario `PHRB` authority runner. It executes title screen, file select, and `kmr_03 ENTRY_5` against a supplied `.phrb`, records one validation summary, and rejects legacy runtime inputs.
- [`paper-mario-selected-package-authority-validation.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-selected-package-authority-validation.sh) is the stricter selected-package lane. It runs through the shared `PHRB` authority runner but still requires native sampled entries per fixture.
- [`paper-mario-full-cache-phrb-authority-validation.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-full-cache-phrb-authority-validation.sh) is the full-cache `PHRB` authority runner used by the default full-cache conformance wrapper.
- [`paper-mario-full-cache-phrb-zero-config-refresh.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-full-cache-phrb-zero-config-refresh.sh) is the maintained zero-context refresh workflow for the compat-only front-door lane.
- [`paper-mario-full-cache-phrb-authority-refresh.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-full-cache-phrb-authority-refresh.sh) is the maintained promoted-baseline refresh workflow for the enriched authority-context lane.
- [`paper-mario-title-timeout-selected-package-validation.sh`](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-title-timeout-selected-package-validation.sh) is the main selected-package timeout review surface. It emits selector, pool, seam-register, and alternate-source artifacts when the needed inputs are present.

## Common Experimental Overrides

- Use `RUNTIME_ENV_OVERRIDE=/abs/path/to/runtime.env` for temporary debug-only runs.
- Use `DISABLE_SCREENSHOT_VERIFY=1` only when a controlled experiment is expected to diverge from locked hashes.
- Runtime env overrides are auto-exported while sourcing, so `PARALLEL_RDP_*` toggles reach the RetroArch/core process.
- Prefer the real `PARALLEL_RDP_HIRES_FILTER_*` variable names. The older `HIRES_FILTER_*` names remain compatibility fallbacks only.

## Supplemental Research

- Deeper Paper Mario probe history, deferred seam evidence, offline tooling notes, and experimental runtime flags now live in [PAPER_MARIO_RUNTIME_RESEARCH.md](/home/auro/code/parallel-n64/docs/PAPER_MARIO_RUNTIME_RESEARCH.md).
- The controlling docs remain:
  - [Hi-Res Runtime Primary Plan](/home/auro/code/parallel-n64/docs/plans/hires_runtime_primary_plan.md)
  - [Project State](/home/auro/code/parallel-n64/docs/PROJECT_STATE.md)
  - [EMU_TESTING.md](/home/auro/code/parallel-n64/docs/EMU_TESTING.md)
