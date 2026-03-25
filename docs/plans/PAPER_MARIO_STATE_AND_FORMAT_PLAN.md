# Paper Mario State And Format Plan

## Purpose

- Use the new Paper Mario reference set to stop doing blind menu probing
- Turn the current file-select branch evidence into a reliable path toward deeper authoritative states
- Feed that better state coverage back into the hi-res format decision, so the format is built on broader and more trustworthy evidence

## Why This Plan Exists

We now have three distinct kinds of evidence:

- runtime bundle evidence from `parallel-n64`
- behavior and state-machine evidence from `papermario-dx`
- a new upstream vanilla Paper Mario reference checkout at `/home/auro/code/paper_mario/papermario`

That changes the right path forward.

Before this, it was too easy to:

- over-trust `entryID` or other coarse runtime signals
- over-trust `papermario-dx` addresses as if they were vanilla ROM addresses
- keep probing buttons without a good state model

Now we can do something better:

- use DX for behavior and code-shape understanding
- use upstream Paper Mario for vanilla comparison
- use runtime bundles as the authority for what actually happened in this emulator/core path

## Core Findings To Build On

### 1. The file-select branch ladder is real and deterministic

Current branch ladder from the savefile-backed file-select authority:

- `START x120` -> `89cb1bddd5c2dd2a62b063210af11c2324eca04d3060e746042edc0323b00e8e`
- `START x120 -> A` -> `674bbf51ab0c985d16088aedd373d2bd7d3d8fdc5f1e12020858f322e7073732`
- `START x120 -> A -> A` -> `fece26f3ac694b9cbf9c395c10a4cb0543499cdc8eb2aa9beaacb896c2acd1ad`
- `START x120 -> A -> START` -> `fece26f3ac694b9cbf9c395c10a4cb0543499cdc8eb2aa9beaacb896c2acd1ad`
- `START x120 -> START -> START` -> `86d3d0a9f7db600bdc0f0f4b8ec29d9c7ff1418a7e7c7ac346dc9a710c2dd3a7`

That ladder is useful even though it still stays inside `state_init_file_select` / `state_step_file_select`.

### 2. `entryID=11` is not a trustworthy world-entry signal here

The decomp evidence strongly suggests file-select save scanning can populate map/entry fields without leaving `GAME_MODE_FILE_SELECT`.

That means:

- `entryID`
- `areaID`
- `mapID`

must not be treated as proof of world entry on this branch without stronger supporting evidence.

### 3. DX addresses are useful but not authoritative for vanilla ROM memory layout

The first filemenu panel snapshot attempt was valuable as a negative result:

- the DX-derived panel addresses do not line up cleanly with the vanilla ROM in our current runtime path
- those panel snapshots are now correctly marked non-authoritative in bundle output

This is a good correction. It means the next path should be:

- derive or verify vanilla-relevant symbols
- then trust them

not:

- trust DX relocation blindly

### 4. The file-select authority and the deeper branch are different states

A no-input settle from the authoritative file-select state back to `frame=423` reproduces the canonical file-select hash, not the deeper `89cb1b...` branch.

That proves:

- the deeper branch is input-caused
- it is not just an idle-delay artifact

## Strategy

This plan has four workstreams that should feed each other in order.

### Workstream A: Reference Triangulation

Goal:
- build a trustworthy Paper Mario state model that distinguishes vanilla behavior from DX-specific layout

Inputs:
- `/home/auro/code/paper_mario/papermario`
- `/home/auro/code/paper_mario/papermario-dx`
- current runtime bundles

Required work:
- compare upstream and DX file-select logic side by side
- identify which findings are behavior-only and which depend on symbol/layout assumptions
- build a short “safe-to-use runtime signals” list and a “not-safe-yet” list

Expected outputs:
- a list of trusted runtime predicates
- a list of DX-only helpers
- a list of symbol/address candidates that still need vanilla verification

Exit signal:
- we can say which Paper Mario signals are authoritative, which are advisory, and which are currently unsafe

Current output:
- the first version of that table now lives in [PAPER_MARIO_SIGNAL_TABLE.md](/home/auro/code/parallel-n64/docs/plans/PAPER_MARIO_SIGNAL_TABLE.md)
- current best vanilla-safe signals are the `CurGameMode` callback pair, `filemenu_menus`, and `filemenu_currentMenu`
- panel snapshots are now live when derived through `filemenu_menus`; only the old fixed DX-style panel addresses remain retired

### Workstream B: Vanilla-Safe State Discovery

Goal:
- replace coarse or misleading state guesses with stronger state evidence

Required work:
- look for trustworthy vanilla symbol sources or reconstruct them from upstream artifacts
- prefer state signals that survive vanilla/DX comparison
- extend bundle semantic output only when a signal is verified against the vanilla reference path

Priority targets:
- file-select substate / confirm state
- actual transition into `GAME_MODE_END_FILE_SELECT`
- actual transition into `GAME_MODE_ENTER_WORLD` / `GAME_MODE_WORLD`

Rules:
- do not promote a signal into bundle semantics just because it exists in DX
- if a signal cannot be validated against vanilla, keep it explicitly non-authoritative

Exit signal:
- at least one deeper branch has a stronger state interpretation than “still file select, unknown substate”

### Workstream C: Authority Minting Beyond File Select

Goal:
- turn the deterministic branch ladder into at least one deeper authoritative state outside the current menu neighborhood

Required work:
- use the current ladder as a bounded search tree, not an open-ended input playground
- search serially and intentionally from the existing branch nodes
- prefer branch points that are behavior-backed by decomp logic
- when a deeper state is found, mint it immediately as a new authority fixture

Search order:
1. authoritative file-select state
2. `START x120` branch
3. `START x120 -> A` branch
4. `START x120 -> A -> A` / `A -> START` branch
5. only then widen search if none of those exit file select

Authority rule:
- once a target branch is visually and semantically stable, mint a state so the canonical workflow stays `load -> settle 3 -> capture`

Exit signal:
- at least one non-file-select authority exists and reloads reproducibly

### Workstream D: Feed Format Confidence

Goal:
- use the improved Paper Mario state coverage to decide the hi-res format on stronger evidence

Required work:
- rerun hi-res family capture on any newly minted deeper authority
- compare CI and non-CI family breadth against the current file-select-heavy set
- update the import-review artifacts with deeper-state families
- only then revisit format hardening decisions

Expected outputs:
- broader family coverage
- less menu-overfit format evidence
- better confidence about what belongs in exact identity versus explicit compatibility/import policy

Exit signal:
- the hi-res format work is no longer anchored primarily to one file-select neighborhood

## Immediate Execution Order

### Step 1: Build The Vanilla-Safe Signal Table

Do next:

- compare upstream `papermario` and `papermario-dx` file-select logic
- write down which runtime signals are safe, unsafe, or unresolved

Why first:
- it reduces wasted probing immediately

### Step 2: Find One Stronger File-Select Substate Signal

Do next:

- identify one state signal that can distinguish:
  - file-select main menu
  - confirm menu
  - post-confirm transition
- use [paper-mario-file-select-signal-sweep.sh](/home/auro/code/parallel-n64/tools/scenarios/paper-mario-file-select-signal-sweep.sh) for bounded settle sweeps before inventing new one-off probe paths

Why second:
- one good signal is better than ten more screenshots

### Step 3: Use The Existing Branch Ladder As A Bounded Search

Do next:

- continue from the current branch nodes rather than inventing new long startup paths
- mint any stable deeper state as soon as it is found

Why third:
- it keeps the workflow deterministic and avoids losing the current known-good ladder

### Step 4: Re-run Hi-Res Family Capture On The First New Authority

Do next:

- once a deeper authority exists, run the same strict hi-res evidence program there

Why fourth:
- that is the first real test of whether the format/import model is menu-overfit

## Decision Gates

### Gate 1: Stop Trusting Bad Signals

Before adding new runtime semantics:

- signal must be verified against upstream or another vanilla-safe source
- or it must be clearly labeled non-authoritative

### Gate 2: Mint State Early

Before doing broad new probing:

- if a branch is stable enough to reload, mint it

This keeps the main workflow deterministic.

### Gate 3: No Format Commitment From Menu-Only Evidence

Before hardening the new hi-res format:

- at least one deeper non-file-select authority must exist
- and it must contribute real family evidence

### Gate 4: Keep Compatibility Explicit

Even with new state coverage:

- exact identity remains tier 1
- compatibility remains explicit and reviewable
- unresolved legacy ambiguity remains import-time or policy-layer data, not hidden runtime guessing

## Non-Goals

- Do not keep adding DX-derived addresses to runtime bundles unless they are clearly marked and justified.
- Do not widen runtime heuristics just because deeper states are harder to reach.
- Do not let Paper Mario state discovery turn into a separate open-ended project detached from hi-res format confidence.

## Success Condition

This plan has succeeded when:

- we have at least one deeper authoritative Paper Mario state outside the current file-select neighborhood
- we have a better vanilla-safe state model than `entryID`-based guessing
- we have new hi-res family evidence from that deeper state
- the format decision is grounded in broader and more trustworthy ParaLLEl evidence than before
