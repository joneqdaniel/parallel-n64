# Making Hi-Res Work for Any Game

## Situation Assessment

This project has spent significant effort on the right fundamental insight — that
ParaLLEl RDP (LLE) sees textures differently than Glide64/Rice (HLE) — but the
execution went sideways into bespoke per-game analysis tooling instead of making
the general case work first.

**What works today:**
- Legacy `.hts` pack lookup gets 91% hits on Paper Mario title screen (178/196)
- The Rice CRC texture hash is already correct (same algorithm, same RDRAM data)
- The PHRB binary format is well-designed for runtime consumption
- The fixture/scenario framework is solid for regression testing
- The renderer code is clean with a dual lookup path (authored + sampled)

**What doesn't work:**
- Paper Mario file-select only gets 50% hits (82/165) — CI palette mismatches
- `LoadBlock` shape mismatches (64x1 upload keyed differently than 16x16 sampled)
- The sampled-object lookup is behind a debug env var, not production
- 39 Python tools require ~15-25 person-days of manual work per game
- No path to "any game" — everything is Paper-Mario-specific

**Root cause of the gap:**
The texture CRC is fine. The problems are (1) palette CRC mismatch for CI textures,
and (2) upload-shape vs sampled-shape mismatch for LoadBlock textures. These are
general N64 problems, not Paper Mario problems, and should be solved generically.

---

## Strategy: Investigate, Build, Then Decide the Architecture

The project's previous 200-commit failure was caused by premature architecture:
redesigning the runtime contract before the actual identity issues were understood.
This plan inverts that pattern — investigate the concrete, measurable problems first,
use the results to make informed architectural decisions, and defer structural
redesign until evidence demands it.

**Sequencing principle:** Every step must produce a testable improvement or a
concrete decision. No step should be a multi-week refactor with no observable
outcome. Tests are written alongside each step, not batched at the end.

**Runtime format:** PHRB is the right runtime format — it's cleaner, faster, and
carries richer identity than legacy `.hts`/`.htc`. But the path to PHRB must be a
**single generic converter** that works for any game, not a 39-tool pipeline
requiring manual policy per game.

**Architectural guardrail:** The converter and runtime must not collapse PHRB into
a container for mostly legacy-shaped runtime keys. Records must carry all identity
fields the format supports, even when the runtime initially keys on a subset. This
ensures the format is ready for structured sampled-object lookup when that ships
later, without requiring re-conversion.

**The tool:** `hts2phrb` — one command, one input, one output.

```
hts2phrb "PAPER MARIO_HIRESTEXTURES.hts" --output paper-mario.phrb
```

No policy files. No per-game tuning. No surface packages. Just conversion.

---

## Why This Sequence: Investigate Before Architecture

The competing plan (Codex Runtime Redirect) proposes the opposite sequencing:
redesign the provider to structured sampled-object keys first (Phase A), then
investigate the CRC/LoadBlock issues (Phase B1), then build the converter (Phase A1).

This plan deliberately inverts that order. Here is why.

### The failed branch died from premature architecture

The previous 200-commit attempt rewrote runtime lookup modes, ownership policies,
and consumer contracts before understanding why textures were actually missing.
That produced a policy explosion with no measurable improvement to hit rates.
Codex's Phase A repeats this pattern: redesigning the provider lookup to structured
keys before the CRC/LoadBlock issues are even investigated. The structured key model
may need revision once the investigation results are in — meaning the redesign could
be wasted work.

### The investigations produce measurable results immediately

Step 1 (palette CRC) has a concrete numeric target: file-select hits from 82 to
~150+. Step 2 (LoadBlock reinterpretation) resolves a documented miss family. Both
can be validated in days with existing fixtures. A provider redesign to structured
keys produces zero visible improvement to hit rates — it's a refactoring step that
only pays off later when the structured fields are populated (which requires ROM-scan
enrichment that doesn't exist yet).

### The converter can't populate the structured key fields anyway

Codex's Phase A calls for replacing `checksum64 + formatsize` with a key using
`fmt`, `siz`, `tile`, `tmem`, `line`, `logical size`, and palette identity. But
Codex's own Phase A1 admits (line 93) that most of these fields are unknowable from
a legacy `.hts` pack. The converter would emit records with zero-defaulted structured
fields that the redesigned provider can't meaningfully use for lookup. This means
the provider redesign is blocked on ROM-scan enrichment tooling that is itself
blocked on having a working converter — a circular dependency that delays everything.

### Evidence-first sequencing avoids rework

By investigating the CRC and LoadBlock issues first, we learn whether
`checksum64 + formatsize` with corrected CRCs is sufficient for cross-game lookup.
If it is, the structured key redesign becomes an optional optimization (Step 7)
rather than a prerequisite. If it isn't, the classification gate at Step 2.5 tells
us exactly which structured fields are needed and why — making the eventual provider
redesign targeted rather than speculative.

### Every intermediate step is shippable

After Step 1 alone, file-select hit rates improve. After Step 3, users have a
one-command converter. After Step 5, zero-config hi-res works for Paper Mario.
Codex's sequencing produces no user-visible improvement until Phase A1 ships —
which is sequenced after the provider redesign (Phase A) and the classification
gate (Phase B2). That's weeks of invisible infrastructure before anything works
better than it does today.

### The architectural destination is the same

Both plans end at the same place: PHRB as runtime, generic converter, structured
identity in records, explicit compat fencing, cross-game validation. The
disagreement is purely about whether the provider redesign happens before or after
the investigations. Since the converter emits all PHRB identity fields regardless
of the current runtime key model, both orderings reach the same destination — but
ours produces working results at every intermediate step.

---

## Promotion Rule

No new behavior should be promoted to the default runtime path unless all of:

1. It improves active authority fixtures.
2. It does not break semantic hi-res evidence expectations.
3. It survives the classification gate (Step 2.5).
4. It does not require game-specific runtime key rules.
5. It fits the native-first runtime contract.

---

## Execution Overview

Work is organized into seven phases. Phases 0 and I run in parallel. The converter
skeleton starts late in Phase I before the classification gate. Tests are written
alongside each step, not batched at the end.

```
Phase 0: Validation Infrastructure ──────────────┐
Phase I: Parallel Investigations (1 + 2) ────────┤
                                                  ├─ Phase II: Classification + Provider Fix
                                                  │
              Converter skeleton starts ──────────┤
                                                  ├─ Phase III: Converter Completion
                                                  │
                                                  ├─ Phase IV: Paper Mario Validation
                                                  │
                                                  ├─ Phase V: Ship (Default Path + Second Game)
                                                  │
                                                  └─ Phase VI: Structured Key Decision
```

| Phase | Steps | Days | Notes |
|-------|-------|------|-------|
| 0. Validation infra | 0a-0d | 1-2 | Parallel with Phase I |
| I. Investigations | 1, 2 | 3-5 | 1 and 2 in parallel |
| II. Classify + fix | 2.5, 2.75 | 1 | Gate + cheap provider fix |
| III. Converter | 3 | 2-3 | Skeleton starts late Phase I |
| IV. PM validation | 4 | 1-2 | Fixtures ready from Phase 0 |
| V. Ship | 5, 6 | 3-5 | Promotion + second game |
| VI. Decision | 7 | 0.5-5 | Evidence-driven |

**Estimated total: 13-20 days** (parallelization saves 3-8 days vs serial execution)

### Parallelism Rules

**Can run in parallel:**
- Phase 0 (validation infra) and Phase I (investigations)
- Step 1 (palette CRC) and Step 2 (LoadBlock)
- Converter skeleton (Step 3a) starts late Phase I, before classification gate
- Tests are written alongside their parent steps
- Second-game fixture preparation can start once Paper Mario authority is stable

**Must remain serial:**
- Validation infrastructure (Phase 0) before interpreting hit-rate movement
- Both investigations complete before classification gate (Step 2.5)
- Classification before converter wires in classified behavior (Step 3b)
- Paper Mario full gate (Step 4) before default-path promotion (Step 5)
- Second-game gate (Step 6) before claiming generality
- All gates before structured-key decision (Step 7)

---

## Phase 0: Validation Infrastructure

Runs in parallel with the investigations. Zero dependency on CRC or LoadBlock work.
Goal: when investigation results land, they validate against a broader, more rigorous
fixture set immediately.

### 0a. Mint Non-Menu Fixture (~0.5 day)

Promote the `hos_05 ENTRY_3` scene to an authoritative fixture. The scenario script,
runtime env, and authority-graph node already exist. The remaining work is defining
the controller-input route from file-select into `hos_05`, minting the savestate,
and hashing steady state.

### 0b. Resolve Metadata Drift (~0.5 day)

Audit `expected_capture_sha256` across fixtures, authority graph, and env files.
Reconcile or remove stale hashes. Pure docs/fixtures cleanup.

### 0c. Build Evidence-Assertion Harness (~0.5-1 day)

Build a test that reads an evidence bundle and asserts on class presence and
semantic signal categories (`exact`, `compat`, `conflict`, `unresolved`). Wire it
into the existing title and file-select scenarios first. The block-family and
tile-family probe fixtures already define evidence requirements.

### 0d. Wire Semantic Evidence into Pass/Fail (~0.5 day)

Make the test runner fail when `hires-evidence.json` signals degrade from the
recorded baseline. Current hit rates provide the baseline expectations.

### Exit Criteria

- `hos_05 ENTRY_3` is an active authoritative fixture
- Metadata is internally consistent across fixtures, authority graph, and env files
- Semantic evidence assertions run on title and file-select scenarios
- The assertion harness is ready to absorb investigation results immediately

---

## Step 1: Investigate Palette CRC Parity

**Runs in parallel with Step 2.** No dependency between the two investigations.

**Problem:** ParaLLEl's CI palette CRC doesn't match what pack creators used.

**Root cause analysis:** GlideN64 computes the hi-res palette CRC like this:

```
// On LoadTLUT:
gDP.TexFilterPalette = raw RDRAM copy (2 bytes per entry, contiguous)

// On hi-res lookup (CI4):
palette_data = gDP.TexFilterPalette + (tile->palette << 4)   // 16 entries
rice_crc = RiceCRC32(palette_data, cimax+1, 1, 2, 32)

// On hi-res lookup (CI8):
palette_data = gDP.TexFilterPalette                           // 256 entries
rice_crc = RiceCRC32(palette_data, cimax+1, 1, 2, 512)

// Combined key:
checksum64 = (palette_rice_crc << 32) | texture_rice_crc
```

**What ParaLLEl does:** Uses `rice_crc32_wrapped` on `tlut_shadow` (also RDRAM bytes).
The algorithm is the same. The question is whether `tlut_shadow` contains the same
bytes as `TexFilterPalette` at lookup time.

**Key differences to investigate:**
1. `TexFilterPalette` is populated from raw RDRAM on LoadTLUT via simple `memcpy`
2. `tlut_shadow` is also populated from raw RDRAM, but the offset/range logic has
   been patched multiple times and may not match GlideN64's simpler `memcpy`
3. For CI4, GlideN64 indexes by `palette << 4` (16 entries x 2 bytes = 32 bytes),
   ParaLLEl indexes by `bank * 32` — should match if `palette == bank`
4. For CI8, GlideN64 uses the full `TexFilterPalette` (512 bytes),
   ParaLLEl uses `tlut_shadow` from offset 0 with stride 512

### Sub-steps:

**1a. Instrumentation** (~1 day)
- [ ] Add a debug comparison mode that logs both ParaLLEl's computed palette CRC
      and what GlideN64's algorithm would produce given the same RDRAM state
- [ ] Run on Paper Mario file-select and identify exactly where the CRCs diverge

**1b. Fix** (~1-2 days)
- [ ] Fix `tlut_shadow` population to match `TexFilterPalette` semantics exactly
- [ ] Verify CI4 bank offset math matches GlideN64's `palette << 4` indexing
- [ ] Verify CI8 entry-count logic matches GlideN64's `cimax + 1` computation
- [ ] Validate: file-select hits should jump from 82 to ~150+ after fix

**1c. Test** (~0.5 day, written alongside 1b)
- [ ] Unit test: feed known RDRAM byte sequences into both ParaLLEl and GlideN64
      CRC algorithms, assert matching output
- [ ] This test exists before the fix ships, catching regressions from day one

**Key files:**
- GlideN64 palette CRC: `~/code/gliden64-upstream/src/GLideNHQ/TxUtil.cpp:82-116`
- GlideN64 TexFilterPalette: `~/code/gliden64-upstream/src/gDP.cpp:758-767`
- GlideN64 hi-res lookup: `~/code/gliden64-upstream/src/Textures.cpp:1210-1228`
- ParaLLEl palette CRC: `parallel-rdp/rdp_hires_ci_palette_policy.hpp:549-577`
- ParaLLEl tlut_shadow: `parallel-rdp/rdp_renderer.cpp:4100-4150`
- ParaLLEl texture CRC: `parallel-rdp/texture_keying.hpp:30-58`

**Success criteria:** Paper Mario file-select CI palette CRC matches GlideN64's
computation for the same RDRAM state. Parity test passes.

**If the fix is partial** (hits reach 60-65% instead of 85%+): do not spiral into
per-case debugging. Log the remaining misses, classify them by cause, and proceed
to Step 2.5. The classification gate will determine whether the partial fix is a
native identity fact or a dead end.

---

## Step 2: Investigate LoadBlock Dimension Reinterpretation

**Runs in parallel with Step 1.** No dependency between the two investigations.

**Problem:** Some textures are uploaded via `LoadBlock` as e.g. 64x1 but sampled as
16x16 CI4 via `SetTile`/`SetTileSize`. The pack keys them as 16x16, ParaLLEl keys
them as 64x1.

**Why this happens:** `LoadBlock` treats TMEM as a flat buffer and uses `dxt` to
define the line stride for odd-line interleaving. The actual sampled dimensions come
from `SetTile`/`SetTileSize`, which may describe a completely different shape. Pack
creators (using Rice/Glide64) saw the texture as its final sampled shape, not as the
raw upload shape.

**This needs to be solved in two places:**

### 2a. In the runtime lookup (for direct `.hts` fallback during development)

When the primary RDRAM CRC lookup misses on a `LoadBlock` upload, compute the
sampled dimensions from the tile descriptor and retry:

```
if (miss && upload_was_loadblock) {
    sampled_w = (tile.sh - tile.sl + 4) >> 2;
    sampled_h = (tile.th - tile.tl + 4) >> 2;
    sampled_fmt = tile.fmt;
    sampled_siz = tile.siz;

    texture_crc = rice_crc32_wrapped(rdram, rdram_size, src_addr,
                                     sampled_w, sampled_h, sampled_siz,
                                     sampled_stride);
    retry_result = provider->lookup(checksum64, formatsize_from_sampled);
}
```

### 2b. In the generic converter (`hts2phrb`)

When emitting PHRB records from legacy pack entries, detect LoadBlock-shaped entries
(where the legacy key dimensions don't match what a LoadBlock upload would produce)
and emit records keyed to both the legacy shape AND the upload shape. This way the
PHRB runtime lookup hits regardless of which view the renderer uses.

### Sub-steps:

**2a. Instrumentation** (~0.5 day)
- [ ] Annotate uploads as `LoadBlock` vs `LoadTile` (already partially done)
- [ ] Log sampled-dimension mismatches to identify the miss class size

**2b. Fix** (~1-2 days)
- [ ] Implement sampled-dimension retry in the runtime lookup path
- [ ] Validate: the dominant 64x1 fs514 miss family should resolve
- [ ] Verify no false positives on title screen (which is already 91% hits)

**2c. Test** (~0.5 day, written alongside 2b)
- [ ] Unit test: known 64x1 LoadBlock upload → retry with sampled 16x16 → hit
- [ ] Negative test: non-LoadBlock upload does NOT trigger retry path

**False positive risk:** Games with heavy LoadBlock traffic (Zelda OoT, GoldenEye)
could theoretically surface CRC collisions where the reinterpreted shape matches the
wrong texture. The retry-on-miss design limits this — only fires when the primary
lookup fails — but Step 6 must explicitly validate against this risk.

**Success criteria:** Paper Mario file-select block-class misses resolve.
LoadBlock reinterpretation test passes.

---

## Step 2.5: Identity Classification Gate

After Steps 1-2 are validated on Paper Mario, explicitly classify the results.

**Are the palette CRC fix and LoadBlock reinterpretation:**

1. **Native identity facts** — meaning they represent how N64 textures actually work,
   and should be baked into the PHRB format and converter as canonical behavior.
2. **Bounded compatibility helpers** — meaning they're workarounds for legacy pack
   authoring conventions, and should stay as explicit secondary runtime behavior
   behind a mode flag, not baked into the default path.
3. **Dead ends** — meaning they don't materially improve hit rates or introduce
   false positives, and should be dropped.

### Classification Rules

- Classify as **native identity fact** only if it reflects canonical N64 texture
  identity across games — not just a legacy pack lookup convention.
- Classify as **bounded compatibility helper** if it materially improves legacy-pack
  behavior but should remain explicit secondary behavior.
- Classify as **dead end** if it does not generalize cleanly, introduces false
  positives, or does not materially improve results.

### What Happens After Classification

- **Native fact**: Baked into the converter as default behavior. Baked into the
  runtime as the primary lookup path. No mode flag needed.
- **Bounded helper**: Lives behind an explicit `--compat` flag in the converter
  and an explicit compatibility mode in the runtime. Not active by default.
  Documented as secondary behavior, not the canonical identity path.
- **Dead end**: Removed. No further work.

### Exit Criteria

- Both investigations have a written classification outcome with supporting data
  (hit rates before/after, false positive count, generality assessment).
- The converter and runtime plans reflect those classifications explicitly.
- No compatibility seam is promoted into canonical runtime identity without passing
  this gate.

---

## Step 2.75: Preserve PHRB Identity at Load Time

**A cheap, targeted fix that stops the provider from discarding structured data.**

Currently, `add_sampled_entry` in `texture_replacement.cpp` (line ~941) reads PHRB
records carrying `fmt`, `siz`, `tex_offset`, `stride`, `sampled_low32`,
`sampled_entry_pcrc`, and `sampled_sparse_pcrc` — then compiles them down to a flat
`checksum64` key for the in-memory `Entry` struct, discarding everything else. The
richer identity PHRB was designed to carry is thrown away at load time.

### Fix:
- Add `fmt`, `siz`, `tex_offset`, `stride`, and `sampled_low32` fields to the
  `Entry` struct (~6 lines in the header)
- Populate them from the PHRB record in `add_sampled_entry` (~6 lines in the cpp)

### What this does NOT change:
- No lookup key changes — `checksum_index_` and `checksum_low32_index_` stay the same
- No behavioral changes — `find_entry`, `lookup`, `lookup_with_selector` untouched
- No calling code changes

### What it enables:
- The converter (Step 3) can emit fully populated records knowing the runtime
  preserves them instead of throwing them away
- Debug/diagnostic tools can query structured identity without re-parsing PHRB
- Step 7 (structured key decision) has the data in memory, ready for a lookup
  redesign if needed — without requiring re-conversion or re-loading

**Effort:** ~15-20 lines across 2 files. Half-day task. Zero regression risk.

**Key files:**
- `texture_replacement.cpp:941-960` (`add_sampled_entry`)
- `texture_replacement.hpp:88` (`Entry` struct)

---

## Step 3: Build the Generic Converter

**Goal:** A single tool that converts any `.hts`/`.htc` to `.phrb` with no per-game
configuration.

**Note:** The converter skeleton (`.hts` parsing, PHRB record emission, identity
field population) can start late in Phase I, since those parts are format-agnostic
and don't depend on the classification gate. Palette CRC and LoadBlock behavior slot
in after Step 2.5.

### Design Principles

**Structured records, not legacy repackaging.** The converter must NOT simply wrap
Rice CRC keys in PHRB packaging — that would make PHRB a glorified `.hts` wrapper.
Each emitted PHRB record carries **all identity fields the format supports**, even
if the runtime initially only keys on `checksum64 + formatsize` for lookup.

**Converter non-goals** (from Codex's plan, adopted as hard constraints):
- Do not collapse PHRB into a container for mostly legacy-shaped runtime keys just
  to make conversion simpler.
- Do not turn auto-conversion convenience into a substitute for fixing the
  provider/runtime identity contract.
- Do not pretend currently unknown sampled-object fields are known just to make the
  first converter output look complete.

### Record Structure

- **Populated from the legacy entry:** `sampled_low32` (= Rice texture CRC),
  palette CRC (corrected per classification gate), `formatsize`, dimensions, RGBA data
- **Populated as derivable defaults:** `fmt`, `siz` (extracted from `formatsize`)
- **Left as zero/unknown for now:** `tile`, `tmem offset`, `line stride`, `tlut_type`
- **Explicit flags:** which fields are populated vs zero-defaulted, so the runtime
  can distinguish "field is zero" from "field was not available at conversion time"

This means:
- Records are ready for structured sampled-object lookup when that ships later
- No re-conversion needed when the runtime key model evolves
- The converter is an orchestration layer, not a dumbed-down shortcut

### What it does:
1. Parse all entries from the legacy pack (reusing `hires_pack_common.py`)
2. For each entry, emit a PHRB record with all available identity fields
3. Apply palette CRC behavior per the classification gate outcome
4. For entries classified as LoadBlock-shaped, emit reinterpreted-dimension
   variants per the classification gate outcome
5. For CI entries with multiple palette variants in the pack, emit all variants
   as separate PHRB records (the runtime picks the matching one)
6. Emit warnings and diagnostics for ambiguous cases instead of silently
   broadening runtime behavior

### What it does NOT do:
- No per-game policy files
- No manual transport selection
- No surface package modeling
- No ordered-slot analysis
- No ROM scanning (that's a future enhancement via `--enrich` flag)

### Enrichment path (future, not required for initial converter):

```
# Basic: generic conversion, works for any game
hts2phrb pack.hts -o pack.phrb

# Enriched: ROM-scan fills in tile/tmem/line/tlut_type fields
hts2phrb pack.hts --rom game.z64 -o pack.phrb

# Policy-assisted: for games with known ambiguities
hts2phrb pack.hts --policy game-policy.json -o pack.phrb
```

The basic path must work with zero extra inputs. Enrichment and policy are opt-in
for games that need them, accessed through the same front door.

### Ambiguity handling:
- If multiple legacy entries map to the same PHRB key, emit all of them and let
  the runtime pick the first match (or use replacement dimensions as tiebreaker)
- Log warnings for ambiguous cases so users can investigate if needed
- This handles 95%+ of real packs where entries are unambiguous

### Sub-steps:

**3a. Skeleton** (~1 day, starts late Phase I)

The earliest shippable form of the converter is a skeleton that can run end-to-end
without classified behavior. It must produce:
- One command, one input, one output
- Structured PHRB records with all known identity fields
- Ambiguity diagnostics for duplicate or conflicting entries
- No unclassified compatibility behavior baked into default output

Action items:
- [ ] `.hts` parsing via `hires_pack_common.py`
- [ ] PHRB record emission with all identity fields
- [ ] Ambiguity logging

**3b. Classified behavior** (~1-2 days, after Step 2.5)
- [ ] Wire in palette CRC behavior per classification gate
- [ ] Wire in LoadBlock dual-key emission per classification gate
- [ ] Handle CI multi-palette variants

**3c. Smoke test + converter test** (~0.5 day)
- [ ] Test on Paper Mario pack — output should reproduce current hit rates
- [ ] Test on a second game's pack (OoT, MM, SM64) — zero-config
- [ ] Ensure converter runs in under 60 seconds for typical pack sizes (~2GB)
- [ ] Round-trip test: legacy entry → PHRB record → load → verify key fields

**Success criteria:** `hts2phrb pack.hts -o pack.phrb` works for any game's pack,
and the output records carry structured identity ready for future runtime upgrades.

---

## Step 4: Validate Within Paper Mario

Before going cross-game, validate within Paper Mario beyond menu screens. The
non-menu fixture and evidence harness are already set up from Phase 0.

### Validation requirements:
- [ ] Run converted PHRB against title, file-select, AND `hos_05` fixtures
- [ ] Verify hit rates match or exceed legacy `.hts` across all three
- [ ] Class-based assertions pass (texrect, block, CI/TLUT cases)
- [ ] Semantic evidence assertions pass (from Phase 0 harness)
- [ ] PHRB output matches legacy `.hts` hit rates on the non-menu fixture

### Negative data requirement:
- [ ] Record at least one intentionally rejected fallback or unresolved family as
      explicit negative data. The test suite must prove it can say "no" as well as
      "yes."

**Success criteria:** Non-menu Paper Mario scene passes with converted PHRB.
Semantic evidence participates in gating. At least one negative case is documented.

---

## Step 5: Make PHRB the Default Runtime Path

**After** the converter is proven on Paper Mario menu + non-menu scenes:

- [ ] Make `.phrb` the default runtime format
- [ ] Add auto-conversion: if user provides `.hts`, convert to `.phrb` on first load
      and cache the result (like GlideN64's `.htc` compilation)
- [ ] Keep direct `.hts` loading as a development/debug fallback
- [ ] Remove debug env var gates — the improved lookup should be the default
- [ ] Document the user-facing workflow: drop pack in system dir, enable hi-res, play

### Compatibility fencing:
- [ ] Any behavior classified as "bounded compatibility helper" at Step 2.5 must
      live behind an explicit runtime mode flag, not in the default path
- [ ] Compatibility behavior must be disableable without changing native PHRB semantics
- [ ] Native package success on active fixtures must not depend on implicit
      compatibility broadening

### Tests (written alongside this step):
- [ ] Provider lookup: exact hit, miss, CI fallback
- [ ] Compatibility alias fencing: compat behavior does not fire when disabled
- [ ] Auto-conversion: `.hts` input → cached `.phrb` → correct lookup

**Success criteria:** Zero-configuration hi-res for Paper Mario with legacy pack.
Compatibility behavior, if any, is cleanly fenced. Provider tests pass.

---

## Step 6: Validate on a Second Game

**Problem:** All current validation is Paper Mario only. Need proof of generality.

### Requirements:
- [ ] Pick a second game with a well-known Rice-format hi-res pack
      (Zelda OoT or Mario 64 are good candidates — large community packs exist)
- [ ] The second game must exercise a **materially different runtime class profile**
      than Paper Mario — not just another texrect/UI-heavy scene. Look for games
      with heavy 3D texture use, multi-tile composites, or different CI/TLUT patterns.
- [ ] Build a minimal fixture (savestate + scenario) for one representative scene
- [ ] Run with auto-converted PHRB and the fixed lookup
- [ ] Compare hit rate against GlideN64 on the same scene
- [ ] Document any new miss classes that don't appear in Paper Mario
- [ ] Explicitly validate that LoadBlock reinterpretation does not produce false
      positives in the second game's texture traffic

### Gate:
The second game must work without adding new core runtime key rules. If it requires
game-specific logic, the converter or runtime has a gap that needs fixing
generically, not per-game.

**What "no per-game policy" means in practice:** The converter's zero-config path
must handle the second game. If ambiguous cases exist that the basic path cannot
resolve, those must be handled through the `--policy` enrichment flag — not by
adding game detection to the core converter or runtime. The `--policy` path is an
escape hatch for edge cases, not a requirement for normal operation.

**Success criteria:** Second game achieves comparable hit rate to GlideN64 with
zero game-specific tooling. The generic converter handles it with no new rules.

---

## Step 7: Structured Sampled-Object Key Decision

After Steps 1-6, the runtime has working `checksum64 + formatsize` lookup with
corrected CRCs, a generic converter, and cross-game validation. Now decide whether
to redesign the provider lookup to use structured sampled-object keys.

### Decision inputs:
- What miss classes remain after CRC fixes and LoadBlock reinterpretation?
- Do any remaining misses require identity fields beyond `checksum64 + formatsize`?
- Does ROM-scan enrichment (filling in `tile`, `tmem`, `line`, `tlut_type`) resolve
  cases that the CRC-based path cannot?
- Is the remaining miss rate low enough that structured keys are an optimization
  rather than a necessity?

### If structured keys are needed:
- Redesign the provider lookup (Codex's Phase A) using the identity fields already
  carried in PHRB records — `fmt`, `siz`, `tile`, `tmem`, `line`, `logical size`,
  palette identity, `tlut_type`
- The converter already emits these fields (zero-defaulted when unknown), so no
  re-conversion is needed
- Step 2.75 already preserves these fields in the in-memory `Entry` struct, so
  the provider has the data — it just needs a new index path
- Build the ROM-scan enrichment path (`hts2phrb --rom game.z64`) to populate
  the currently-unknown fields
- Preserve `checksum64 + formatsize` as a compatibility fallback for records that
  lack structured fields

### Delivery rule: measurable slices, not big-bang rewrite
If the provider redesign proceeds, it must land in incremental slices where each
slice preserves or improves active fixture results. No slice should break existing
hit rates or require the next slice to become testable. Good early slices:
- Separate native records from compatibility aliases in provider internals
- Add provider/package tests before widening runtime lookup coverage
- Widen primary structured lookup only after the prior slices are stable and tested

### If structured keys are not needed:
- Document why the CRC-based path is sufficient
- Keep the structured fields in PHRB records for future use
- Close this step with a written decision

### Other possible enhancements:
- **Native pack authoring**: Future pack creators could author directly against
  sampled-object identity for perfect LLE alignment. The PHRB format already
  supports this — it just needs documentation and tooling.
- **Performance**: PHRB's sorted numeric keys enable binary search at runtime,
  avoiding the Rice CRC computation on every draw call. This matters for
  performance-sensitive scenarios.

---

## What to Keep from Current Work

- **PHRB binary format** — becomes the runtime standard
- **Fixture/scenario framework** — essential for regression testing
- **Evidence bundle infrastructure** — useful for debugging new games
- **Rice CRC implementation** — already correct for textures
- **Renderer integration** — clean descriptor-indexed replacement path
- **`hires_pack_common.py`** — core parsing, reused by converter
- **Sampled-object identity model** — future ROM-scan enrichment path

## What to Deprioritize

- **38 of the 39 Python tools** — replace with single `hts2phrb` converter
- **Per-family transport policy** — manual curation doesn't scale
- **Surface package ordered-slot model** — over-engineered for the current problem
- **Paper Mario decomp-backed static scans** — useful research but not the fix path
- **Per-low32 import policies** — converter should handle this automatically
- **Proxy/bridge binding machinery** — unnecessary with correct CRC computation

## What to Revive from the Failed Attempt

- Replacement-provider parser/decode/lookup tests
- Selected offline comparison and provenance tooling

## What NOT to Revive

- Runtime lookup-mode matrix
- Ownership and consumer policy explosion
- Frontend-exposed heuristic controls as product features
- Permissive reinterpretation as the normal path

---

## Decision Gates

The project should not declare the runtime ready until all of:

1. PHRB is the default runtime format with auto-conversion from `.hts`
2. Palette CRC behavior is classified and integrated per the gate at Step 2.5
3. LoadBlock reinterpretation is classified and integrated per the gate at Step 2.5
4. One non-menu Paper Mario fixture passes with converted PHRB
5. Semantic hi-res evidence participates in pass/fail gating
6. One second game works without game-specific rules, exercising a different
   runtime class profile than Paper Mario
7. Direct provider/package/converter tests exist (written alongside each step)
8. Compatibility behavior (if any) is explicitly fenced behind a mode flag
9. At least one unresolved or rejected case is documented as negative data
10. The Step 7 structured-key decision is recorded with supporting evidence
11. If auto-conversion is enabled, it is covered by direct tests and does not
    change native package semantics

---

## Risk Mitigations

### If the palette CRC fix is partial (60-65% instead of 85%+):
The classification gate at Step 2.5 catches this. Do not spiral into per-case
debugging. Log the remaining misses by class, determine if `tlut_shadow` diverges
from `TexFilterPalette` for structural reasons (timing, partial TMEM updates,
multi-frame palette cycling), and classify accordingly. A partial fix that's a
native identity fact is still worth shipping — the remaining gap may require
structured keys (Step 7) rather than more CRC patching.

### If "no per-game policy" breaks on the second game:
This is a strong claim. Real packs have per-game quirks (duplicate Rice CRCs,
game-specific TLUT cycling). If the second game requires policy, the escape hatch
is the `--policy` enrichment flag — not new core runtime rules. If even the
enrichment flag is insufficient, that's a signal that the converter design needs
broadening, and the right response is to fix the converter generically.

### If LoadBlock reinterpretation produces false positives at scale:
The retry-on-miss design limits exposure, but games with heavy LoadBlock traffic
could surface collisions. Step 6 must explicitly test for this. If false positives
appear, the reinterpretation gets classified as a bounded compat helper (behind a
flag) rather than a native fact.

---

## Open Questions

1. **Does `tlut_shadow` actually contain different bytes than `TexFilterPalette`?**
   Step 1 will answer this definitively. If the bytes match, the palette CRC fix is
   trivial. If they don't, we need to understand exactly why.

2. **Are there games where LoadBlock reinterpretation produces false positives?**
   Step 2 should validate this on Paper Mario, Step 6 on a second game. The
   reinterpretation only fires on misses, so false positives would require a
   different texture with the same reinterpreted CRC.

3. **Is there a class of textures where neither Rice CRC nor reinterpretation works?**
   Copy-mode draws, framebuffer-derived textures, and procedurally generated content
   may fall into this category. These should be explicitly excluded from replacement
   rather than guessed at.

4. **Can auto-conversion at first load be fast enough?**
   A 2GB `.hts` pack needs to be parsed, CRC-corrected, and written as `.phrb` in
   a reasonable time. If this takes minutes, it should be a one-time operation with
   the result cached. If it takes seconds, it can happen transparently.

5. **What percentage of real packs have entries that genuinely need per-game policy?**
   If it's <5%, the generic converter is vindicated. If it's >15%, the `--policy`
   enrichment path becomes load-bearing and needs more design attention.
