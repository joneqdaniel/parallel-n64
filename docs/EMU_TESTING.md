# Emulator Test Tiers

This repo uses tiered, local-only emulator-behavior test gates to separate required checks from heavier optional checks.

## Runtime Emulator Test Rules

- run emulator-facing tests at `4x` internal scale
- run emulator-facing tests one at a time
- treat emulator-facing tests as display-occupying local runs
- standardize emulator-facing runtime scenarios as fullscreen windows for consistent screenshots
- do not start a tracked runtime scenario if another `retroarch` process is already running
- tracked RetroArch adapter launches are expected to enforce a runtime lock so concurrent scenario starts fail fast
- tracked runtime scenarios should not depend on global `~/.config/retroarch/saves`; save RAM belongs inside the bundle or an explicitly staged local asset
- do not try to parallelize runtime emulator tests just because build steps are parallelized

These rules matter because runtime emulator tests consume significant local resources and can interfere with each other visually.

## Local Commands

- Required gate (PR-safe):
  - `./run-tests.sh --profile emu-required`
- Optional conformance gate:
  - `./run-tests.sh --profile emu-conformance`
- Optional runtime conformance gate:
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
- `emu-runtime-conformance`: runtime conformance (`runtime_smoke_lavapipe` + `lavapipe_frame_hash` + `lavapipe_vi_filters_hash` + `lavapipe_vi_filters_mixed_hash` + `lavapipe_vi_downscale_hash` + `lavapipe_sm64_frame_hash` + `paper_mario_full_cache_phrb_authorities` + `paper_mario_full_cache_phrb_authorities_refresh` + `paper_mario_full_cache_phrb_authorities_zero_config_refresh` + `paper_mario_selected_package_authorities` + `paper_mario_selected_package_timeout_validation`) with opt-in env automatically set
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

- `ctest` execution in `run-tests.sh` is serial unless extra parallel flags are added manually.
- `run-tests.sh` parallelizes the build step, not the runtime test execution step.
- `emu.conformance.paper_mario_full_cache_phrb_authorities`, `emu.conformance.paper_mario_full_cache_phrb_authorities_refresh`, `emu.conformance.paper_mario_full_cache_phrb_authorities_zero_config_refresh`, `emu.conformance.paper_mario_selected_package_authorities`, and `emu.conformance.paper_mario_selected_package_timeout_validation` skip cleanly when the required local `PHRB` package or Paper Mario prerequisites are absent.
- Set `EMU_RUNTIME_PM64_FULL_CACHE_PHRB` to override the default zero-config full-cache `PHRB` path.
- Set `EMU_RUNTIME_PM64_FULL_CACHE_BUNDLE_ROOT` to keep the full-cache authority bundles instead of using a temporary directory.
- The shared `paper-mario-phrb-authority-validation.sh` lane now defaults `PARALLEL_RDP_HIRES_RUNTIME_SOURCE_MODE=phrb-only` unless the caller overrides it explicitly, so cache-directory validation does not rely on later source-mode checks to fence out legacy inputs.
- The explicit selected-package timeout validation lane now defaults the same source policy (`PARALLEL_RDP_HIRES_RUNTIME_SOURCE_MODE=phrb-only`) unless the caller overrides it explicitly, so both primary `PHRB` runtime lanes start from the same source-policy contract.
- Hi-res evidence and fixture verification now keep requested loader policy separate from actual loaded source mix: promoted default Paper Mario authority scenarios assert `source_policy=auto` with `source_mode=phrb-only`, while the explicit `PHRB` validation lanes assert both `source_policy=phrb-only` and `source_mode=phrb-only`.
- Set `EMU_RUNTIME_PM64_FULL_CACHE_CONTEXT_SUMMARY` to override the authority-summary-root input used by `emu.conformance.paper_mario_full_cache_phrb_authorities_refresh`.
- Set `EMU_RUNTIME_PM64_FULL_CACHE_REFRESH_OUTPUT_DIR` or `EMU_RUNTIME_PM64_FULL_CACHE_REFRESH_BUNDLE_ROOT` to keep the regenerated package and authority bundles from that refresh lane instead of using temporary directories.
- The default full-cache conformance path now prefers the latest regenerated authority-summary-root package at [`artifacts/hts2phrb-review/20260408-pm64-all-families-authority-context-abs-summary/package.phrb`](/home/auro/code/parallel-n64/artifacts/hts2phrb-review/20260408-pm64-all-families-authority-context-abs-summary/package.phrb), then falls back to the earlier authority-context artifact, and only then falls back to the zero-config `hts2phrb` artifact.
- The repo-default `paper-mario-title-screen.sh`, `paper-mario-file-select.sh`, and `paper-mario-kmr-03-entry-5.sh` authority scenarios now use that same preference order when no cache override is provided, so the normal `on` authority lane resolves to the enriched full-cache `PHRB` artifact whenever it is present.
- The current live full-cache runtime-contract baseline is [`artifacts/paper-mario-probes/validation/20260408-full-cache-phrb-authorities-authority-context-root-provenance-promoted-round2/validation-summary.json`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260408-full-cache-phrb-authorities-authority-context-root-provenance-promoted-round2/validation-summary.json): the enriched `phrb-only` lane keeps all three authority fixtures green with fully sampled descriptor traffic (`title-screen 268/0/0/0`, `file-select 214/0/0/0`, `kmr_03 ENTRY_5 182/0/0/0`) and `native_sampled_entry_count=503`.
- The broader combined-context package under [`artifacts/hts2phrb-review/20260408-pm64-all-families-authority-plus-timeout-context-root/package.phrb`](/home/auro/code/parallel-n64/artifacts/hts2phrb-review/20260408-pm64-all-families-authority-plus-timeout-context-root/package.phrb) remains review-only: it widens the package and stays fully sampled, but the authority rerun still changes `kmr_03 ENTRY_5` to `d3d2bf397d9bfd8cd311e51fc356a3130880b1ade5bbd53571ab815a08b965ad`, so it is not the active conformance baseline.
- When the enriched full-cache package is the active conformance input, `emu.conformance.paper_mario_full_cache_phrb_authorities` now enforces the locked authority screenshot hashes as well as `native_sampled_entry_count > 0`, `descriptor_path_class=sampled-only`, `descriptor_path_counts.generic == 0`, and `descriptor_path_counts.compat == 0` for every authority fixture. When that same wrapper is pointed at the zero-config fallback artifact instead, it now enforces the locked zero-config screenshot hashes plus `entry_class=compat-only` and `descriptor_path_class=compat-only` on every authority fixture.
- `emu.conformance.paper_mario_full_cache_phrb_authorities_refresh` goes one step further: it regenerates the enriched package from the legacy `.hts` cache plus the authority-summary-root context, then re-runs the full authority validation and asserts the current converter/runtime counts (`8883` package records, `28` runtime-ready native sampled records, `503` live native sampled entries, `context_bundle_class=context-enriched`, `package_manifest_runtime_ready_record_class=mixed-native-and-compat`, and the current locked sampled-only descriptor-path counts per fixture).
- `emu.conformance.paper_mario_full_cache_phrb_authorities_zero_config_refresh` does the same for the zero-context lane: it regenerates the front-door `PHRB` from the legacy `.hts` cache alone, then re-runs the authority validation and asserts the current compat-backed runtime shape (`8992` package records, `8613` runtime-ready compat records, `379` deferred records, `context_bundle_class=zero-context`, `package_manifest_runtime_ready_record_class=compat-only`, and the current locked compat-only descriptor-path counts for the zero-config lane).
- Representative converter operational gates now live in direct support tests as well:
  - `emu.support.hts2phrb_paper_mario_full_cache_contract` enforces `partial-runtime-package`, `10 s`, `2.1 GB`, and `--reuse-existing` for the current Paper Mario full-cache pack in both zero-context and authority-context modes.
  - `emu.support.hts2phrb_paper_mario_pre_v401_full_cache_contract` enforces the same output/cache shape with a `12 s` timing gate for the older pre-v401 Paper Mario full-cache pack.
- Those same authority and selected-package summaries now also expose native-checksum detail counts (`exact`, `identity_assisted`, `generic_fallback`) alongside the existing generic detail counts, so future non-sampled descriptor traffic can be triaged more precisely from one bundle.
- Set `EMU_RUNTIME_PM64_SELECTED_PHRB` to override the default selected-package path.
- Set `EMU_RUNTIME_PM64_SELECTED_LOADER_MANIFEST`, `EMU_RUNTIME_PM64_SELECTED_TRANSPORT_REVIEW`, `EMU_RUNTIME_PM64_SELECTED_ALT_SOURCE_CACHE`, or `EMU_RUNTIME_PM64_SELECTED_TIMEOUT_ON_HASH` to override the deeper timeout-lane defaults.
- Set `EMU_RUNTIME_PM64_SELECTED_TIMEOUT_EXPECTED_SAMPLED_DUPLICATE_KEYS` and `EMU_RUNTIME_PM64_SELECTED_TIMEOUT_EXPECTED_SAMPLED_DUPLICATE_ENTRIES` when validating a review-only duplicate-dedupe candidate that intentionally removes the active sampled-duplicate seam.
- [`tools/hires_pack_build_selected_package.py`](/home/auro/code/parallel-n64/tools/hires_pack_build_selected_package.py) now also accepts `--surface-transport-policy` when you need a review-only surface-package overlay reproduced through the normal selected-package build path.
- That same builder now also accepts `--alias-group-review` when you need a review-only broader asset-alias candidate reproduced through the normal selected-package build path.
- That same builder now also accepts `--review-profile` when you want one tracked review-only input to bundle duplicate-review, alias-group-review, review-pool, and surface-policy overlays without turning them into default behavior.
- The current tracked review-only profile is [`tools/hires_selected_package_review_profile.json`](/home/auro/code/parallel-n64/tools/hires_selected_package_review_profile.json), which reproduces the proven `7701ac09` duplicate-plus-alias shaping from one input.
- Set `EMU_RUNTIME_PM64_SELECTED_TIMEOUT_POOL_REGRESSION_FLAT_SUMMARY`, `EMU_RUNTIME_PM64_SELECTED_TIMEOUT_POOL_REGRESSION_DUAL_SUMMARY`, `EMU_RUNTIME_PM64_SELECTED_TIMEOUT_POOL_REGRESSION_ORDERED_SUMMARY`, or `EMU_RUNTIME_PM64_SELECTED_TIMEOUT_POOL_REGRESSION_SURFACE_PACKAGE` to override the bounded `1b8530fb` history used by the timeout-lane pool regression review.
- When `EMU_RUNTIME_PM64_SELECTED_TRANSPORT_REVIEW` is available, selected-package timeout validation emits `hires-sampled-selector-review.*` plus `hires-sampled-pool-review-*.{md,json}` into the bundle traces.
- When `EMU_RUNTIME_PM64_SELECTED_TIMEOUT_PACKAGE_MANIFEST` is also available, that same timeout lane emits `hires-sampled-duplicate-review-*.{md,json}` for the live duplicate buckets recorded in `hires-runtime-seam-register.*`.
- When those expected sampled-duplicate env vars are set to `0`, the timeout runtime-conformance lane now treats missing `hires-sampled-duplicate-review-*` artifacts as success and instead asserts that the duplicate seam has been eliminated from both provider counters and the seam register.
- When those transport inputs and the bounded `1b8530fb` historical summaries are available together, that same timeout lane also emits `hires-sampled-pool-regression-review-1b8530fb.{md,json}` into the bundle traces.
- When `EMU_RUNTIME_PM64_SELECTED_ALT_SOURCE_CACHE` is also available, that same timeout lane emits `hires-alternate-source-review.*` and folds the seeded candidate counts into `hires-runtime-seam-register.*`.
- When `EMU_RUNTIME_PM64_SELECTED_TIMEOUT_TITLE_GUARD_EVIDENCE` and `EMU_RUNTIME_PM64_SELECTED_TIMEOUT_FILE_GUARD_EVIDENCE` are available, that same timeout lane also emits `hires-sampled-cross-scene-review.*` and folds the promotion status into `hires-runtime-seam-register.*`.
- When both the alternate-source cache and timeout guard evidence are available together, that same timeout lane also emits `hires-alternate-source-activation-review.*` and folds the joined activation status plus `candidate_free_review_bounded_probe_count` into both `hires-runtime-seam-register.*` and the top-level validation summary.
- Set `EMU_RUNTIME_PM64_SELECTED_TIMEOUT_WORLD_GUARD_EVIDENCE` to add the selected-package non-menu authority as an extra guard label when you want the review to record whether a family is also present on the steady-state gameplay lane.
- For source-backed triangle promotion work, run `tools/hires_sampled_cross_scene_review.py` against the timeout and selected-package authority `hires-evidence.json` traces before emitting any zero-selector probe; `tools/hires_pack_emit_probe_pool_binding.py --selector-mode zero` now accepts that review and refuses shared-scene families unless `--allow-shared-scene-family` is passed explicitly.
- The timeout runtime-conformance lane currently asserts that the active `1b8530fb` pool remains `defer-runtime-pool-semantics` and `keep-flat-runtime-binding`.
- The same timeout lane also asserts that the live `1b8530fb` pool review still carries a non-empty `runtime_sample_replacement_id`, currently `legacy-038a968c-9afc43ab-fs0-1184x24`.
- The same timeout lane also asserts that the consolidated `1b8530fb` pool regression review still recommends `keep-flat-runtime-binding` with `defer-runtime-pool-semantics` as the follow-up.
- The same timeout lane now also records live `1b8530fb` pool-stream diagnostics in `hires-runtime-seam-register.*`; the current bounded conclusion is `33` unique observed `texel1-peer` selectors, `32` transitions, and no repeats inside the mapped set.
- The same timeout lane also asserts the current selected-package duplicate accounting: `sampled_index + sampled_dupe_entries == native_sampled_entry_count`, with the default Paper Mario selected package currently proving `sampled_dupe_keys=1` and `sampled_dupe_entries=1`.
- The same timeout lane also asserts that the live sampled-duplicate seam for `7701ac09` keeps a non-empty active `replacement_id`, currently `legacy-844144ad-00000000-fs0-1600x16`.
- The same timeout lane also asserts that the bounded duplicate review for `7701ac09` stays on `keep-runtime-winner-rule-and-defer-offline-dedupe`.
- For the review-only dedupe candidate [`20260407-selected-plus-timeout-960-v1-dedupe-7701ac09/package.phrb`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260407-selected-plus-timeout-960-v1-dedupe-7701ac09/package.phrb), override those same duplicate expectations to `0` / `0`; the conformance lane then asserts that the `7701ac09` sampled-duplicate seam disappears while the `960` image remains unchanged.
- For the broader review-only asset-alias candidate [`20260407-selected-plus-timeout-960-v1-dedupe-7701ac09-asset-alias-review/package.phrb`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260407-selected-plus-timeout-960-v1-dedupe-7701ac09-asset-alias-review/package.phrb), use those same `0` / `0` duplicate overrides plus `EMU_RUNTIME_PM64_SELECTED_TIMEOUT_PACKAGE_MANIFEST` pointed at the aliased package-manifest; the conformance lane then asserts that the broader group stays package-only and the `960` image remains unchanged.
- The review-only `1b8530fb` tail-slot candidate [`20260407-selected-plus-timeout-960-v1-1b85-tail-slot-review/package.phrb`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260407-selected-plus-timeout-960-v1-1b85-tail-slot-review/package.phrb) is not a runtime-conformance baseline.
  - It is authority-safe and `960`-hash-neutral, but it intentionally converts the live `1b8530fb` pool-conflict seam into `67` sampled-duplicate keys / entries and suppresses the pool-review artifact.
  - Validate it through the regular selected-package authority and timeout scripts, not through `emu.conformance.paper_mario_selected_package_timeout_validation`.
- The timeout validation summary now also surfaces `sampled_duplicate_probe`, so the active duplicate seam is visible in bundle evidence instead of only in provider counters.
- When selector review input is available, the timeout validation lane also emits `hires-runtime-seam-register.*` so the current deferred runtime set stays explicit in the bundle.
- `emu.dump.*` is skip-by-default without `rdp-validate-dump`.
- Baseline fixture is committed at `tests/rdp_dumps/baseline_minimal_eof.rdp`.
- Remote CI enforcement is intentionally disabled for now; run tiers locally.
- `emu-tsan` runs a compiler/runtime preflight first; if TSAN is unsupported locally it exits with a clear skip message.
- Set `EMU_TSAN_FORCE=1` to bypass preflight and force TSAN execution.
- Randomized ingest fuzz tests are deterministic by default and log their seed.
- Set `EMU_FUZZ_SEED=<value>` (hex or decimal) to reproduce/override `emu.unit.rdp_command_ingest` fuzz runs.
- `run-tests.sh` profile mapping/guard behavior is locked by `emu.unit.test_runner_profile_contract`.
- `run-dump-tests.sh` CLI/env handoff behavior is locked by `emu.unit.dump_runner_contract`.
- `run-build.sh` CLI/env handoff behavior is locked by `emu.unit.build_runner_contract`.
- `run-build.sh` auto-cleans when effective build flags change; set `RUN_BUILD_AUTO_CLEAN=0` to disable.
- `run-n64.sh` runtime launch contract behavior is locked by `emu.unit.run_n64_contract`.
