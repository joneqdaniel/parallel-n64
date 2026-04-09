# Phase Overview

## Goal

- Build a stable hi-res texture replacement and scaling program for the ParaLLEl video core without losing baseline behavior when features are off

## Sequence

1. Phase 0: agent-first tooling and fixture hardening
2. Phase 1: hi-res replacement without corruption
3. Phase 2: scaling and sharpness work

## Current Redirect Inside Phase 1

The current controlling runtime/package sequence is defined in
[Hi-Res Runtime Primary Plan](/home/auro/code/parallel-n64/docs/plans/hires_runtime_primary_plan.md).

Within the existing phase ladder, the active near-term order is:

1. validation trust and authority cleanup
2. first provider/loader preservation slice for `PHRB`
3. palette parity, `LoadBlock`, and `hts2phrb` skeleton work in parallel
4. identity classification gate
5. targeted structured-runtime widening, now starting from a provider that separates native sampled records from compat low32 families, explicitly prefers `PHRB` over legacy duplicate keys in mixed cache dirs, can describe native sampled pools directly, resolves exact sampled descriptors through native sampled decode instead of checksum-only re-selection, now also keeps generic exact-checksum descriptor resolution on the native sampled path when the winning entry is a native `PHRB` record, keeps compat CI fallback descriptors in a separate compat cache path instead of re-entering generic/native duplicates, keeps resolved selector identity separate from resolved replacement checksum in renderer tile state, and from a selected-package review path that distinguishes candidate-free absent families from already-rejected selector-conflict and pool-conflict families, emits explicit pool-family deferment recommendations, and surfaces provider composition in validation summaries
   - the provider also now keeps explicit native-versus-compat checksum duplicate indices, so later runtime widening does not have to infer that split from load order
   - generic exact-checksum lookups now also return the winning entry's native-versus-compat source class directly, so the renderer no longer needs a second checksum probe just to decide between native checksum fallback and compat fallback
   - the provider now also exposes one typed resolution contract for checksum-driven and upload-time lookup, so the generic descriptor path and upload path no longer each rebuild their own sampled-family / exact-native / generic native-compat precedence from raw provider probes
   - the renderer now also routes CI low32 compat materialization through that same typed provider-resolution helper, so generic descriptor, upload, and CI compat descriptor paths now share one materialization contract
   - the sampled-exact texrect / narrow triangle seam now also consumes a provider-owned sampled resolution result for `exact-selector` versus `family-singleton`, leaving only the explicit ordered-surface reservation step outside that seam
   - compat-backed generic exact upload hits now also decode through the compat descriptor helper immediately once that source class is known, so the upload path no longer re-enters the broad generic resolver just to materialize the same compat entry
   - ordered-surface singleton sampled families now resolve through a provider-owned singleton helper instead of bespoke renderer-side selection logic, keeping that family-selection rule inside the provider seam for both upload and texrect sampled paths
   - exact sampled lookup no longer requires probe just to compute sampled identity, and the runtime-conformance tier now carries that explicit probe-off selected-package timeout lane
   - normal runtime summaries now also expose aggregate sampled singleton detail counts without requiring hit-side debug logging; current rebuilt selected-package `960` proof reports `sampled_family_singleton=0` and `sampled_ordered_surface_singleton=33` in [`20260408-title-timeout-selected-package-sampled-detail-960-rebuilt/validation-summary.json`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260408-title-timeout-selected-package-sampled-detail-960-rebuilt/validation-summary.json)
  - the generic converter is now canonical-package-first: it emits `PHRB` v7 records with explicit runtime-ready flags, 64-bit blob offsets, and preserved payload format metadata, its runtime overlay now builds only when runtime context is present, canonical packaging actually yields runtime-ready records, and deterministic bindings exist (or when overlay is explicitly forced), skipped-overlay runs no longer emit placeholder runtime-overlay files, validation-summary bundle input now resolves both summary-relative and repo/cwd-relative bundle paths, `--minimum-outcome` now lets automation gate on canonical-package success without pretending the runtime overlay is already complete, each run carries dedicated `hts2phrb-family-inventory.{json,md}` artifacts so exhaustive per-family state does not get lost behind the compact summary, emitted loader/package manifests now carry their own runtime-ready/deferred native-vs-compat counts and class strings instead of leaving that split implicit, `--reuse-existing` now invalidates on runtime-class and per-kind drift instead of trusting only total runtime-ready counts, and `hts2phrb-progress.json` now exposes that same class split while materialization is still running
  - the same front door now also lifts blocker runtime-state counts and review-backed blocker reasons to top-level report fields, including an explicit uncovered-blocker count when unresolved-review reasons do not cover every blocker family
  - the same front door now also emits a grouped canonical-only unresolved-family review, so the remaining authority-context full-cache import ambiguity is no longer just `368` flat blocker families but `134` review groups split into `98` same-aspect/context-review groups and `36` mixed-aspect/manual-review groups
  - the same front door now also lifts runtime-overlay reason counts and hash-review classes to top-level report fields, so the remaining overlay residue is visible without opening the nested overlay review first
  - review-only duplicate / alias / profile inputs on that front door are now explicitly optional overlays: if the current conversion scope does not include the reviewed family or only carries a candidate-free canonical sampled record, `hts2phrb` records the review input as `skipped` instead of failing canonical package emission
  - the same front door now also records per-input review overlay state (`applied`, `skipped`, `mixed`, or `none`), and the current Paper Mario timeout review-profile path has a direct support contract so that optional review shaping stays explicit and reusable instead of silently becoming a no-op
  - the converter now streams binary package emission directly from the legacy cache and stores legacy payload blobs on its own front-door path instead of forcing raw RGBA storage; practical consequence: full-cache zero-config conversion now completes as a practical `partial-runtime-package` artifact instead of a multi-dozen-gigabyte raw-RGBA package
  - the default zero-config output has now been refreshed in place, and the full-cache authority wrapper proves that same front-door artifact across title screen, file select, and `kmr_03 ENTRY_5`; current default result is `provider=on` + `source_mode=phrb-only` everywhere, but still `native_sampled_entry_count=0`
  - the converter now also supports repeatable `--context-bundle` inputs that enrich sampled/CI identity without changing the requested family set, including an `fs0` fallback that lets legacy generic families adopt sampled identities by matching `low32`; those context inputs can now also be fixture-based validation summary roots, and the context parser now also reads full provenance-hit rows from the bundle log so exact-authority families can promote into canonical sampled records even when the summary buckets are not enough by themselves
  - current enriched full-cache converter proof is now tracked from the current code path at [`artifacts/hts2phrb-review/20260408-pm64-all-families-authority-context-abs-summary/hts2phrb-report.json`](/home/auro/code/parallel-n64/artifacts/hts2phrb-review/20260408-pm64-all-families-authority-context-abs-summary/hts2phrb-report.json): `8992` requested families collapse to `8883` package records with `28` canonical sampled records, `8515` runtime-ready package records, `368` canonical-only families, `15` deterministic bindings, `13` unresolved overlay families, and a runtime-ready class split of `28` native-sampled vs `8487` compat
  - the same enriched artifact now also carries [`hts2phrb-runtime-overlay-review.md`](/home/auro/code/parallel-n64/artifacts/hts2phrb-review/20260408-pm64-all-families-authority-context-abs-summary/hts2phrb-runtime-overlay-review.md), which keeps the remaining `13` overlay misses explicit as `12` direct overlay cases plus `1` import-linked case instead of only reporting a flat unresolved count; the new hash review also shows that all `13` are internally pixel-divergent (`8` single-dim, `5` multi-dim), so there is no hidden within-case identical-candidate auto-promotion left on this lane
  - there is now one tracked review-only converter profile, [`tools/hires_runtime_overlay_review_profile.json`](/home/auro/code/parallel-n64/tools/hires_runtime_overlay_review_profile.json), backed by [`tools/hires_runtime_overlay_review_transport_policy.json`](/home/auro/code/parallel-n64/tools/hires_runtime_overlay_review_transport_policy.json) plus [`tools/hires_canonical_family_selection_review.json`](/home/auro/code/parallel-n64/tools/hires_canonical_family_selection_review.json). The latest persistent proof at [`artifacts/hts2phrb-review/20260409-pm64-all-families-authority-context-overlay-review-profile/hts2phrb-report.json`](/home/auro/code/parallel-n64/artifacts/hts2phrb-review/20260409-pm64-all-families-authority-context-overlay-review-profile/hts2phrb-report.json) still reduces the same lane to `19` bindings / `9` unresolved with the top-level split reading `8` direct overlay cases plus `1` import-linked case and no grouped candidate-set review residue, and now also lowers canonical-only residue from `368` families in `134` groups to `327` families in `94` groups while still passing strict full-cache authority conformance. The tracked canonical review set is now a proven forty-one-family batch, the exact-scale same-aspect/context-bundle bucket is exhausted, the first four non-integer same-aspect batches are proven, and the paired [`hts2phrb-runtime-overlay-linked-import-review.md`](/home/auro/code/parallel-n64/artifacts/hts2phrb-review/20260409-pm64-all-families-authority-context-overlay-review-profile/hts2phrb-runtime-overlay-linked-import-review.md) still shows that the only remaining non-deferred overlay blocker is the `7064585c` linked-import cluster rather than another candidate-set or transport-policy repeat
  - the same enriched family inventory now counts legacy `fs0` uploads that were absorbed into sampled canonical records through `asset_candidates`, so the current front-door family state is `8624` runtime-ready-package families and `368` canonical-only families, with the earlier stale `115`-family `diagnostic-only` bucket removed; the paired unresolved review now makes the remaining blocker class explicit as `372` exact-family-ambiguous imports, `368` canonical-only families, and `4` runtime-ready-package families backed by one canonical sampled object, and the new [`hts2phrb-unresolved-family-runtime-ready-review.md`](/home/auro/code/parallel-n64/artifacts/hts2phrb-review/20260409-pm64-all-families-authority-context-overlay-review-profile/hts2phrb-unresolved-family-runtime-ready-review.md) groups those `4` families into the single `7064585c` sampled-object unit they actually belong to
  - the paired fresh authority proof is now [`20260408-full-cache-phrb-authorities-authority-context-abs-summary-fresh/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260408-full-cache-phrb-authorities-authority-context-abs-summary-fresh/validation-summary.md): the regenerated `phrb-only` package still carries `503` native sampled entries, keeps all three authority fixtures on sampled-only descriptor traffic (`title-screen 268/0/0/0`, `file-select 214/0/0/0`, `kmr_03 ENTRY_5 182/0/0/0`), and preserves the locked screenshot hashes
  - adding the timeout-root as a fourth context source still stays review-only after both loader-manifest normalization and the tighter triangle sampled-probe filter: it widens the package to `29` canonical sampled records and keeps the lane fully sampled, but `kmr_03 ENTRY_5` still changes to `d3d2bf397d9bfd8cd311e51fc356a3130880b1ade5bbd53571ab815a08b965ad`, so the promoted baseline remains the three-authority-root package above
  - the runtime-conformance tier now carries both lanes explicitly:
    - `emu.conformance.paper_mario_full_cache_phrb_authorities` validates a current enriched artifact in place
  - `emu.conformance.paper_mario_full_cache_phrb_authorities_refresh` regenerates that enriched package from the legacy `.hts` cache plus the authority-summary-root context before validating it, with converter-side class gates for `context_bundle_class=context-enriched`, `package_manifest_runtime_ready_record_class=mixed-native-and-compat`, and the live default overlay expectation (`15` bindings / `13` unresolved); the separate review-only overlay profile is proven by its own converter contract plus a strict wrapper rerun, not by changing this default gate
    - `emu.conformance.paper_mario_full_cache_phrb_authorities_zero_config_refresh` regenerates the zero-context front-door package from the legacy `.hts` cache alone before validating the current compat-backed baseline, with converter-side class gates for `context_bundle_class=zero-context` and `package_manifest_runtime_ready_record_class=compat-only`
  - representative converter operational gates now exist for both local full-cache Paper Mario variants:
    - the current-cache contract enforces `partial-runtime-package`, `10 s`, `2.1 GB`, and `--reuse-existing`
    - the pre-v401 contract enforces the same output/cache shape with a `12 s` timing gate
  - practical consequence: the converter already has real local timing/cache/output-size gates on the only full-cache legacy variants available here; remaining breadth work is about runtime generalization and new inputs, not absence of any operational baseline
  - those authority/timeout summaries now also carry native-checksum detail counts alongside generic detail counts, so any future fallback residue is easier to classify precisely
  - generic detail counts now also split plain generic traffic into `native`, `compat`, and `unknown` buckets while preserving the older aggregate `plain` count, so summary consumers can see how much checksum-shaped traffic is still native-backed versus truly compat-backed
  - the renderer resident-image cache now also splits generic descriptor entries by that resolved source class, so native-backed generic traffic and compat-backed generic traffic do not share one generic cache bucket just because the checksum/selector tuple matches
  - the final generic decode path now also routes through the matching native or compat provider decode helper when that source class is known, so generic descriptor residue no longer re-enters the broad generic decode helper just to materialize image bytes
  - the main CI/low32 compat ladder is now provider-owned too: renderer upload-time CI fallback no longer open-codes `selected-dims`, `replacement-dims-unique`, `unique`, and `any-preferred` compat lookup sequencing, but instead consumes one typed compat resolution result from `ReplacementProvider`; the probe-only CI palette diagnostics still use the raw low32 helpers for now and remain outside the main runtime seam
  - the last sampled-exact ordered-surface reservation lookup is now provider-owned too: once the renderer reserves an ordered-surface slot, it now asks `ReplacementProvider` for one typed reserved-selector resolution instead of re-entering the raw sampled lookup helper; the renderer still owns the ordered-surface cursor state, but the fallback lookup/classification itself no longer lives there
  - generic exact lookup is now native-first for `PHRB` family-runtime compat stubs that share a checksum with a native sampled record, which removes another load-order seam without changing the explicit compat-alias path
  - practical consequence: the enriched full-cache Paper Mario lane has now crossed from `generic=0` to `compat=0` as well; the remaining converter/runtime gap is no longer “make the active authority fixtures stop using fallback” but “keep widening native sampled coverage beyond this authority-enriched Paper Mario set without regressing the contract”
6. default-path promotion only after the Paper Mario breadth gate

Current runtime split:

- active Paper Mario authorities now resolve only through the promoted full-cache `PHRB` artifacts by default and fail closed if no preferred `PHRB` artifact is available
- remaining repo-local `.hts` references on the runtime side are explicit refresh, probe, or review inputs rather than silent defaults; the default-authority contract now also verifies that both the shared scenario cache resolver and the default full-cache conformance wrapper stay enriched-`PHRB`-first and do not implicitly fall back to zero-config or legacy artifacts
- selected-package timeout validation is the current deeper `PHRB` runtime lane
- selected-package authority validation now also proves the same explicit `PHRB` lane across title screen, file select, and `kmr_03 ENTRY_5`
- both selected-package lanes are now part of the opt-in runtime-conformance tier:
  - `emu.conformance.paper_mario_selected_package_authorities`
  - `emu.conformance.paper_mario_selected_package_timeout_validation`
  - `emu.conformance.paper_mario_selected_package_timeout_lookup_without_probe`
- the current selected-package `960` timeout proof now reports descriptor-path usage directly
  - current outcome: `descriptor_paths(sampled=66 native_checksum=0 generic=0 compat=0)` in [`20260407-selected-package-timeout-current-contract/validation-summary.md`](/home/auro/code/parallel-n64/artifacts/paper-mario-probes/validation/20260407-selected-package-timeout-current-contract/validation-summary.md)
  - practical consequence: the active explicit `PHRB` timeout lane is currently proving structured sampled resolution directly, not leaning on native-checksum or generic/compat fallback
- the same timeout lane is currently pixel-identical to `off`
  - current outcome: `on_hash=4bd3929dabff3ffb1b7e03a9c10d8ce50e9b6d0f067825d3a788c48a41b6fc62`, `matches_off=true`
  - practical consequence: the timeout lane is now a runtime-contract proof for the explicit `PHRB` path rather than a visible-improvement proof, and deferred `1b8530fb` pool evidence now falls back to the historical pool-regression review when live draw-sequence reconstruction is unavailable
- both explicit selected-package lanes now fail closed if provider composition drifts away from `phrb-only`
- runtime source policy now also has an explicit `auto` bridge mode for mixed cache directories:
  - `auto` prefers `.phrb` when native and legacy cache formats coexist, and empty / unset policy now also defaults to that same `auto` bridge mode unless a lane pins a stricter policy explicitly
  - the low-level provider default now also uses that same `auto` mode, so direct cache-directory loads no longer silently broaden back to `all` unless a caller opts in
  - validation evidence now keeps that distinction explicit by recording both `source_policy` (requested loader policy) and `source_mode` (actual loaded source mix)
- selected-package timeout validation now also emits live sampled selector and sampled pool reviews when transport review input is present
  - current `1b8530fb` outcome stays `defer-runtime-pool-semantics` at the family level and `keep-flat-runtime-binding` at the pool-shape level
  - the live selected-package timeout summary now also carries the active pool replacement id, currently `legacy-038a968c-9afc43ab-fs0-1184x24`
- the same timeout lane now also emits a bounded flat-vs-surface regression review for `1b8530fb` when the historical `960` comparison inputs are present
  - current outcome: the live bundle now keeps the March 30 flat, dual, and ordered-only `960` comparisons attached to the current pool review, and the recommendation stays `keep-flat-runtime-binding`
  - practical consequence: `1b8530fb` pool deferment is now documented from one current artifact instead of from scattered historical bundle references
- the same timeout lane now also carries live pool-stream diagnostics for `1b8530fb`
  - current outcome: the active mapped set rotates across `33` unique observed `texel1-peer` selectors with `32` transitions and no repeats inside the mapped set
  - practical consequence: the unresolved dwell is still an extra edge state outside the mapped selectors, so the new evidence sharpens `keep-flat-runtime-binding` instead of weakening it
- the smallest `1b8530fb` tail-slot follow-up is now also classified and stays review-only
  - current outcome: a review-only surface-policy overlay that fills the unresolved tail slot and compiles `surface-1b8530fb` in `dual` mode is byte-identical to the active selected package on title screen, file select, `kmr_03 ENTRY_5`, and the `960` timeout frame
  - current limitation: the same candidate leaves `exact_unresolved_miss_count` unchanged at `90877`, removes the live pool-review artifact, and turns the seam into `67` sampled-duplicate keys / entries across `10` duplicate families
  - practical consequence: filling the tail slot alone is not a promotable fix; keep the active runtime shape on `keep-flat-runtime-binding` and keep the review path explicit instead of half-promoted
- selected-package timeout conformance now also asserts the current sampled duplicate accounting for the active package
  - current outcome: `entries=195`, `native_sampled=195`, `sampled_index=194`, `sampled_dupe_keys=1`, `sampled_dupe_entries=1`
  - practical consequence: the current `194/195` split is now treated as explained package-level duplicate identity instead of as unexplained runtime drift
  - the same lane now emits one live duplicate-review bucket for `sampled_low32=7701ac09`, `fs=768`, `selector=0000000071c71cdd`, active policy `surface-7701ac09`, and active replacement id `legacy-844144ad-00000000-fs0-1600x16`
  - the same lane now also emits a bounded duplicate review for `7701ac09`
    - current outcome: the active `0000000071c71cdd` selector collision resolves to two `1600x16` candidates with identical pixel hashes, and the broader package duplicate-pixel group already spans `legacy-2cf87740-00000000-fs0-1600x16`, `legacy-844144ad-00000000-fs0-1600x16`, and `legacy-e0dc03d0-00000000-fs0-1600x16`
    - practical consequence: keep the stable runtime winner rule for now and treat the next move as offline dedupe/alias policy, not as a broader runtime merge policy
  - runtime duplicate selection for that family is now stable by preserved native `replacement_id`, so the selected-package lane no longer depends on load order even though deeper duplicate merge/classification work is still deferred
  - the same conformance lane now fails closed if either of those live replacement ids disappears
- the first review-only offline dedupe candidate for that seam is now also proven
  - candidate package: [`20260407-selected-plus-timeout-960-v1-dedupe-7701ac09/package.phrb`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260407-selected-plus-timeout-960-v1-dedupe-7701ac09/package.phrb)
  - current outcome: title screen, file select, `kmr_03 ENTRY_5`, and the `960` timeout image all stay byte-identical to the active selected package while runtime sampled-duplicate accounting drops from `1` key / `1` entry to `0` / `0`
  - practical consequence: exact pixel-identical duplicate follow-up is now a bounded offline package-shaping seam, not a reason to widen runtime merge behavior
- the broader `7701ac09` asset-alias follow-up is now also proven as a review-only package-shaping slice
  - candidate package: [`20260407-selected-plus-timeout-960-v1-dedupe-7701ac09-asset-alias-review/package.phrb`](/home/auro/code/parallel-n64/artifacts/hires-pack-review/20260407-selected-plus-timeout-960-v1-dedupe-7701ac09-asset-alias-review/package.phrb)
  - current outcome: all four selectors in the broader identical-pixel group now reuse the canonical `legacy-844144ad-00000000-fs0-1600x16` asset and one materialized PNG path, while title screen, file select, `kmr_03 ENTRY_5`, and the `960` timeout image stay byte-identical and runtime sampled-duplicate accounting stays `0` / `0`
  - practical consequence: broader identical-pixel follow-up is now an offline asset-alias/promotion question, not a runtime merge blocker
- the selected-package builder now also accepts a tracked review-only profile for the current proven `7701ac09` shaping inputs
  - review profile: [`tools/hires_selected_package_review_profile.json`](/home/auro/code/parallel-n64/tools/hires_selected_package_review_profile.json)
  - current outcome: `--review-profile` reproduces the explicit duplicate-review plus alias-group-review package byte-for-byte
  - practical consequence: the build path can carry review-only shaping coherently before any default promotion decision
- selected-package builder support is now rich enough to reproduce both kinds of review-only package shaping
  - `--duplicate-review` reproduces the `7701ac09` dedupe candidate from tracked `bindings.json`
  - `--alias-group-review` reproduces the `7701ac09` asset-alias candidate from tracked `bindings.json` plus the alias-group review input
  - `--review-profile` reproduces the same combined `7701ac09` review-only shaping from one tracked input
  - `--surface-transport-policy` now reproduces the `1b8530fb` tail-slot review candidate from the tracked surface package plus the review policy overlay
- selected-package timeout validation now also emits a review-only alternate-source artifact when a source cache is provided
  - current alternate-source outcome: the candidate-free triangle trio now has `13` review-only source-backed candidates total, split as `91887078 -> 1`, `6af0d9ca -> 7`, and `e0d4d0dc -> 5`
  - practical consequence: the repo now has a bounded new-source lane for those families without pretending they are runtime-ready
- the same timeout lane now also has a cross-scene promotion review for the triangle trio
  - current outcome: `91887078` and `e0d4d0dc` already share absent runtime signatures with title screen and file select before promotion, while `6af0d9ca` is shared with title only and absent on both file select and steady-state `kmr_03 ENTRY_5`
  - practical consequence: the triangle seam is now blocked on a tighter discriminator or scene-bounded activation model, not on missing source data or missing timeout-side capture; the likely boundary is narrower than “all gameplay,” but still not bounded enough for promotion
- the same timeout lane now also emits a joined alternate-source activation review
  - current outcome: the joined review reports `review_bounded_probe_count=0` and `shared_scene_blocked_count=3`, with `91887078`, `6af0d9ca`, and `e0d4d0dc` all still classified as `shared-scene-source-backed-candidates`
  - practical consequence: the shallow source-backed boundary is now explicit in one artifact, so the next shallow step is not more source discovery or cross-scene restatement; it is a tighter activation discriminator
- the first bounded alternate-source promotion probe is now recorded as negative data
  - current outcome: a zero-selector singleton for `91887078` clears that family's `960` timeout misses without changing the gameplay frame, but it regresses selected-package title and file-select authorities
  - practical consequence: triangle source-backed work stays review-only until a tighter activation model exists, and the probe-emission path now refuses shared-scene zero-selector promotion unless explicitly overridden for review
- later timeout checkpoints now also show that the source seam drifts with phase
  - current outcome: `1200` moves into battle and broadens the candidate-free/source-backed worklist, while `1500` returns to world and lands on `on == off` despite review-only source candidates still being present
  - practical consequence: `960` remains the bounded source-path target; later checkpoints are evidence about phase drift, not immediate promotion targets
- selected-package timeout validation now also emits a runtime seam register
  - current register: candidate-free `91887078` / `6af0d9ca` / `e0d4d0dc`, candidate-backed `28916d63`, pool-conflict `1b8530fb`, duplicate family `7701ac09`
  - the same register now also records that all three candidate-free triangle families already have alternate-source review candidates
  - the same register now also records all three candidate-free triangle families as `no-runtime-discriminator-observed`
  - the same register now also records `candidate_free_review_bounded_probe_count=0`
  - practical consequence: deferred runtime work now travels as a single reviewed artifact instead of scattered prose
- provider-composition gates can now distinguish those lanes explicitly via `source_mode`, so native-`PHRB` minimums should not be promoted into the authority fixtures until that lane actually moves

This does not replace the Phase 0 / Phase 1 / Phase 2 backbone. It defines the
current execution order inside the hi-res replacement phase.

Completed enabling slices and any intentionally deferred work must stay recorded
in [Hi-Res Runtime Primary Plan](/home/auro/code/parallel-n64/docs/plans/hires_runtime_primary_plan.md),
especially its `Current Implementation State`, `Deferred Work Register`, and
`Immediate Next Step` sections.

## Why This Order

- tooling first reduces ambiguity
- hi-res replacement must stabilize before scaling work can be trusted
- scaling should build on a proven replacement path, not on a moving target

## Current Validation Scope

- Paper Mario only

## First Fixture Ladder

1. active: title screen
2. active: file select main menu
3. active: `kmr_03 ENTRY_5`
4. planned: `hos_05 ENTRY_3`
5. planned: `osr_00 ENTRY_3`

## Global Rules

- `feature off` must remain baseline-safe
- `feature on` prioritizes correctness and diagnosability over early broad coverage
- all fixture runs require evidence bundles
- all fallbacks and exclusions require explicit reason reporting
- unsupported or risky categories must be listed explicitly, not implied away

## Gate Style

- hybrid gating
- tooling and docs can overlap
- renderer milestones require explicit phase sign-off
- semantic hi-res evidence must participate in pass/fail before default-path promotion
