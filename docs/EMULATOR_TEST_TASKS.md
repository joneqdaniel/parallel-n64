# Emulator Behavior Test Program (Non-HIRES)

## Purpose
- Build a broad, enforceable unit-test and conformance suite for emulator behavior before additional feature work.
- Keep this track independent from hi-res texture replacement work.

## Scope
- In scope:
  - `mupen64plus-video-paraLLEl/parallel.cpp`
  - `mupen64plus-video-paraLLEl/rdp.cpp`
  - `mupen64plus-video-paraLLEl/z64.h`
  - `mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/*`
  - Test harness + CI/CTest integration.
- Out of scope:
  - Hi-res texture replacement behavior and related cache/keying tests (tracked in `docs/HIRES_TEXTURE_TASKS.md`).
  - New rendering features that are not required to make tests deterministic and enforceable.

## Test Categories
- `tests/hires_textures`: existing hi-res-specific tests (no expansion in this plan).
- `tests/emulator_behavior`: new non-hi-res emulator behavior suite.
- Test naming:
  - Unit tests: `emu.unit.*`
  - Vulkan/software conformance: `emu.conformance.*`
  - Dump replay/regression: `emu.dump.*`

## Phase Roadmap
- [x] T0: Harness Foundations
  - Deliverables:
    - Introduce test doubles/fakes for Vulkan frontend/device/command processor seams.
    - Build deterministic fixture helpers for DP/VI register memory blocks.
    - Keep tests runnable on local machines without requiring a physical Vulkan GPU.
  - Exit criteria:
    - `ctest -R emu.unit` runs a seeded smoke target in `tests/emulator_behavior`.
    - No changes to runtime behavior in production builds.

- [x] T1: Plugin ABI and Entry-Point Contract Tests
  - Deliverables:
    - Lock down `parallelGetDllInfo`, `parallelPluginGetVersion`, and symbol export expectations.
    - Add null-outparam safety checks for version calls.
  - Exit criteria:
    - ABI tuple and strings are asserted exactly.
    - Entry-point tests pass on Linux local build.

- [x] T2: DP Command Ingestion Semantics (`process_commands`)
  - Deliverables:
    - XBUS vs DRAM path tests, alignment masking checks, invalid-address guards.
    - Incomplete-tail handling and DPC register reset behavior.
    - SyncFull interrupt behavior for async and synchronous modes.
  - Exit criteria:
    - Deterministic pass/fail for command parser invariants and MI interrupt signaling.

- [x] T3: Frame Lifecycle and VI Forwarding (`begin_frame`, `complete_frame`)
  - Deliverables:
    - Sync index resizing/wait tests.
    - VI register forwarding table assertions.
    - Null scanout image fallback behavior tests (1x1 image path).
    - `parallelUpdateScreen`/`parallelShowCFB` delegation and call ordering checks.
  - Exit criteria:
    - Output image metadata + scanout options are validated at API boundary.

- [ ] T4: Init/Deinit and Device Capability Gating
  - Deliverables:
    - `init()` precondition failures (`context`/`vulkan` missing).
    - Sync mask frame-count mapping checks.
    - External host memory alignment offset tests.
    - Unsupported-device fail-fast tests.
    - `deinit()` cleanup + idempotency tests.
  - Exit criteria:
    - Init/deinit state transitions are fully guarded by tests.

- [ ] T5: Option Wiring and Constants Sanity Locks
  - Deliverables:
    - Setter-to-global wiring tests for VI/filter/upscaling options.
    - Propagation checks from setters into `ScanoutOptions`.
    - Static assertions for interrupt/status constants in `z64.h`.
  - Exit criteria:
    - Changing option plumbing or constants causes immediate unit-test failures.

- [ ] T6: parallel-rdp Core Module Unit Tests (No Vulkan Rendering Required)
  - Deliverables:
    - `command_ring` FIFO/wrap/capacity tests.
    - `rdp_data_structures` size/layout assertions.
    - `rdp_common` opcode/length table tests (including SyncFull opcode handling).
    - LUT determinism/hash checks where applicable.
    - Worker thread shutdown and ordering tests.
  - Exit criteria:
    - Core data-structure and command-model regressions are caught without GPU replay.

- [ ] T7: Doc-Backed Behavior Conformance (Software Vulkan Tier)
  - Deliverables:
    - Small synthetic command-list tests for fill rect, texture load basics, sync commands, and VI scaling/crop.
    - Golden-image/hash checks on lavapipe (or equivalent software Vulkan).
  - Exit criteria:
    - `ctest -R emu.conformance` passes in local/software-Vulkan environment.

- [ ] T8: Dump Replay Regression Suite
  - Deliverables:
    - Curated dump corpus integrated from `DUMPING.md` workflow.
    - Replay checks with standard and sync-only validation modes.
  - Exit criteria:
    - `ctest -R emu.dump` passes on baseline corpus with stable hashes.

- [ ] T9: CI Gating and Developer Workflow
  - Deliverables:
    - Wire emulator behavior suite into `run-tests.sh` categories and CI jobs.
    - Define tiered gating:
      - required: `emu.unit.*`
      - optional/nightly: `emu.conformance.*`, `emu.dump.*`
    - Add failure triage docs and update contributor guidance.
  - Exit criteria:
    - PRs can be blocked on unit-regression failures.
    - Nightly job reports conformance drift with reproducible artifacts.

## Phase Execution Policy
- Work one phase at a time; no phase jumping.
- Each phase needs:
  - Explicit file list touched.
  - Test command transcript summary.
  - Green baseline before moving to next phase.

## Status Update Format
- `Phase`: active phase.
- `Done`: concrete work completed since last update.
- `Changed`: files edited.
- `Validated`: commands run + result.
- `Risks`: open technical risk items.
- `Next`: immediate next step.

## Current Status
- Active phase: `T4` (Init/Deinit and Device Capability Gating).
- Hi-res plan: on hold for new feature work until emulator behavior test baseline is established.

## Change Log
- 2026-03-05: Initialized non-hires emulator behavior test track and separated it from hi-res tasks.
- 2026-03-05: Completed `T0` harness scaffolding:
  - Added `tests/emulator_behavior/support/fake_rdp_seams.hpp` with deterministic fake seams for Vulkan frontend, command processor, and device-style call recording.
  - Added `tests/emulator_behavior/support/rdp_memory_fixture.{hpp,cpp}` to generate seeded DP/VI/RDRAM fixture state and a `GFX_INFO` binding.
  - Added `tests/emulator_behavior/emu_unit_smoke_test.cpp` and registered it as `emu.unit.smoke`.
  - Wired CMake via `tests/CMakeLists.txt` and `tests/emulator_behavior/CMakeLists.txt`.
- 2026-03-05: Validated `T0` exit gate with `./run-tests.sh -R emu.unit` (passes) and full suite `./run-tests.sh` (all current tests pass).
- 2026-03-05: Completed `T1` plugin ABI and entrypoint contract coverage:
  - Added `tests/emulator_behavior/emu_unit_plugin_contract_test.cpp`.
  - Added `emu.unit.plugin_contract` target to `tests/emulator_behavior/CMakeLists.txt`.
  - Locks:
    - `parallelGetDllInfo` exact ABI identity values.
    - `parallelPluginGetVersion` tuple + null-outparam tolerance.
    - Link-time symbol surface checks for key plugin entrypoints.
    - Delegation checks (`parallelProcessRDPList`, `parallelUpdateScreen`, `parallelShowCFB`) and `parallel_init`/`parallel_deinit` pointer semantics.
- 2026-03-05: Validated `T1` with `./run-tests.sh -R emu.unit` and full suite `./run-tests.sh` (all tests pass).
- 2026-03-05: Completed `T2` DP command-ingest coverage:
  - Extracted command ingestion core to `mupen64plus-video-paraLLEl/rdp_command_ingest.hpp`.
  - Updated `mupen64plus-video-paraLLEl/rdp.cpp::process_commands()` to delegate to the shared ingest helper.
  - Added `tests/emulator_behavior/emu_unit_rdp_command_ingest_test.cpp` with checks for:
    - DRAM and XBUS alignment/load behavior.
    - command buffer overflow guard behavior.
    - incomplete-tail handling (`DPC_START`/`DPC_CURRENT` reset to `DPC_END`).
    - opcode enqueue gating (`>= 8` only).
    - SyncFull async/synchronous behavior and signal->wait->interrupt ordering.
    - current high-address mask behavior in DRAM path.
- 2026-03-05: Validated `T2` with `./run-tests.sh -R emu.unit.rdp_command_ingest`, `./run-tests.sh -R emu.unit`, full suite `./run-tests.sh`, core build `./run-build.sh`, and 20s forced-`parallel` runtime smoke (`./run-n64.sh`).
- 2026-03-05: Started `T3` frame-lifecycle scaffolding:
  - Added `mupen64plus-video-paraLLEl/rdp_frame_mapping.hpp` with shared helpers for:
    - sync-mask to frame-count mapping (`begin_frame` resize behavior),
    - VI register forwarding table,
    - `ScanoutOptions` construction from runtime toggles.
  - Updated `mupen64plus-video-paraLLEl/rdp.cpp` to use the shared frame-mapping helpers in `begin_frame()` and `complete_frame()`.
  - Added `tests/emulator_behavior/emu_unit_rdp_frame_mapping_test.cpp` as `emu.unit.rdp_frame_mapping`.
  - Added checks for:
    - sync-mask mapping edge cases,
    - exact VI register forwarding order/value mapping,
    - scanout option propagation values and invariants.
- 2026-03-05: Validated current `T3` progress with:
  - `./run-tests.sh -R emu.unit`,
  - `./run-tests.sh`,
  - `./run-build.sh`,
  - `timeout --signal=INT --kill-after=5 20s ./run-n64.sh -- --verbose`.
- 2026-03-05: Completed `T3` frame-lifecycle + scanout fallback coverage:
  - Added `mupen64plus-video-paraLLEl/rdp_scanout_fallback.hpp` with:
    - canonical 1x1 null-scanout image create-info helper,
    - generic fallback sequencing helper used by runtime path.
  - Updated `mupen64plus-video-paraLLEl/rdp.cpp::complete_frame()` to use shared fallback helper (no behavior change intended).
  - Added `tests/emulator_behavior/emu_unit_rdp_scanout_fallback_test.cpp` as `emu.unit.rdp_scanout_fallback`.
  - Existing `T1` plugin-contract tests continue to cover `parallelUpdateScreen`/`parallelShowCFB` delegation and call ordering.
- 2026-03-05: Revalidated after `T3` completion with:
  - `./run-tests.sh -R emu.unit`,
  - `./run-tests.sh`,
  - `./run-build.sh`,
  - `timeout --signal=INT --kill-after=5 20s ./run-n64.sh -- --verbose`.
