# Hi-Res Runtime Primary Plan

## Why This Exists

- The current project direction is better than the earlier failed attempt.
- The current runtime contract is still too compatibility-shaped for the long-term goal.
- The next milestone should stop expanding compatibility machinery and instead make the native package/runtime seam authoritative.
- Paper Mario is the first authority game because it has the best current evidence, not because the architecture should remain Paper Mario-specific.

## Short Verdict

- Keep the current repo direction.
- Do not revive the failed branch's runtime lookup-mode matrix.
- Redirect the next milestone toward a native-first `PHRB` runtime contract.
- Treat legacy-pack runtime parity work as bounded compatibility research, not as the primary architecture.
- Provide a single-command generic conversion path for legacy packs, but do not let that convenience define the canonical runtime identity model.

## Plan Authority

- This document is the controlling execution plan for the hi-res runtime/package direction.
- Other planning docs may provide implementation detail, experiments, or alternate reasoning, but when sequencing or architectural priorities conflict, this document wins.
- Companion plans are still useful:
  - converter and parity work can borrow concrete implementation ideas
  - validation and confidence docs still define supporting evidence expectations
  - import-model docs still describe useful internal scaffolding
- The purpose of this document is to keep all of that work pointed at one outcome instead of letting adjacent plans re-fragment the sequence.

## Repo Integration Requirements

- The repo entrypoints must treat this document as the primary plan:
  - [`README.md`](/home/auro/code/parallel-n64/README.md)
  - [`AGENTS.md`](/home/auro/code/parallel-n64/AGENTS.md)
  - [`docs/README.md`](/home/auro/code/parallel-n64/docs/README.md)
  - [`docs/plans/README.md`](/home/auro/code/parallel-n64/docs/plans/README.md)
  - [`docs/plans/PHASE_OVERVIEW.md`](/home/auro/code/parallel-n64/docs/plans/PHASE_OVERVIEW.md)
  - [`docs/PROJECT_STATE.md`](/home/auro/code/parallel-n64/docs/PROJECT_STATE.md)
- Historical, research, or supporting docs may remain, but they should not present themselves as the active direction unless they explicitly supersede this document.
- The repo should not retain duplicate “active direction” plan docs that compete with this one for sequencing authority.
- The user-facing story should remain coherent across the repo:
  - runtime target: `PHRB`
  - legacy input path: `.hts` / `.htc`
  - public conversion front door: `hts2phrb`
  - auto-conversion convenience only after the promotion gate

## Current Assessment

### What Is Working

- The project now treats Glide-era packs as import input instead of product truth.
- The renderer has a real sampled-object exact-lookup seam in [`rdp_renderer.cpp`](/home/auro/code/parallel-n64/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_renderer.cpp).
- The tooling now carries canonical sampled-object identity, ordered surfaces, policy-backed selection, and reproducible evidence artifacts.
- Validation and fixtures are much more disciplined than the earlier failed branch.
- Using Paper Mario first is a reasonable bootstrap strategy because it currently has the deepest local evidence base.

### What Is Still Wrong

- Runtime lookup is still centered on `checksum64 + formatsize + selector` in [`texture_replacement.cpp`](/home/auro/code/parallel-n64/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/texture_replacement.cpp).
- `PHRB` stores richer identity than the loader actually uses.
- The sampled-object exact path is still narrow and should be treated as scoped, not complete.
- Validation is still too Paper-Mario-heavy and too shallow in runtime-class breadth to justify final architectural commitment or cross-game confidence.
- There are still likely general legacy-pack miss classes that should be investigated directly at runtime, especially CI palette parity and `LoadBlock` sampled-shape mismatch.

## Current Implementation State

### Completed Slices

- Validation trust is partially live:
  - semantic hi-res evidence now participates in pass/fail on the active title-screen and file-select fixtures
  - authority metadata drift on the active menu fixtures is corrected and covered by a direct contract test
- The first provider/loader seam preservation slice is in:
  - structured `PHRB` identity is preserved in memory instead of being discarded at load time
  - direct provider/package coverage now exists for that preserved identity
  - native sampled records now have a dedicated structured provider index instead of relying on reverse scans over compatibility-shaped storage
  - CI low32 fallback families are now explicitly compat-only and no longer silently read native `PHRB` sampled records
- The exact sampled-object seam is now improved:
  - the renderer can prefer structured provider lookup on exact sampled-object matches instead of relying only on recomposed legacy-style keys
  - the seam now reaches texrects plus the current narrow single-texture triangle case, and the active file-select / `kmr_03 ENTRY_5` authorities stayed runtime-neutral under that widening
  - the sampled seam now also has a bounded family-unique fallback after an exact miss: singleton sampled families can resolve through preserved native family identity without reopening pool or ordered-surface behavior
  - ordered-surface singleton sampled families now resolve through the provider's sampled-family singleton helper instead of bespoke renderer-side selection logic, so both the upload path and the texrect sampled path no longer have to reimplement that one-family rule outside the provider
  - hi-res evidence summaries now also keep `resolution_reason_counts`, so the current lanes can report how many hits came from sampled-family singleton resolution versus native-checksum, generic, or compat fallback reasons without re-reading raw logs
  - normal runtime summaries now also expose aggregate sampled singleton detail counts without requiring hit-side debug logging, so the live selected-package and authority lanes can distinguish plain sampled-family singleton traffic from ordered-surface singleton traffic even when `resolution_reason_counts` is absent; current rebuilt `960` selected-package proof is [`20260408-title-timeout-selected-package-sampled-detail-960-rebuilt/validation-summary.json`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260408-title-timeout-selected-package-sampled-detail-960-rebuilt/validation-summary.json) with `sampled_family_singleton=0` and `sampled_ordered_surface_singleton=33`
  - that widening stays fenced at the provider/runtime seam: direct provider coverage proves it remains disabled for multi-selector sampled pools and enabled for singleton sampled families only
  - generic exact-checksum descriptor resolution can now also stay on the native structured path when the provider proves the winning entry is a native `PHRB` record with preserved sampled identity, instead of collapsing immediately back to checksum-only handling
  - generic exact descriptor resolution now also preserves the provider's resolved selector/checksum pair when it stays on the generic path, so the live upload/descriptor seam no longer reverts that decision back to selector `0` before cache/decode
  - renderer tile-state bookkeeping now also keeps the resolved selector separate from the resolved replacement checksum, so sampled-object exact probing no longer has to infer selector identity from `checksum64` after a replacement hit
  - sampled-object probe evidence now also carries the original upload checksum separately from the resolved replacement checksum, so `upload_low32` / `upload_pcrc` in the runtime traces reflect the real upload identity instead of the winning replacement key
  - native sampled resident-image caching now carries the structured sampled identity fields all the way into the renderer cache key instead of collapsing back to checksum / selector only once provider lookup succeeds
  - native checksum fallback now also has its own resident-image cache source and decode path, so native `PHRB` hits no longer collapse back into the generic checksum cache when the structured sampled path cannot be used
- The earliest safe conversion front door exists:
  - `hts2phrb` is live as a wrapper over the current import/build pipeline
  - `hts2phrb --cache` now accepts either a direct legacy cache file or a cache directory; when a directory contains multiple legacy candidates, the report records the resolved source path, selection reason, and candidate list instead of silently hiding the ambiguity
  - `hts2phrb --bundle` now also accepts the artifact paths people actually have in hand: bundle directories, direct `traces/hires-evidence.json`, and `validation-summary.{json,md}` files
  - `hts2phrb --context-bundle` now accepts the same evidence inputs as an enrichment-only path: it merges sampled/CI context from one or more bundles without changing the requested family set, which lets full-cache conversion absorb known runtime identity where evidence already exists
  - validation-summary bundle resolution is now robust to the three path styles the repo actually emits today: summary-relative bundle paths, repo-root-relative bundle paths, and cwd-relative bundle paths; the resolved mode is recorded in `bundle_resolution.bundle_reference_mode`
  - `hts2phrb` now also supports a true zero-config entrypoint: if no bundle or family selectors are supplied it defaults to all-family inventory mode and writes to a derived `./artifacts/hts2phrb/<resolved-cache>-<path-tag>-<request-mode>/` directory instead of forcing explicit output plumbing for common review runs or colliding same-named packs from different directories
  - bundle-driven default output dirs are now also path-scoped to the resolved bundle root, so repeated runs against different `validation-summary.{json,md}` files with the same filename do not trample each other
  - the default stdout surface is now a concise human-readable summary with output/report paths; machine consumers can opt back into full JSON via `--stdout-format json`
  - `hts2phrb --reuse-existing` now lets repeat runs reuse a matching completed output directory instead of rebuilding from scratch, and it backfills older signature-less reports on the first rerun so pre-upgrade artifacts are not stranded
  - `hts2phrb --reuse-existing` is now fingerprint-aware on the resolved cache, bundle, and policy inputs, and it can reuse matching migration / manifest / runtime-overlay intermediates when a prior run was interrupted after those stages even if the final report and binary package are missing
  - `hts2phrb --reuse-existing` now also self-heals stale loader/package/report runtime-summary metadata in place: older artifacts with missing or `None` runtime class/count fields are normalized from the manifest records before reuse is accepted, so the front-door state stays readable instead of carrying forward ambiguous `None` summaries
  - `hts2phrb` now also accepts `--duplicate-review`, `--alias-group-review`, and `--review-profile`, applying the same review-only canonical package shaping already proven on the selected-package builder directly to the converter front door before package emission while keeping that shaping explicitly non-default
  - `hts2phrb` now emits a canonical loader manifest and canonical `PHRB` package first; the proxy-binding-driven runtime loader manifest is now an explicit runtime-overlay artifact instead of the converter's main success path, and in `--runtime-overlay-mode auto` it is skipped cleanly when no bundle or other runtime context is present
  - when the runtime overlay is skipped, `hts2phrb` no longer leaves behind placeholder `bindings.json` or `runtime-loader-manifest.json`; canonical-only runs now report `runtime_overlay_artifacts_emitted=false` and keep the overlay purely internal to reporting/gating
  - the emitted `PHRB` is now version `7` and carries an explicit runtime-ready record flag plus 64-bit blob offsets and preserved payload format metadata, so canonical non-runtime records can coexist with runtime-ready records without forcing fake sampled identities into the runtime loader or capping the binary package at a 32-bit blob span
  - `hts2phrb` now keeps legacy payload blobs on its own conversion path instead of inflating every runtime-ready record to raw RGBA, and its binary emitter streams those blobs directly from the legacy cache instead of assembling the whole runtime-ready payload in memory; the selected-package and review-oriented tooling still keeps PNG materialization as its default
  - deterministic singleton proxy groups can be auto-selected without widening default runtime behavior
  - bundle-driven conversion can now fall back to sampled-object top groups when a live evidence bundle has no CI-family list, so current selected-package runtime bundles remain usable as conversion seeds
  - the migration/import path now also lets `fs0` legacy families adopt sampled identities from matching `low32` context bundles when real runtime evidence exists; practical consequence: generic full-cache family stubs can now promote into native sampled canonical records without pretending the bundle chose the whole request set
  - `hts2phrb --all-families` now provides a zero-config inventory path over the resolved legacy cache; without sampled runtime context it no longer emits an empty diagnostic package, but instead emits a `canonical-package-only` result with runtime-deferred records and explicit `canonical-only-families` blockers
  - smoke coverage exists for the current skeleton path
  - round-trip coverage now proves the emitted `PHRB` preserves both the canonical package identity and the explicit runtime-ready/runtime-deferred split carried through migration, binding, and materialization
  - the converter report now also records per-stage timings and output-size telemetry, so later operational gating can build on measured report fields instead of ad hoc timing notes
  - the converter report now also records per-requested-family import/runtime state plus explicit promotion blockers, so `canonical-only`, `transport-unresolved`, and `missing-active-pool` outcomes are visible without manually diffing migration, binding, and package artifacts
  - every conversion now also emits `hts2phrb-summary.md`, so the front door leaves behind one readable outcome sheet instead of requiring direct inspection of multiple JSON artifacts
  - the front door now also supports explicit conversion gates (`--minimum-outcome`, `--require-promotable`, `--max-total-ms`, and `--max-binary-package-bytes`), so later operational policy can fail cleanly on the tool itself instead of only in wrapper scripts
  - the front door now also supports explicit runtime-class gates (`--expect-context-class` and `--expect-runtime-ready-class`), so wrapper workflows can assert whether a run is supposed to stay zero-context compat-backed or context-enriched mixed-native-and-compat without re-deriving that from record counts alone
  - practical consequence: canonical-package-first automation no longer has to pretend every successful conversion is runtime-promotable; wrappers can gate explicitly on `canonical-package-only`, and `partial-runtime-package` remains reserved for cases where runtime-ready package records actually exist
  - every conversion now also emits `hts2phrb-family-inventory.json` and `hts2phrb-family-inventory.md`, so the readable summary can stay compact while the exhaustive per-family import/runtime state stays attached to the same run artifact
  - the current representative Paper Mario timeout-slice converter report now exists at [`artifacts/hts2phrb/paper-mario-hirestextures-9fa7bc07-bundle-timeout-960-4df05131/hts2phrb-report.json`](/home/auro/code/parallel-n64/artifacts/hts2phrb/paper-mario-hirestextures-9fa7bc07-bundle-timeout-960-4df05131/hts2phrb-report.json)
  - current outcome on that local `960` slice via the current saved timeout proof: `10` requested families, `10` canonical package records, `0` runtime-ready package records, `0` deterministic bindings, `0` transport-unresolved families, `runtime_overlay_built=false`, `runtime_overlay_reason=no-runtime-ready-records`, `runtime_overlay_artifacts_emitted=false`, `conversion_outcome=canonical-package-only`, and two explicit blocker classes (`missing-active-pool-families=10`, `canonical-only-families=10`)
  - the paired family inventory at [`artifacts/hts2phrb/paper-mario-hirestextures-9fa7bc07-bundle-timeout-960-4df05131/hts2phrb-family-inventory.md`](/home/auro/code/parallel-n64/artifacts/hts2phrb/paper-mario-hirestextures-9fa7bc07-bundle-timeout-960-4df05131/hts2phrb-family-inventory.md) now shows the whole requested timeout slice as `import-unresolved` plus `canonical-only`, with every family currently classified as `missing-active-pool`
  - practical consequence: operational telemetry is now real, the converter no longer depends on runtime bindings to emit a meaningful package, and the timeout slice now confirms the deeper limitation more cleanly than before: current bundle/runtime context is enough to build the canonical package, but still not enough to promote any of those ten families into runtime-ready package records, so auto overlay now stays off instead of emitting empty overlay artifacts
  - the same canonical-first rule now also applies one step later in auto mode: when runtime-ready package records do exist but binding selection still produces zero deterministic bindings, the converter keeps the package outcome, records the gap in the report/warnings, and skips overlay artifacts instead of emitting empty `bindings.json` / runtime-loader outputs
  - emitted loader manifests and package manifests now carry their own runtime-ready/deferred native-vs-compat counts, per-kind counts, and record-class strings, so the front door and its reuse/consistency checks can read those summaries directly instead of re-deriving the class split from scratch on every rerun
  - `--reuse-existing` now invalidates on runtime-class and per-kind drift too, not just total runtime-ready counts, so stale manifests cannot silently reuse a report that claims the wrong native-vs-compat package shape or record-kind composition
  - `hts2phrb-progress.json` now carries the same runtime-ready/deferred native-vs-compat counts, per-kind counts, and class strings while package materialization is still in flight, so long-running or interrupted front-door runs expose more than just raw record totals
  - the zero-config full Paper Mario legacy-cache run now completes through the same canonical-first path at [`artifacts/hts2phrb-review/20260407-pm64-all-families-streaming-v7-legacy-blobs/hts2phrb-report.json`](/home/auro/code/parallel-n64/artifacts/hts2phrb-review/20260407-pm64-all-families-streaming-v7-legacy-blobs/hts2phrb-report.json)
  - current outcome on that full local cache: `8992` requested families, `8992` canonical package records, `8613` runtime-ready package records, `379` runtime-deferred package records, `0` deterministic bindings, `0` transport-unresolved families, `runtime_overlay_built=false`, `runtime_overlay_reason=no-runtime-context`, `runtime_overlay_artifacts_emitted=false`, `conversion_outcome=partial-runtime-package`, one remaining blocker class (`canonical-only-families=379`), and a `1.94 GB` `PHRB`
  - the current full-cache timings now show the storage-model fix clearly: `materialize_package ≈ 272 ms`, `emit_binary_package ≈ 2.23 s`, `total ≈ 3.93 s`
  - the default zero-config output directory is now healthy again after the reuse-consistency fix: [`artifacts/hts2phrb/paper-mario-hirestextures-9fa7bc07-all-families/hts2phrb-report.json`](/home/auro/code/parallel-n64/artifacts/hts2phrb/paper-mario-hirestextures-9fa7bc07-all-families/hts2phrb-report.json) now also reads `partial-runtime-package` with the same `8613` runtime-ready records instead of the stale all-deferred `canonical-package-only` state, and the refreshed report now makes the class split explicit: `context_bundle_class=zero-context`, `package_manifest_runtime_ready_record_class=compat-only`, `0` runtime-ready native-sampled records, `8613` runtime-ready compat records, `package_manifest_runtime_deferred_record_class=compat-only`, and `379` deferred compat records
  - zero-config full-cache authority proof is now explicit at [`artifacts/paper-mario-probes/validation/20260407-full-cache-phrb-authorities-default-artifact/validation-summary.json`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-full-cache-phrb-authorities-default-artifact/validation-summary.json): title screen, file select, and `kmr_03 ENTRY_5` all pass with `provider=on`, `source_mode=phrb-only`, `entry_count=12420`, and `native_sampled_entry_count=0`
  - that same authority proof now records descriptor-path counts directly in the summary, and the current front-door package is unambiguously compat-path-backed (`title-screen compat=178`, `file-select compat=82`, `kmr_03 ENTRY_5 compat=112`, with `sampled=0`, `native_checksum=0`, `generic=0` on all three); the shared summary now also classifies that lane explicitly as `entry_class=compat-only` plus `descriptor_path_class=compat-only`
  - the current recommended full-cache context-enriched converter proof now exists at [`artifacts/hts2phrb-review/20260408-pm64-all-families-authority-context-abs-summary/hts2phrb-report.json`](/home/auro/code/parallel-n64/artifacts/hts2phrb-review/20260408-pm64-all-families-authority-context-abs-summary/hts2phrb-report.json): a single `--context-bundle` authority summary still expands to `3` fixture bundles (`context_bundle_inputs=1`, `context_bundles=3`), `8992` requested families now collapse to `8883` package records with `28` canonical sampled records, `8508` runtime-ready package records, `375` canonical-only families, `15` deterministic bindings, and `13` unresolved overlay families; the refreshed report also shows the class split directly: `context_bundle_class=context-enriched`, `package_manifest_runtime_ready_record_class=mixed-native-and-compat`, `28` native-sampled records, `8480` compat records, `package_manifest_runtime_deferred_record_class=compat-only`, and `375` deferred compat records
  - the same artifact now also emits a dedicated runtime-overlay review at [`hts2phrb-runtime-overlay-review.md`](/home/auro/code/parallel-n64/artifacts/hts2phrb-review/20260408-pm64-all-families-authority-context-abs-summary/hts2phrb-runtime-overlay-review.md), so the remaining `13` overlay misses no longer travel as a dead counter; current review result is still `manual-review-required` / `proxy-transport-selection-required`, but the new hash review shows the residue is genuinely divergent rather than a hidden auto-collapse case: `8` entries are `pixel-divergent-single-dim`, `5` are `pixel-divergent-multi-dim`, there are no zero-error decode failures, and the only exact cross-policy pairings are the two small `fs259` / `fs4` pairs (`identical_alpha_hash_case_count_counts = 0:9, 1:4`)
  - the full-cache family inventory now also counts legacy `fs0` families absorbed into sampled canonical records through `asset_candidates`, so the front-door state no longer overstates missing families just because a sampled record owns multiple legacy uploads; current enriched inventory is `runtime-ready-package=8617`, `canonical-only=375`, and no longer reports the stale `115`-family `diagnostic-only` bucket. The paired unresolved-family review at [`hts2phrb-unresolved-family-review.md`](/home/auro/code/parallel-n64/artifacts/hts2phrb-review/20260408-pm64-all-families-authority-context-abs-summary/hts2phrb-unresolved-family-review.md) now makes the remaining blocker class explicit: all `379` unresolved import families are still `exact-family-ambiguous`, `375` remain `canonical-only`, and `4` already land in `runtime-ready-package` via one canonical sampled object
  - that same enriched path now uses three bounded converter improvements instead of new runtime fallbacks: authority-context exact families are no longer dropped during canonical transport construction, `--context-bundle` can now harvest full provenance-hit rows from each bundle `log_path` when the summarized buckets do not carry enough sampled geometry to promote a family, and triangle sampled-probe promotion now requires concrete family signal instead of accepting empty `0x0` review groups
  - the paired fresh authority proof at [`artifacts/paper-mario-probes/validation/20260408-full-cache-phrb-authorities-authority-context-abs-summary-fresh/validation-summary.json`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260408-full-cache-phrb-authorities-authority-context-abs-summary-fresh/validation-summary.json) is now the clearest current full-cache runtime-contract picture in the repo: all three fixtures still pass with `provider=on` and `source_mode=phrb-only`, `native_sampled_entry_count=503`, fully sampled descriptor usage on every authority fixture (`title-screen 268/0/0/0`, `file-select 214/0/0/0`, `kmr_03 ENTRY_5 182/0/0/0`), and the locked screenshot hashes preserved; the shared authority summary now also labels that lane as `descriptor_path_class=sampled-only` on every fixture
  - local legacy-pack variant breadth is now codified on the converter path as well: the repo-local pre-v401 Paper Mario cache proves the same class shape at [`artifacts/hts2phrb-review/20260408-pm64-pre-v401-all-families-zero-context/hts2phrb-report.json`](/home/auro/code/parallel-n64/artifacts/hts2phrb-review/20260408-pm64-pre-v401-all-families-zero-context/hts2phrb-report.json) and [`artifacts/hts2phrb-review/20260408-pm64-pre-v401-all-families-authority-context/hts2phrb-report.json`](/home/auro/code/parallel-n64/artifacts/hts2phrb-review/20260408-pm64-pre-v401-all-families-authority-context/hts2phrb-report.json): zero-context stays `context_bundle_class=zero-context` plus `package_manifest_runtime_ready_record_class=compat-only`, while authority-context stays `context_bundle_class=context-enriched` plus `package_manifest_runtime_ready_record_class=mixed-native-and-compat`; the exact counts differ slightly (`8983/8599/384` zero-context and `8874/8494/380` authority-context), but the converter contract shape holds across both local Paper Mario legacy variants
  - authority and selected-package validation summaries now also carry native-checksum descriptor detail counts (`exact`, `identity_assisted`, `generic_fallback`) alongside the older generic detail counts, so future non-sampled traffic can be classified more precisely than “native checksum” versus “generic”
  - the shared `paper-mario-phrb-authority-validation.sh` runner now also defaults its runtime source policy to `phrb-only`, so directory-backed `PHRB` validation lanes stop depending on post-run source-mode checks alone to exclude legacy cache inputs
  - the live-core generic-detail rerun at [`artifacts/paper-mario-probes/validation/20260408-full-cache-phrb-authorities-authority-context-root-native-checksum-fallback-v2/validation-summary.json`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260408-full-cache-phrb-authorities-authority-context-root-native-checksum-fallback-v2/validation-summary.json) is still useful historical context because it proved the intermediate residue was plain generic, not identity-assisted; from there the compat-lane proof and the provenance-promoted round-trip show the remaining gap was converter-side exact-family promotion, not another renderer fallback seam
  - adding the current selected-package timeout bundle as a fourth context source now does widen the package slightly (`29` canonical sampled records instead of `28`), but the resulting authority rerun still changes the `kmr_03 ENTRY_5` screenshot hash to `d3d2bf397d9bfd8cd311e51fc356a3130880b1ade5bbd53571ab815a08b965ad` even after loader-manifest upload normalization; that combined-context package is therefore useful review-only evidence, not the promoted full-cache baseline
  - the runtime-conformance tier now also has a refresh gate for this full-cache lane: `emu.conformance.paper_mario_full_cache_phrb_authorities_refresh` regenerates the enriched package from the legacy `.hts` cache plus the authority-summary-root context and then re-runs the authority validation against the current converter counts, live overlay counts (`15` bindings / `13` unresolved), locked screenshot hashes, and sampled-only descriptor-path counts
  - representative converter operational gates now also exist for the two local full-cache legacy variants the repo can exercise today:
    - [`emu_hts2phrb_paper_mario_full_cache_contract.sh`](/home/auro/code/parallel-n64/tests/emulator_behavior/support/emu_hts2phrb_paper_mario_full_cache_contract.sh) now requires the current Paper Mario cache to stay at least `partial-runtime-package`, remain within `10 s` and `2.1 GB`, and prove `--reuse-existing` on both zero-context and authority-context reruns
    - [`emu_hts2phrb_paper_mario_pre_v401_full_cache_contract.sh`](/home/auro/code/parallel-n64/tests/emulator_behavior/support/emu_hts2phrb_paper_mario_pre_v401_full_cache_contract.sh) enforces the same outcome, cache-reuse, and output-size shape on the older pre-v401 cache, with a looser `12 s` timing gate for that asset set
    - practical consequence: representative converter timing, cache behavior, and output-size gates are now real for the local Paper Mario full-cache path; the remaining converter-breadth gap is cross-game input availability, not lack of any operational gate
  - the low-level provider default now also resolves cache directories in `auto` mode, not `all`, so runtime entrypoints and direct provider callers now share the same `.phrb`-first mixed-directory behavior unless they opt into `all` explicitly
  - the provider exact-checksum helper is now explicitly native-first only for `PHRB` family-runtime compat stubs: if a family-runtime compat record shares a checksum with a native sampled record, generic exact lookup resolves the native sampled entry instead of letting the later family stub win by load order, while explicit legacy compat aliases still remain available through the compat path
  - practical consequence: the default front-door `PHRB` is now a real replacement path for the current Paper Mario authority set, and the context-enriched full-cache lane is no longer merely “mostly sampled” or “generic-free”; for the authority fixtures it is now fully sampled without reopening the deferred pool/source seams or requiring proxy bindings to be the converter's main product
  - the intermediate repo-local all-families artifacts that still read `canonical-package-only` or the temporary raw-RGBA `51 GB` state are now stale relative to this legacy-payload v7 slice; treat them as historical pre-v7 evidence, not the current converter state
  - current limitation: a broader local search still turns up only Paper Mario legacy packs; local converter breadth now covers both the current and pre-v401 Paper Mario variants, but cross-game converter breadth remains an explicit open gate rather than an implied one
  - practical consequence: the converter is now a viable common-case front door for both canonical package generation and exact-authority runtime-ready family emission on the full Paper Mario legacy cache without an explosive size/runtime penalty; the remaining gaps are the last `379` canonical-only families, runtime-overlay promotion, and cross-game breadth
  - `hts2phrb-progress.json` is now always written during conversion, so long or externally-timed-out runs still leave behind stage-level and package-materialization progress instead of disappearing mid-run
- The first CI palette investigation slice is complete enough to bound the next step:
  - the obvious palette-CRC and TLUT-shadow candidates have been tested
  - the remaining gap still needs formal classification instead of open-ended per-family debugging
- Review-only surface-policy overlays are now part of the tracked offline workflow:
  - [`tools/hires_apply_surface_transport_policy.py`](/home/auro/code/parallel-n64/tools/hires_apply_surface_transport_policy.py) can now carry `allow_runtime_selector_compile` through policy overlays instead of only slot aliases and selector modes
  - [`tools/hires_pack_build_selected_package.py`](/home/auro/code/parallel-n64/tools/hires_pack_build_selected_package.py) now accepts `--surface-transport-policy` so review-only surface-package experiments can be reproduced through the normal selected-package builder instead of manual two-step package surgery
  - direct support coverage now exists for both the policy tool and the builder hook
- Validation breadth is no longer menu-only:
  - the first deterministic non-menu Paper Mario authority fixture is now active at `kmr_03 ENTRY_5`
  - the fixture is savestate-backed, semantically gated in both `off` and `on`, and records the earlier live timeout-probe hash as lineage evidence instead of confusing it with the savestate steady-state capture
- Native selected-package review is now explicit on deeper validation bundles:
  - timeout selected-package summaries now keep exact-hit, exact-miss, conflict-miss, and unresolved-miss counts together instead of collapsing back to hits versus misses only
  - sampled selector review can now classify top conflict/unresolved families against a package loader manifest as `absent-from-package`, `present-selector-conflict`, or stronger matches
  - the same review can now also classify whether absent families still have legacy transport candidates or are already candidate-free under the current `.hts` transport model
- Native pool-conflict diagnostics are now part of the runtime contract:
  - the provider keeps a family-level native sampled index in addition to exact selector keys
  - direct provider/package coverage now proves that multi-selector sampled families stay visible as pools without silently collapsing selector conflicts
  - sampled exact-miss debug logging can now report whether the runtime is looking at an absent family, a selector conflict, or a native pool conflict, along with the preserved `policy_key` and `sampled_object_id`
- Mixed-source runtime precedence is now explicit:
  - cache-directory loading now prefers `PHRB` records over legacy `.hts` / `.htc` duplicates regardless of filename sort order
  - direct provider coverage now proves mixed cache directories keep compat entries available without allowing them to override duplicate `PHRB` keys by load-order accident
  - the provider now also keeps explicit native-checksum and compat-checksum duplicate indices, so exact duplicate families can be addressed intentionally instead of only through “latest entry wins” behavior
  - practical consequence: compat exact helpers and compat low32 unique lookup now stay inside the compat pool even when a native `PHRB` duplicate with the same checksum is present
  - the renderer now mirrors that split for CI fallback descriptors as well, so compat-selected checksum keys get their own resident-image cache namespace and decode path instead of slipping back through the generic/native descriptor cache
  - proof bundle: [`20260406-225500-title-timeout-selected-package-compat-resolver-split/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-225500-title-timeout-selected-package-compat-resolver-split/validation-summary.md)
  - current effect: the explicit selected-package `PHRB` lane stays hash-identical and `phrb-only`, while mixed-cache compat CI resolutions are fenced away from native duplicate descriptor reuse
- The first intentionally rejected family case is now explicit negative data:
  - re-adding `28916d63` to the active `1b85` gameplay package increases native exact hits and converts many `960`-frame misses into selector conflicts
  - but it revives the previously dropped strict title/file hashes and leaves the `960` gameplay image unchanged
  - practical consequence: `28916d63` stays rejected for promotion in the current active package context unless new evidence changes that verdict
- The bounded `LoadBlock` investigation now has explicit decision artifacts:
  - the dominant file-select `64x1 fs514` loadblock family classifies as `no-simple-loadblock-retry`
  - the title `2048x1 fs515` loadblock family lands on the same outcome
  - those results now live in dedicated offline analyzer reports instead of only in free-form notes

### Still Open

- Structured sampled-object lookup is now indexed natively inside the provider, but it is not yet the primary runtime key across the full renderer path.
- `.phrb` is not yet the only production runtime source.
- Ordered-surface runtime preservation is not complete.
- `tlut_type` is not yet a first-class runtime identity field.
- The planned non-Paper-Mario zero-config converter proof is locally blocked right now because the workspace still has no non-Paper-Mario `.hts` / `.htc` pack to run through the front door; this is an input gap, not an intentionally skipped validation step.
- The current timeout worklist is now led by sampled families that are absent from the active package, especially the dominant `2cycle` triangle families `91887078`, `6af0d9ca`, and `e0d4d0dc`.
- The timeout worklist is now split more sharply:
  - the dominant absent `2cycle` triangle families `91887078`, `6af0d9ca`, and `e0d4d0dc` are already candidate-free under the current legacy `.hts` transport model
  - the new alternate-source review lane now proves those same three families are not source-empty: the current cache can seed `1` `16x32`, `7` `32x32`, and `5` `32x16` review-only candidates for `91887078`, `6af0d9ca`, and `e0d4d0dc` respectively
  - current alternate-source proof:
    - bundle summary: [`20260406-214200-title-timeout-selected-package-runtime-alt-source/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-214200-title-timeout-selected-package-runtime-alt-source/validation-summary.md)
    - alternate-source review markdown: [`20260406-214200-title-timeout-selected-package-runtime-alt-source/on/timeout-960/traces/hires-alternate-source-review.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-214200-title-timeout-selected-package-runtime-alt-source/on/timeout-960/traces/hires-alternate-source-review.md)
    - alternate-source review json: [`20260406-214200-title-timeout-selected-package-runtime-alt-source/on/timeout-960/traces/hires-alternate-source-review.json`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-214200-title-timeout-selected-package-runtime-alt-source/on/timeout-960/traces/hires-alternate-source-review.json)
  - the same timeout lane now also has an explicit cross-scene promotion gate for the current triangle trio:
    - cross-scene review markdown: [`20260406-214200-title-timeout-selected-package-runtime-alt-source/on/timeout-960/traces/hires-sampled-cross-scene-review.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-214200-title-timeout-selected-package-runtime-alt-source/on/timeout-960/traces/hires-sampled-cross-scene-review.md)
    - cross-scene review json: [`20260406-214200-title-timeout-selected-package-runtime-alt-source/on/timeout-960/traces/hires-sampled-cross-scene-review.json`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-214200-title-timeout-selected-package-runtime-alt-source/on/timeout-960/traces/hires-sampled-cross-scene-review.json)
    - current result: before any promotion, `91887078` and `e0d4d0dc` already share the same absent runtime signatures with title screen and file select, while `6af0d9ca` is shared with title screen and absent on both file select and the steady-state selected-package `kmr_03 ENTRY_5` authority
    - practical consequence: there is still no observed runtime discriminator for any of the current candidate-free triangle families yet, but the world-absent boundary is now explicit, so promotion work depends on a tighter discriminator or scene-bounded activation model rather than on better timeout-side capture
  - the same timeout lane now also emits a joined alternate-source activation review so the shallow source-backed boundary is explicit in one artifact:
    - proof bundle: [`20260407-selected-package-duplicate-review/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-selected-package-duplicate-review/validation-summary.md)
    - activation review markdown: [`20260407-selected-package-duplicate-review/on/timeout-960/traces/hires-alternate-source-activation-review.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-selected-package-duplicate-review/on/timeout-960/traces/hires-alternate-source-activation-review.md)
    - activation review json: [`20260407-selected-package-duplicate-review/on/timeout-960/traces/hires-alternate-source-activation-review.json`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-selected-package-duplicate-review/on/timeout-960/traces/hires-alternate-source-activation-review.json)
    - current result: all three source-backed triangle families still classify as `shared-scene-source-backed-candidates`, the joined review reports `review_bounded_probe_count=0` and `shared_scene_blocked_count=3`, and the seam register now carries `candidate_free_review_bounded_probe_count=0`
    - practical consequence: the next shallow step is no longer “find any source” or “re-check cross-scene overlap”; it is “wait for a tighter discriminator or scene-bounded activation model,” because the current joined review still blocks every source-backed triangle family from promotion
  - the first bounded promotion probe is also now recorded:
    - candidate package: [`20260406-selected-plus-timeout-960-v3-add-9188-zero/package.phrb`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260406-selected-plus-timeout-960-v3-add-9188-zero/package.phrb)
    - timeout proof: [`20260406-220100-title-timeout-selected-package-9188-zero/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-220100-title-timeout-selected-package-9188-zero/validation-summary.md)
    - selected-package authority proof: [`20260406-221400-selected-package-authorities-9188-zero/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-221400-selected-package-authorities-9188-zero/validation-summary.md)
    - current result: a zero-selector singleton for `91887078` converts all `10296` of that family's timeout misses into exact hits and leaves the `960` gameplay frame byte-identical, but it changes the selected-package title and file-select authority screenshots sharply while leaving `kmr_03 ENTRY_5` unchanged
    - practical consequence: source-backed triangle candidates stay review-only for now; zero-selector is not a safe default promotion path for this seam, and the probe emitter now requires an explicit override when a cross-scene review reports `no-runtime-discriminator-observed`
  - deeper timeout checkpoints now prove the source seam drifts with game phase instead of staying fixed to the `960` frame:
    - phase-drift bundle: [`20260406-222138-title-timeout-selected-package/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-222138-title-timeout-selected-package/validation-summary.md)
    - `1200` result: the selected-package lane enters battle (`state_init_battle` / `state_step_battle`, `kmr_03`, `entry 0`) and broadens the candidate-free set beyond the original triangle trio
    - `1500` result: the lane returns to world (`state_init_world` / `state_step_world`, `kmr_06`, `entry 3`) and the selected-package capture matches `off` exactly even though review-only source candidates and world-shared partial-overlap seams are still present
    - practical consequence: keep `960` as the bounded source-path activation target for now; later checkpoints are evidence about phase drift, not immediate promotion targets
  - `28916d63` remains absent from the active package, but it is candidate-backed negative data rather than an open promotion target
- The remaining active-package seam on the current `960` bundle is `1b8530fb`, but it now classifies more narrowly as a `present-pool-selector-conflict`.
  - practical consequence: this is not a simple one-record selector alias; any future attempt to close it must preserve the pool semantics instead of collapsing `33` candidates onto one selector.
  - the live selected-package timeout lane now emits the family-level selector review, the pool-shape review, the seam register, and a consolidated flat-vs-surface regression review:
    - selected-package timeout bundle: [`20260407-selected-package-pool-regression-review/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-selected-package-pool-regression-review/validation-summary.md)
    - selector review markdown: [`20260407-selected-package-pool-regression-review/on/timeout-960/traces/hires-sampled-selector-review.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-selected-package-pool-regression-review/on/timeout-960/traces/hires-sampled-selector-review.md)
    - pool review markdown: [`20260407-selected-package-pool-regression-review/on/timeout-960/traces/hires-sampled-pool-review-1b8530fb.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-selected-package-pool-regression-review/on/timeout-960/traces/hires-sampled-pool-review-1b8530fb.md)
    - seam register markdown: [`20260407-selected-package-pool-regression-review/on/timeout-960/traces/hires-runtime-seam-register.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-selected-package-pool-regression-review/on/timeout-960/traces/hires-runtime-seam-register.md)
    - pool regression review markdown: [`20260407-selected-package-pool-regression-review/on/timeout-960/traces/hires-sampled-pool-regression-review-1b8530fb.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-selected-package-pool-regression-review/on/timeout-960/traces/hires-sampled-pool-regression-review-1b8530fb.md)
    - current recommendation: keep the family deferred as `defer-runtime-pool-semantics`, and keep the active runtime shape on `keep-flat-runtime-binding`
    - current rationale: the current live stream still classifies as `rotating-stream-edge-dwell`, the ordered map remains `33/34` with one right-edge unresolved tail slot, the long dwell still aligns with that unresolved edge slot instead of a slot-aligned selector stream, and the new regression review keeps the older flat / dual / ordered-only `960` comparisons attached to the live bundle instead of forcing that deferment to depend on scattered March 30 artifacts.
  - the same seam now also has live pool-stream diagnostics instead of only inferred shape analysis:
    - proof bundle: [`20260407-title-timeout-selected-package-pool-stream-diagnostics-v3/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-title-timeout-selected-package-pool-stream-diagnostics-v3/validation-summary.md)
    - stream register: [`20260407-title-timeout-selected-package-pool-stream-diagnostics-v3/on/timeout-960/traces/hires-runtime-seam-register.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-title-timeout-selected-package-pool-stream-diagnostics-v3/on/timeout-960/traces/hires-runtime-seam-register.md)
    - current outcome: the active mapped family rotates across `33` unique observed `texel1-peer` selectors with `32` transitions and no repeats inside the mapped set
    - practical consequence: the unresolved dwell is still outside the mapped `33` selectors, so the new evidence sharpens the deferment instead of reopening selector-alias promotion; keep `1b8530fb` on `keep-flat-runtime-binding`
  - the smallest bounded tail-slot follow-up is now also classified as review-only negative data:
    - review policy: [`tools/hires_surface_transport_review_policy.json`](/home/auro/code/parallel-n64/tools/hires_surface_transport_review_policy.json)
    - reviewed surface package: [`20260407-1b85-tail-slot-reviewed-surface-package/surface-package.json`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260407-1b85-tail-slot-reviewed-surface-package/surface-package.json)
    - candidate package: [`20260407-selected-plus-timeout-960-v1-1b85-tail-slot-review/package.phrb`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260407-selected-plus-timeout-960-v1-1b85-tail-slot-review/package.phrb)
    - builder reproduction: [`20260407-selected-plus-timeout-960-v1-1b85-tail-slot-review-builder/package.phrb`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260407-selected-plus-timeout-960-v1-1b85-tail-slot-review-builder/package.phrb)
    - selected-package authority proof: [`20260407-selected-package-authorities-1b85-tail-slot-review/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-selected-package-authorities-1b85-tail-slot-review/validation-summary.md)
    - selected-package timeout proof: [`20260407-title-timeout-selected-package-1b85-tail-slot-review/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-title-timeout-selected-package-1b85-tail-slot-review/validation-summary.md)
    - current outcome: title screen, file select, `kmr_03 ENTRY_5`, and the `960` timeout image all stay byte-identical to the active selected package, and `1b8530fb` gains `1056` additional exact hits through `sampled-sparse-ordered-surface`
    - current limitation: the gameplay image does not improve, `exact_unresolved_miss_count` stays `90877`, the live pool-review artifact disappears, and the provider shape explodes from `1` sampled-duplicate key / entry to `67` / `67` with `10` duplicate families in the seam register
    - practical consequence: filling the unresolved tail slot alone is not a promotable runtime step; it just trades one deferred pool-conflict seam for a larger duplicate-selector seam, so `1b8530fb` remains on `keep-flat-runtime-binding`
- The exact sampled runtime path no longer re-enters the provider through checksum-shaped decode after a native sampled lookup succeeds.
  - `rdp_renderer.cpp` now resolves exact sampled descriptors through a direct sampled-entry decode path, using the same resident-image cache key but bypassing checksum-index re-selection.
  - latest proof bundle: [`20260406-180724-title-timeout-selected-package-direct-sampled-decode/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-180724-title-timeout-selected-package-direct-sampled-decode/validation-summary.md)
  - current outcome: the rendered `960` frame stays byte-identical to the prior bundle and the `Pool Families` recommendation for `1b8530fb` is unchanged.
  - note: small exact-unresolved deltas have not stayed stable across equivalent selected-package reruns. The same `960` frame and semantic state have now reproduced with totals of `90877`, `90885`, and one earlier `90869`, all on the same `phrb-only` lane. Treat those low-count triangle shifts as non-gating telemetry until a change survives repeated reruns with a real behavioral delta.
- Runtime summary logs can now report how hybrid the loaded provider still is.
  - `log_hires_summary()` now includes total entries, native-sampled vs compat entry counts, sampled-family counts, compat-low32 family counts, and per-source entry counts (`.phrb`, `.hts`, `.htc`).
  - practical consequence: the next runtime-source narrowing step can be measured directly instead of inferred.
- Runtime source policy now has an explicit mixed-cache bridge mode.
  - `PARALLEL_RDP_HIRES_RUNTIME_SOURCE_MODE=auto` now prefers `.phrb` inputs automatically when a cache directory contains both native and legacy formats, but still falls back to legacy-only when no `.phrb` exists.
  - current baseline: empty or unset source-policy env now also defaults to `auto`, so the runtime default matches the repo's `PHRB`-first direction while still preserving the same legacy fallback when no usable `.phrb` content exists.
  - explicit opt-out: `PARALLEL_RDP_HIRES_RUNTIME_SOURCE_MODE=all` still remains available for lanes that intentionally want mixed-source loading.
  - hi-res evidence summaries now carry both `source_policy` (requested loader policy) and `source_mode` (actual loaded source mix), so default-path bundles can prove `auto` policy without losing the stronger `phrb-only` provider-composition assertion.
- Selected-package validation summaries now surface that provider composition directly.
  - fresh proof bundle: [`20260406-194500-title-timeout-selected-package-provider-summary/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-194500-title-timeout-selected-package-provider-summary/validation-summary.md)
  - current outcome on the active `960` package probe: `source_mode=phrb-only`, `entries=195`, `native_sampled=195`, `compat=0`, `sampled_families=10`, `sources(phrb=195, hts=0, htc=0)`.
  - selected-package timeout validation now enforces that contract directly instead of only reporting it: explicit selected-package probes fail if `source_mode` drifts away from `phrb-only` or if native sampled / `PHRB` entry counts fall to zero.
- The selected-package timeout lane now also reports which descriptor path the live runtime actually used.
  - fresh proof bundle: [`20260407-selected-package-timeout-current-contract/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-selected-package-timeout-current-contract/validation-summary.md)
  - current outcome on the active `960` package probe: `descriptor_paths(sampled=66 native_checksum=0 generic=0 compat=0)`.
  - practical consequence: on the current explicit `phrb-only` timeout lane, successful live descriptor resolution is entirely on the structured sampled path; native-checksum and generic/compat fallback remain implemented, but they are not carrying the active selected-package `960` proof.
- The selected-package timeout lane now also proves that the current `194/195` sampled-index split is an explained package-level duplicate identity, not an unexplained runtime omission.
  - proof bundle: [`20260407-selected-package-duplicate-review/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-selected-package-duplicate-review/validation-summary.md)
  - current outcome: the live runtime summary now reports `entries=195`, `native_sampled=195`, `sampled_index=194`, `sampled_dupe_keys=1`, and `sampled_dupe_entries=1` on the explicit `phrb-only` lane.
  - current interpretation: the missing sampled-index slot is now accounted for by one exact sampled-key collision inside the selected package rather than by a provider load/drop bug.
  - the active duplicate probe now records that seam directly in bundle evidence: one duplicate bucket at `sampled_low32=7701ac09`, `palette_crc=00000000`, `fs=768`, `selector=0000000071c71cdd`, with active policy `surface-7701ac09` and active replacement id `legacy-844144ad-00000000-fs0-1600x16`.
  - the new duplicate review now also proves that active selector collision is pixel-identical inside the selected package: the live `0000000071c71cdd` pair shares the same pixel hash, and the broader package duplicate-pixel group already spans `legacy-2cf87740-00000000-fs0-1600x16`, `legacy-844144ad-00000000-fs0-1600x16`, and `legacy-e0dc03d0-00000000-fs0-1600x16`.
  - the timeout lane now also emits a seam register that keeps this duplicate seam next to the candidate-free families, candidate-backed family, and pool-conflict family in one artifact instead of scattering them across separate notes.
  - with the alternate-source review attached, that same register now also proves the triangle trio has `13` source-backed review candidates waiting without conflating them with runtime-ready behavior.
  - with the new cross-scene review attached, that same register now records `91887078` / `e0d4d0dc` as shared with title and file plus absent on the steady-state selected-package `kmr_03 ENTRY_5` authority, while `6af0d9ca` is shared with title and absent on both file and world, so the current source-backed seam stays blocked on tighter discriminator or scene-bounded activation work instead of drifting back into “maybe safe” status.
  - with the new joined activation review attached, that same register now records `candidate_free_review_bounded_probe_count=0`, so the candidate-free triangle lane is explicitly source-backed-but-blocked rather than a silent promotion backlog.
  - practical consequence: the runtime now applies a bounded deterministic duplicate winner rule keyed by native `replacement_id`, so the active selected-package lane no longer depends on file load order, and the next follow-up for `7701ac09` is better framed as offline dedupe / alias policy instead of a broader runtime merge policy.
- That `7701ac09` offline dedupe follow-up is now proven as a review-only package-shaping slice.
  - candidate package: [`20260407-selected-plus-timeout-960-v1-dedupe-7701ac09/package.phrb`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260407-selected-plus-timeout-960-v1-dedupe-7701ac09/package.phrb)
  - selected-package authority proof: [`20260407-selected-package-authorities-7701ac09-dedupe-review/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-selected-package-authorities-7701ac09-dedupe-review/validation-summary.md)
  - selected-package timeout proof: [`20260407-title-timeout-selected-package-7701ac09-dedupe-review/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-title-timeout-selected-package-7701ac09-dedupe-review/validation-summary.md)
  - runtime-conformance proof: [`20260407-title-timeout-selected-package-7701ac09-dedupe-conformance/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-title-timeout-selected-package-7701ac09-dedupe-conformance/validation-summary.md)
  - builder reproduction: [`20260407-selected-plus-timeout-960-v1-dedupe-7701ac09-builder/package.phrb`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260407-selected-plus-timeout-960-v1-dedupe-7701ac09-builder/package.phrb) now reproduces the same binary package byte-for-byte from the tracked `bindings.json` plus the duplicate-review JSON via [`tools/hires_pack_build_selected_package.py`](/home/auro/code/parallel-n64/tools/hires_pack_build_selected_package.py) `--duplicate-review`
  - current outcome: removing the non-winning `0000000071c71cdd` selector duplicate leaves title screen, file select, `kmr_03 ENTRY_5`, and the `960` timeout image byte-identical to the active selected package while dropping runtime sampled-duplicate accounting from `1` bucket / `1` extra entry to `0` / `0`
  - practical consequence: the next bounded step for exact pixel-identical duplicate seams can stay offline and review-driven; it no longer needs new runtime merge behavior to prove value
- The broader `7701ac09` asset-alias follow-up is now also proven as a review-only package-shaping slice.
  - alias-group review: [`20260407-selected-plus-timeout-960-v1-dedupe-7701ac09-alias-group-review/review.md`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260407-selected-plus-timeout-960-v1-dedupe-7701ac09-alias-group-review/review.md)
  - candidate package: [`20260407-selected-plus-timeout-960-v1-dedupe-7701ac09-asset-alias-review/package.phrb`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260407-selected-plus-timeout-960-v1-dedupe-7701ac09-asset-alias-review/package.phrb)
  - builder reproduction: [`20260407-selected-plus-timeout-960-v1-dedupe-7701ac09-asset-alias-review-builder/package.phrb`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260407-selected-plus-timeout-960-v1-dedupe-7701ac09-asset-alias-review-builder/package.phrb) now reproduces the same binary package byte-for-byte from the tracked `bindings.json` plus the duplicate-review JSON and alias-group review JSON via [`tools/hires_pack_build_selected_package.py`](/home/auro/code/parallel-n64/tools/hires_pack_build_selected_package.py) `--duplicate-review --alias-group-review`
  - selected-package authority proof: [`20260407-selected-package-authorities-7701ac09-asset-alias-review/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-selected-package-authorities-7701ac09-asset-alias-review/validation-summary.md)
  - selected-package timeout proof: [`20260407-title-timeout-selected-package-7701ac09-asset-alias-review/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-title-timeout-selected-package-7701ac09-asset-alias-review/validation-summary.md)
  - current outcome: all four selector rows in the broader identical-pixel group now reuse the canonical `legacy-844144ad-00000000-fs0-1600x16` asset, the materialized package collapses that group onto one PNG path, title screen / file select / `kmr_03 ENTRY_5` / the `960` timeout image all stay byte-identical, and runtime sampled-duplicate accounting stays at `0` / `0`
  - practical consequence: broader identical-pixel groups can stay offline and review-driven as asset-level alias candidates without widening runtime merge or pool behavior; promotion is still deferred, but the shaping path is now proven and reproducible
- The current proven `7701ac09` review-only shaping inputs now travel as one tracked build input instead of two ad hoc flags.
  - review profile: [`tools/hires_selected_package_review_profile.json`](/home/auro/code/parallel-n64/tools/hires_selected_package_review_profile.json)
  - builder support: [`tools/hires_pack_build_selected_package.py`](/home/auro/code/parallel-n64/tools/hires_pack_build_selected_package.py) now accepts `--review-profile`
  - current outcome: the tracked review profile reproduces the explicit duplicate-review plus alias-group-review package byte-for-byte
  - practical consequence: the selected-package build path can now absorb those proven review-only inputs coherently without pretending they are already default behavior
- The explicit selected-package authority lane is now proven across Paper Mario menu and non-menu authorities as a complementary `PHRB` proof alongside the promoted default full-cache authority lane.
  - proof bundle: [`20260406-201200-selected-package-authorities/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260406-201200-selected-package-authorities/validation-summary.md)
  - current outcome: title screen, file select, and `kmr_03 ENTRY_5` all pass semantically under an explicit selected `PHRB` package with `source_mode=phrb-only`, `entries=195`, and `native_sampled=195`.
  - runtime-conformance coverage now exists for that lane through `emu.conformance.paper_mario_selected_package_authorities`, gated behind `EMU_ENABLE_RUNTIME_CONFORMANCE=1`.
- The deeper selected-package timeout lane is now also in runtime conformance instead of being manual-only.
  - latest proof bundle: [`20260407-selected-package-timeout-current-contract/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-selected-package-timeout-current-contract/validation-summary.md)
  - current outcome: the `960` probe still lands on `state_init_world` / `state_step_world`, `kmr_03`, `entry 5`, with `source_mode=phrb-only`, `on_hash=4bd3929dabff3ffb1b7e03a9c10d8ce50e9b6d0f067825d3a788c48a41b6fc62`, `matches_off=true`, `exact_hit_count=66`, `exact_unresolved_miss_count=121647`, and `descriptor_paths(sampled=66 native_checksum=0 generic=0 compat=0)`.
  - practical consequence: the current timeout conformance lane is now a native-runtime contract proof, not a visible-difference proof. The lane shows live sampled descriptor resolution on a `phrb-only` package even though the current frame is pixel-identical to `off`.
  - the timeout bundle summary now records the live pool-review status and replacement id directly. If the current bundle has no reconstructable `1b8530fb` draw-sequence rows, that review now emits `review_status=deferred-no-live-draw-sequence` and explicitly falls back to the historical pool-regression review instead of aborting the timeout proof.
  - that same summary now also records the bounded duplicate review for `7701ac09`, so the live bundle keeps the stable runtime winner rule and the offline-dedupe follow-up attached to the same current proof.
  - that same summary now also records the bounded flat-vs-surface regression verdict for `1b8530fb`, so the live bundle carries the historical reason for keeping flat runtime binding instead of only the current pool-shape result.
  - the paired seam register now keeps the whole deferred runtime set explicit in one place: candidate-free `91887078` / `6af0d9ca` / `e0d4d0dc`, candidate-backed `28916d63`, pool-conflict `1b8530fb`, and duplicate family `7701ac09`.
  - that same conformance lane now fails closed if the live `1b8530fb` pool review loses its `runtime_sample_replacement_id` or if the live `7701ac09` duplicate seam loses its active `replacement_id`.
  - the same runtime-conformance lane now also emits an alternate-source review, proving those candidate-free-under-legacy families have source-backed review candidates before any runtime promotion is attempted.
  - runtime-conformance coverage now exists for that lane through `emu.conformance.paper_mario_selected_package_timeout_validation`, gated behind `EMU_ENABLE_RUNTIME_CONFORMANCE=1`.
- Fresh authority reruns make the current runtime split explicit:
  - the repo-default title-screen, file-select, and `kmr_03 ENTRY_5` authority scenarios now prefer the current enriched full-cache `PHRB` artifact at [`artifacts/hts2phrb-review/20260408-pm64-all-families-authority-context-abs-summary/package.phrb`](/home/auro/code/parallel-n64/artifacts/hts2phrb-review/20260408-pm64-all-families-authority-context-abs-summary/package.phrb), then fall back through the older enriched artifact, the zero-config full-cache artifact, and finally the legacy `.hts` cache only if no `PHRB` is present
  - fresh default-path proof: title screen, file select, and `kmr_03 ENTRY_5` now all pass with no cache override, each reporting `source_mode=phrb-only`, `entry_count=12754`, `native_sampled_entry_count=503`, and `descriptor_path_class=sampled-only`; the promoted screenshot hashes are `0e854083b48ccf48e0a372e39ca439c17f0e66523423fb2c3b68b94181c72ad5`, `43bd91dab1dfa4001365caee5ba03bc4ae1999fd012f5e943093615b4c858ca9`, and `212ffb9329b8d78e608874e524534ca54505a26204abe78524ef8fca97a1b638`
  - practical consequence: the active authority lane has now intentionally moved onto the enriched full-cache `PHRB` runtime path; the remaining default-path work is broader promotion beyond this Paper Mario proof set, not whether the authority lane itself should still be treated as legacy-default
- Second-game validation has not started.

## Deferred Work Register

Any work item skipped to keep the current slice bounded must stay listed here until it is either completed, explicitly rejected, or moved behind a later gate with evidence.

| Deferred item | Why deferred now | Reactivate when |
|---|---|---|
| Widen structured sampled-object lookup beyond the current exact seam | The runtime now preserves native identity, but broader lookup widening should follow classification rather than outrun it. | After the Phase B2 gate and direct tests show which structured fields must become primary. |
| Make `.phrb` the only production runtime source and treat `.hts` / `.htc` as import-only | The conversion front door and default-path promotion are not ready yet, so runtime source narrowing would outrun the user path. | After Paper Mario breadth passes and the front door is ready to carry the common case. |
| Add `tlut_type` as a first-class runtime identity field | The current palette work has not finished classifying which palette facts are truly canonical. | When the palette classification gate shows that `tlut_type` is required for native identity, not just legacy parity. |
| Preserve ordered-surface metadata as a runtime-native concept instead of selector hashes | The first seam slices focused on exact sampled identity and provider preservation, not selector-bearing runtime promotion. | After the structured runtime key space is stable enough to carry richer ordered-surface state without guesswork. |
| Promote review-only alternate-source triangle candidates into the active selected package/runtime lane | The timeout lane now proves the leading candidate-free triangle families have source-backed review candidates, but the first `91887078` zero-selector singleton still changes selected-package title/file authorities even while the `960` gameplay frame stays byte-identical, and the cross-scene review now shows `91887078`, `6af0d9ca`, and `e0d4d0dc` already share the same absent runtime signature across timeout, title, and file select before promotion. | After a tighter source-backed selector model or scene-bounded review path shows a bounded choice improves the target seam without regressing the current authorities, and the cross-scene review no longer reports `no-runtime-discriminator-observed` for the promoted family. |
| Implement runtime pool semantics for `present-pool-selector-conflict` families like `1b8530fb` | The provider can now describe native pool conflicts directly, but the current evidence still says fixed-slot replay is the wrong behavior for the rotating-stream-edge-dwell case. | After a pool-preserving selector model is defined and direct runtime evidence says it improves the seam without regressing strict authorities. |
| Promote review-only offline duplicate and asset-alias shaping for exact pixel-identical families like `7701ac09` into the canonical selected-package build | Both the selector-local dedupe candidate and the broader asset-alias candidate are now proven stable on selected-package authorities and the `960` timeout lane, and a tracked review profile now bundles those inputs reproducibly, but default build promotion is still intentionally deferred. | After repeated review bundles keep the duplicate seam eliminated without new regressions, and the default selected-package build can absorb those review decisions without obscuring which steps were review-only. |
| Enable first-load `.hts` to cached `.phrb` auto-conversion | Auto-conversion is a user convenience, not a sequencing shortcut, and enabling it earlier would blur runtime-contract readiness. | Only during default-path promotion, with direct auto-conversion tests and cache-behavior coverage. |
| Promote native-`PHRB` provider-composition minima beyond the three active Paper Mario authority fixtures | The active title/file-select/`kmr_03` authority lane now prefers the enriched full-cache `PHRB` artifact by default and proves sampled-only descriptor traffic. | After the broader default-path promotion phase starts outside the current Paper Mario authority set. |
| Start second-game validation | Cross-game claims are not useful until the Paper Mario menu and non-menu authority set is stable and classification-backed. | After the Paper Mario breadth gate is green and the runtime contract is stable enough to test without new core rules. |
| Treat representative-pack converter performance and cache behavior as a promotion gate | Correctness and bounded ambiguity came first; operational expectations are only meaningful once the skeleton front door is stable. | Before default-path promotion and before auto-conversion is enabled. |

## Core Decision

The project should continue on the current imported-format and sampled-object path, but the next major work should be:

1. Make the native package contract authoritative at runtime.
2. Reduce compatibility logic to explicit fallback mode.
3. Broaden validation enough to justify the contract first within Paper Mario and then across at least one second game.
4. Investigate the highest-value general legacy-pack miss classes without letting them redefine the core runtime key model.
5. Collapse the current import experience into a generic user-facing conversion entrypoint.

The project should not spend the next cycle on:

- adding more selector heuristics
- widening proxy or bridge machinery as a primary path
- reviving frontend-exposed runtime lookup modes
- treating `.hts` and `.htc` as long-term runtime formats

## Execution Order

The intended order of work is:

1. Stabilize plan prerequisites and validation trust.
2. Land the smallest useful runtime/provider seam slice.
3. Run palette parity, `LoadBlock`, and converter-skeleton work in parallel.
4. Classify those investigations before promoting either seam.
5. Widen structured runtime lookup only where the classification and evidence say it is needed.
6. Promote the generic `hts2phrb` front door on top of the improved internals.
7. Prove the path across Paper Mario menu and non-menu authority scenes.
8. Make `PHRB` the default runtime path only after the Paper Mario gate is met.
9. Prove the same contract on a second game with a different runtime class profile.

The key sequencing rule is:

- converter convenience does not get to outrun the runtime contract
- compatibility investigations do not get to pre-decide the native identity model
- validation gates do not get to remain screenshot-only

## Immediate Priorities

If work starts now, the priority stack is:

1. Make the active validation set trustworthy by resolving authority metadata drift, activating one non-menu Paper Mario authority fixture, and making semantic hi-res evidence participate in pass/fail.
2. Fix the first provider/loader seam so `PHRB` is not reduced back to compatibility keys at load time.
3. Add direct provider/package tests for that seam slice.
4. Run the two highest-value investigations:
   - CI palette parity
   - `LoadBlock` sampled-shape reinterpretation
5. In parallel, build the earliest safe `hts2phrb` skeleton over the improved internals.
6. Capture classification results before allowing either seam into the canonical contract.

## Phase A/A1 Execution Checklist

This checklist is the current execution surface when work is intentionally narrowed to the runtime contract and converter path.

- [x] Preserve structured `PHRB` identity at load time instead of discarding it.
- [x] Separate native sampled records from compat low32 families in provider internals.
- [x] Add direct provider/package coverage for the preserved-identity seam.
- [x] Make runtime source policy explicit (`all`, `auto`, `phrb-only`, `legacy-only`) and thread it through the runtime entrypoint without changing current defaults implicitly.
  - current product-path state: libretro now exposes `parallel-n64-parallel-rdp-hirestex-source-mode`, defaulting to `auto`; scenario env overrides still win when a lane intentionally forces `phrb-only`.
- [x] Narrow explicit selected-package runtime lanes to `phrb-only` by policy instead of relying on artifact convention alone.
- [ ] Widen structured sampled-object lookup beyond the current exact seam only where direct tests exist.
- [ ] Replace checksum-shaped primary lookup with structured sampled-object identity across the remaining runtime path.
- [ ] Make `.phrb` the only production runtime source.
- [ ] Move `.hts` / `.htc` to import-only status for the default runtime path.
- [ ] Preserve ordered-surface metadata as a runtime-native concept instead of selector hashes.
- [x] Ship the first `hts2phrb` skeleton over the existing pipeline.
- [ ] Strengthen `hts2phrb` until it is the clear common-case front door rather than a thin orchestration wrapper.
- [ ] Add at least one non-Paper-Mario zero-config converter proof.
- [x] Add representative-pack converter operational gates for timing, cache behavior, and output sizing.
- [ ] Keep first-load `.hts` to cached `.phrb` auto-conversion disabled until default-path promotion, then add direct tests for it.

### Delivery Rule

- Phase A should land in measurable slices, not as a single opaque rewrite.
- Each slice should preserve or improve active fixture results, add or strengthen direct tests, and keep the next step obvious.
- Tests should be written alongside each slice and investigation, not deferred to the end of the phase.
- Good early slices include:
  - preserve structured `PHRB` identity at load time instead of discarding it
  - separate native records from compatibility aliases in provider internals
  - add provider/package tests before widening runtime lookup coverage
  - widen primary structured lookup only after the prior slices are stable
- The first useful Phase A slice is intentionally smaller than a full structured-key rollout.
- Converter work may start once that first seam slice lands, but it must remain downstream of validation trust and the initial provider/loader fix.

## Phase A: Native Runtime Contract

### Goal

- Make `PHRB` the real runtime format instead of a compatibility wrapper around legacy keys.

### First Slice

Before any broad structured-key rollout, land the smallest useful seam fix:

1. Preserve structured `PHRB` identity at load time instead of discarding it.
2. Separate native records from compatibility aliases internally.
3. Add direct provider/package tests for that seam.

Concretely, the first seam slice should be closer to a targeted loader/provider preservation fix than a lookup redesign:

- keep the current lookup behavior stable
- extend in-memory provider records so structured `PHRB` identity is preserved after load
- avoid changing primary indices until the preserved fields are test-covered and classification work has progressed

This is intentionally a low-risk enabling slice. Its job is to stop the runtime from throwing away native identity before broader lookup changes are considered.

This slice is the minimum runtime-contract change required before converter work or compatibility investigations are allowed to shape default behavior.

### Required Changes

1. Make `.phrb` the only production runtime source in [`texture_replacement.cpp`](/home/auro/code/parallel-n64/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/texture_replacement.cpp).
2. Treat `.hts` and `.htc` as import-only inputs in tooling such as [`hires_pack_migrate.py`](/home/auro/code/parallel-n64/tools/hires_pack_migrate.py) and [`hires_pack_materialize_package.py`](/home/auro/code/parallel-n64/tools/hires_pack_materialize_package.py).
3. Replace provider lookup keyed by `checksum64 + formatsize + selector` with a structured sampled-object key.
4. Use the identity already emitted by [`hires_pack_emit_binary_package.py`](/home/auro/code/parallel-n64/tools/hires_pack_emit_binary_package.py), including:
   - `fmt`
   - `siz`
   - `tile`
   - `tmem`
   - `line`
   - `logical size`
   - palette identity
5. Add `tlut_type` as a first-class runtime identity field.
6. Preserve ordered-surface metadata at runtime instead of compiling it down to opaque selector hashes.

### Exit Criteria

- The provider can resolve native records without reconstructing legacy-style `Entry` keys.
- `PHRB` loading uses structured sampled-object identity as the primary runtime key.
- Compatibility aliases are explicit secondary records, not the baseline key space.
- The runtime contract no longer depends on converter-side convenience decisions to express its canonical identity model.
- The runtime contract reached that state through measurable slices rather than an untestable big-bang rewrite.
- The first seam slice preserved structured `PHRB` identity in memory before broader lookup redesign was attempted.

## Phase A1: Generic Conversion Front Door

### Goal

- Replace the current many-step legacy import experience with one generic conversion command while keeping the richer internal model.

### Required Changes

1. Add one user-facing conversion entrypoint such as `hts2phrb`.
2. Implement that entrypoint as an orchestration layer over existing import/build code where possible instead of replacing the internal model with a flat legacy-key emitter.
3. Support `.hts` and `.htc` as generic inputs and `.phrb` as the output artifact.
4. Ensure conversion succeeds without per-game manual intervention for the common case.
5. Emit structured `PHRB` records with all identity fields that are available at conversion time, and leave currently unknowable fields explicit rather than inventing them.
6. Emit warnings and diagnostics for ambiguous cases instead of silently broadening runtime behavior.
7. Keep policy-backed or enriched import stages available behind the same front door when the generic case is insufficient.
8. Support future optional enrichment inputs behind the same entrypoint, for example ROM-backed or policy-assisted augmentation, without changing the basic zero-config conversion path.

### Non-Goals

- Do not require users to understand the current multi-tool pipeline.
- Do not collapse `PHRB` into a container for mostly legacy-shaped runtime keys just to make conversion simpler.
- Do not turn auto-conversion convenience into a substitute for fixing the provider/runtime identity contract.
- Do not pretend currently unknown sampled-object fields are known just to make the first converter output look complete.
- Do not introduce first-load `.hts` to `.phrb` auto-conversion before the default-promotion stage; early convenience must not reshape sequencing or runtime semantics.

### Exit Criteria

- A user can run one command to convert a legacy pack into a runtime package.
- The generated package can carry structured native identity and explicit compatibility records, including partially populated structured records that are ready for later enrichment.
- The conversion entrypoint is generic even if the internals still use multiple stages.
- The front door may ship before full structured lookup is the default runtime path, but it must remain a wrapper over the richer model rather than freezing a legacy-shaped contract.
- The earliest shippable form of the front door is a skeleton:
  - one command
  - structured records with known fields
  - ambiguity diagnostics
  - no unclassified compatibility behavior baked into default output
- The converter has explicit smoke coverage:
  - Paper Mario pack converts end-to-end and reproduces current expected authority behavior
  - at least one non-Paper-Mario pack converts in zero-config mode without requiring new core runtime rules
- The converter has explicit round-trip coverage:
  - legacy entry to `PHRB` record to load path preserves expected key fields and classification-backed behavior
- The converter has explicit operational coverage:
  - conversion time and cache behavior are measured for representative pack sizes before default-path promotion
  - the front door remains usable for typical packs, not just technically correct
- Partial structured records are allowed:
  - converted records may carry only the fields knowable at conversion time
  - partial records do not block the runtime from preferring richer native records when those records exist

## Phase B: Scoped Compatibility Mode

### Goal

- Keep compatibility tools, but fence them off from the core product path.

### Required Changes

1. Keep CI low32 fallback behind explicit compatibility mode only.
2. Keep proxy bindings and transport bridges as transitional import artifacts, not architectural defaults.
3. Document the sampled-object exact path as intentionally scoped while runtime coverage is incomplete.
4. Do not widen fallback behavior until the native key path is stable and tested.
5. Investigate two bounded runtime compatibility seams as explicit research tasks:
   - CI palette parity with GlideN64 or Rice-era lookup expectations
   - `LoadBlock` upload-shape versus sampled-shape reinterpretation on miss
6. Allow those compatibility investigations to ship only as explicit compat behavior unless they can be expressed cleanly without changing the native runtime identity model.

### Exit Criteria

- Compatibility behavior can be disabled cleanly without changing native package semantics.
- Native package success on active fixtures does not depend on implicit compatibility broadening.
- Palette-parity or `LoadBlock` compatibility work, if retained, is documented as secondary runtime behavior rather than the canonical identity path.

## Phase B1: Legacy Compatibility Investigations

### Goal

- Evaluate the strongest general-case ideas from legacy-pack parity work without replacing the native-first architecture.

### Investigation Discipline

- Investigation work must stay bounded and decision-oriented.
- If an investigation yields a partial improvement, do not spiral into endless case-by-case debugging before the classification gate.
- The correct next step for a partial result is:
  1. record the measurable improvement
  2. classify the remaining misses by cause
  3. decide whether the seam looks native, compat, or dead-end
  4. move the sequence forward
- Investigation work is successful when it produces either:
  - a clear improvement with a defensible classification
  - or a clear rejection with enough evidence to stop investing

### Investigation 1: CI Palette Parity

- Compare ParaLLEl CI palette CRC inputs against GlideN64-style lookup expectations for the same runtime event.
- Determine whether current `tlut_shadow` population or bank-selection semantics diverge in a way that explains active legacy-pack misses.
- If parity fixes improve legacy `.hts` behavior, keep that as explicit compatibility behavior or import guidance unless it cleanly matches the structured native identity model.
- Working assumption:
  - palette parity is more likely to reveal a native identity bug than a mere compatibility nicety
  - it still must pass the classification gate before being declared canonical
- Priority:
  - this is the first identity investigation to run because it is the strongest candidate for a genuine native-identity correction rather than a legacy convenience rule
- Partial-result rule:
  - if the fix materially improves hit rates but does not close the seam completely, record the residual miss classes and proceed to classification instead of expanding into open-ended per-family debugging

### Investigation 2: `LoadBlock` Sampled-Shape Retry

- Measure the real miss class caused by upload-shape versus sampled-shape disagreement.
- Prototype a miss-only retry path for `LoadBlock`-backed cases.
- Keep any such retry path fenced as compatibility behavior unless the same concept can be represented directly in the native package/runtime contract.
- Working assumption:
  - a miss-only retry is compatibility behavior until proven otherwise
  - `LoadBlock` should not be promoted into canonical identity merely because it improves legacy-pack hit rate
- Partial-result rule:
  - if the retry improves known miss families but raises unresolved false-positive risk, stop at classification and second-game validation rather than widening the retry path by instinct

### Investigation Exit Criteria

- The project can say clearly whether palette parity and `LoadBlock` reinterpretation are:
  - required native identity facts
  - bounded compatibility helpers
  - or dead ends that should not shape the architecture
- If they are retained, the generic converter can incorporate them automatically without introducing game-specific policy as the normal path.

## Phase B2: Identity Classification Gate

### Goal

- Force an explicit architectural decision after the two highest-value compatibility investigations complete.

### Required Decision

After CI palette parity and `LoadBlock` sampled-shape work are validated on the active Paper Mario fixtures, classify each result as one of:

1. Native identity fact
2. Bounded compatibility helper
3. Dead end

### Decision Rules

- Classify it as a native identity fact only if it reflects the canonical texture identity ParaLLEl should honor across games, not just a legacy pack lookup convention.
- Classify it as a bounded compatibility helper if it materially improves legacy-pack behavior but should remain explicit secondary behavior.
- Classify it as a dead end if it does not generalize cleanly, introduces false positives, or does not materially improve results.

### Exit Criteria

- Both investigations have a written classification outcome.
- The converter and runtime plans reflect those classifications explicitly.
- No compatibility seam is promoted into canonical runtime identity without passing this gate.

### Current Classification Outcomes

- CI palette parity currently classifies as a bounded compatibility or import diagnostic, not a native identity fact.
  - raw TLUT entry-count variants, sparse used-index hashing, and emulated loaded-TLUT views did not close the remaining misses
  - the remaining seam looks more like inherited legacy-pack identity mismatch than a small runtime CRC-formula bug
  - practical consequence: do not keep widening palette-formula work in the default runtime path; keep it as explicit compat or import-side guidance unless new evidence overturns this
- `LoadBlock` sampled-shape retry currently classifies as a dead end for simple contiguous runtime retry.
  - the dominant file-select `64x1 fs514` family and title `2048x1 fs515` family both classify as `no-simple-loadblock-retry`
  - neither produced exact-surface or area-preserving reinterpretation hits in the active pack under the current bounded analyzer
  - practical consequence: do not add a permissive simple `LoadBlock` retry path to the default runtime contract

## Phase C: Validation Breadth

### Goal

- Stop making format decisions from a menu-heavy and single-game-heavy evidence base.

### Required Changes

1. Promote one deterministic non-menu Paper Mario scene to an authoritative fixture.
2. Keep title and file-select strict fixtures as baseline gates.
3. Add class-based assertions on top of image hashes using the existing evidence output:
   - one texrect-dominated case
   - one block-dominated case
   - one CI or TLUT-sensitive case
4. Make semantic hi-res evidence pass or fail, not just explanatory output. At minimum, require assertions over expected exact, compat, conflict, unresolved, or class-presence signals from `hires-evidence.json`.
5. Resolve authority-graph and fixture metadata drift where expected capture hashes or lineage data disagree across planning files, fixtures, and runtime env files.
6. Validate the generic conversion path across the Paper Mario title, file-select, and deeper non-menu fixture set before widening scope.
7. Record at least one intentionally rejected fallback or unresolved family as negative data before declaring the architecture ready.
8. After the first deeper Paper Mario authority is stable, add one hi-res-specific second-game probe with a materially different runtime class profile, not just another texrect or UI-heavy scene.
9. Keep game-specific bridge or alias rules in import policy instead of allowing them to reshape the core runtime identity model.

### Exit Criteria

- At least one deeper non-menu state is part of the authority set.
- Architectural changes are evaluated against runtime classes, not only screenshot equality.
- Authority metadata and expected captures are internally consistent across the active Paper Mario authority set.
- The generic conversion path works across both menu and non-menu Paper Mario authority scenes before cross-game claims are made.
- Semantic hi-res evidence is part of the gate, not just a sidecar artifact.
- The native runtime contract has at least one non-Paper-Mario hi-res validation target before being treated as generally shaped correctly.
- The second-game validation exercises a runtime class not already dominant in the active Paper Mario authority scenes.
- The generic conversion entrypoint has been exercised on at least one non-Paper-Mario pack without requiring new core runtime key rules.
- At least one unresolved or intentionally rejected fallback case remains explicitly documented as negative data.

## Parallelism Rules

The following work can proceed in parallel after validation trust and the first runtime seam slice are in place:

- CI palette parity investigation
- `LoadBlock` retry investigation
- early `hts2phrb` skeleton work
- direct test authoring
- second-game fixture preparation once the Paper Mario authority set is stable

The following work must remain serial:

- validation trust before interpreting hit-rate movement
- classification before promotion
- targeted structured-key widening before declaring runtime-contract correctness
- Paper Mario full gate before default-path promotion
- second-game gate before claiming generality

## Promotion Rule

No new behavior should be promoted to the default runtime path unless all of the following are true:

1. It improves active authority fixtures.
2. It does not break semantic hi-res evidence expectations.
3. It survives the classification gate.
4. It does not require game-specific runtime key rules.
5. It still fits the native-first runtime contract.
6. If it involves auto-conversion convenience, that convenience remains downstream of the runtime contract and does not alter native package semantics.

## Phase D: Restore Direct Tests

### Goal

- Recover the most valuable test discipline from the failed attempt without reviving its architecture.

### Required Changes

1. Add dedicated tests for:
   - `PHRB` parsing and loading
   - provider lookup behavior
   - selector-bearing native package records
   - compatibility alias fencing
   - converter smoke behavior for zero-config `hts2phrb`
   - converter round-trip preservation of emitted identity fields
   - auto-conversion from `.hts` input to cached `.phrb` output once default promotion work begins
2. Reuse ideas from the failed branch's replacement-provider tests, but not its runtime mode matrix.
3. Add focused tool tests for package emission and record identity preservation.

### Exit Criteria

- Runtime/package regressions can be caught without a full emulator scenario run.
- Provider correctness is testable independently from Paper Mario fixture behavior.

## What To Revive From The Failed Attempt

- replacement-provider parser/decode/lookup tests
- selected offline comparison and provenance tooling

## What Not To Revive

- runtime lookup-mode matrix
- ownership and consumer policy explosion
- frontend-exposed heuristic controls as product features
- permissive reinterpretation as the normal path

## Decision Gates

The project should not declare the native format/runtime seam ready until all of the following are true:

1. `PHRB` is the default runtime contract.
2. Structured sampled-object lookup is primary.
3. Compatibility fallback is explicit and secondary.
4. One non-menu Paper Mario authority fixture is active.
5. Direct provider/package tests exist.
6. At least one second-game probe exercises the same contract without adding new core runtime key rules.
7. The legacy-to-`PHRB` conversion path is available through one generic entrypoint, with smoke and round-trip coverage.
8. The Phase B2 identity-classification gate has been completed for palette parity and `LoadBlock` reinterpretation.
9. Active authority metadata is internally consistent, and semantic hi-res evidence participates in pass/fail gating.
10. If default-path auto-conversion is enabled, it is covered by direct tests and does not change native package semantics.
11. Converter operational behavior is acceptable for representative packs, including documented timing and cache expectations.

## Immediate Next Step

- The semantic hi-res gate, the first provider preservation slice, direct provider/package coverage, the earliest `hts2phrb` skeleton, the first CI palette pass, the first non-menu Paper Mario authority fixture, and the initial Phase B2 classifications are already in.
- The provider now also separates native sampled records from explicit compat low32 families:
  - structured sampled lookup no longer depends on reverse scans over all entries
  - compat low32 fallbacks no longer use native `PHRB` sampled records as if they were compatibility families
- The provider can now also describe sampled native families without changing behavior:
  - multi-selector native families stay visible as pools instead of collapsing into exact selector misses
  - sampled exact-miss debug logs can now report the preserved `policy_key`, `sampled_object_id`, selector counts, and whether the family is a pool
- Selected-package timeout validation now also preserves the conflict/unresolved split, and sampled selector review can classify the main families against the current loader manifest.
- The current runtime source split is now explicit instead of inferred:
  - active Paper Mario authorities now prefer the enriched full-cache `PHRB` artifact by default and currently run `phrb-only`
  - selected-package timeout validation is `phrb-only`
  - selected-package authority validation is also now `phrb-only` across title screen, file select, and `kmr_03 ENTRY_5`
  - if the preferred `PHRB` artifacts are absent, the shared default cache resolver still falls back to legacy `.hts` rather than failing open
- The timeout selected-package review path can now also tell whether each family still has legacy transport candidates:
  - the dominant absent triangle families `91887078`, `6af0d9ca`, and `e0d4d0dc` are now explicitly candidate-free under the current `.hts` transport model
  - the new alternate-source review lane now gives those same families a bounded review-only source path instead of leaving them as abstract future work
  - the new cross-scene review lane now proves `91887078` and `e0d4d0dc` are shared with title/file while `6af0d9ca` is shared with title only and absent on file/world, so the triangle seam is blocked on real discriminator or scene-bounded activation work rather than on missing source data
  - `28916d63` stays candidate-backed negative data, not an open transport mystery
- The first negative-data package experiment is now settled:
  - `28916d63` add-back is rejected in the current active package context because it changes the strict title/file authorities while leaving the `960` gameplay image unchanged
- The next open work is to apply those classifications to the runtime contract:
  - do not add simple `LoadBlock` retry behavior to the default path
  - do not keep widening palette CRC formula variants as if they were native identity fixes
- Continue with targeted structured runtime/package work only where direct tests and current classifications support it:
  - do not keep treating candidate-free absent families as if they were one transport-policy tweak away from promotion
  - use the new alternate-source review artifact to keep source-backed triangle work explicit and bounded, rather than letting it blur into runtime pool or duplicate-policy work
  - do not treat zero-selector singleton promotion as safe for the triangle seam just because `91887078` is a one-candidate family; the first bounded probe is authority-regressing negative data, and the cross-scene review now proves the current candidate-free triangle families still lack a safe runtime discriminator even after adding file/world absence context
  - treat `present-pool-selector-conflict` families like `1b8530fb` as a later runtime/pool-semantics task, not as a naive selector-alias task
  - the smallest `1b8530fb` tail-slot alias experiment is now also explicit negative data for promotion: it stays authority-safe and hash-neutral, but only converts the seam into a much larger duplicate-selector problem
  - the latest pool-stream diagnostics now make that deferment sharper: the active mapped set rotates across `33` unique observed selectors with no repeats, so the unresolved dwell remains an extra edge state outside the mapped set rather than another mapped-slot replay
  - keep the generated `Pool Families` review artifact and the runtime seam register current when that deferment changes, so runtime pool work only resumes from explicit evidence rather than from stale memory
  - use the explicit selected-package authority lane as the deeper bounded `PHRB` correctness proof alongside the promoted default full-cache Paper Mario authorities
  - the `7701ac09` duplicate and broader asset-alias paths are now both proven as review-only offline package-shaping slices, and the tracked review profile keeps those steps reproducible without making them default-path behavior, so they no longer need to lead the next runtime step
  - the next actionable package/runtime work now needs either a tighter source-backed selector/scene-bounding model for the triangle candidates or a real pool-preserving model for `1b8530fb`; `1b8530fb` pool work stays deferred until there is a real pool-preserving model instead of another selector-alias experiment
- Keep every skipped item in the deferred register above until it is either completed or explicitly rejected by a gate decision.

## Outcome

If this plan succeeds, the project ends up with:

- a native-first `PHRB` runtime contract
- a generic one-command legacy conversion path
- explicit and fenced compatibility behavior
- validation that is broader than Paper Mario menus and stronger than screenshot hashes
- a path to more games that does not depend on per-game runtime hacks
