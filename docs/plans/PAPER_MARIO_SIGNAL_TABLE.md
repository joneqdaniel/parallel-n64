# Paper Mario Signal Table

## Purpose

- Define which Paper Mario runtime signals are currently safe to trust against the vanilla ROM.
- Separate authoritative state signals from advisory or unsafe ones.
- Give Phase 1 probing a tighter target than screenshot-only branch hunting.

## Evidence Basis

- Runtime bundles from `parallel-n64`
- Upstream vanilla reference: [papermario](/home/auro/code/paper_mario/papermario)
- Behavior reference: [papermario-dx](/home/auro/code/paper_mario/papermario-dx)

## Current Signal Classes

### Authoritative

- `CurGameMode` callback pair at `0x80151700`
  - Why: both upstream and DX agree on `state_init_file_select` / `state_step_file_select` symbol addresses in [symbol_addrs.txt](/home/auro/code/paper_mario/papermario/ver/us/symbol_addrs.txt) and [symbol_addrs.txt](/home/auro/code/paper_mario/papermario-dx/ver/us/symbol_addrs.txt).
  - Current use: this is the best vanilla-safe proof that the tracked deeper branches are still inside file-select.

- `filemenu_currentMenu` at `0x8024C098`
  - Why: upstream and DX agree on the symbol address in [symbol_addrs.txt](/home/auro/code/paper_mario/papermario/ver/us/symbol_addrs.txt) and [symbol_addrs.txt](/home/auro/code/paper_mario/papermario-dx/ver/us/symbol_addrs.txt).
  - Current use: this is a safe top-level discriminator between `FILE_MENU_MAIN`, `FILE_MENU_CONFIRM`, `FILE_MENU_MESSAGE`, and `FILE_MENU_INPUT_NAME`.
  - Current limitation: all tracked file-select probe branches still read `FILE_MENU_MAIN`, so this signal is safe but not yet sufficient.

- Fixture-relative frame and screenshot hash
  - Why: the Phase 0 runtime contract is now deterministic for these Paper Mario fixtures.
  - Current use: this is still the authoritative branch identity when deeper semantic signals are missing.

### Advisory

- `filemenu_pressedButtons` at `0x8024C084`
- `filemenu_heldButtons` at `0x8024C08C`
  - Why: upstream and DX agree on these addresses, and [filemenu_update()](/home/auro/code/paper_mario/papermario/src/filemenu/filemenu_common.c#L300) clearly writes them from `gGameStatusPtr`.
  - Limitation: they are sample-time sensitive and can legitimately be zero by the time a settled branch is captured.
  - Rule: use them for immediate input-delivery debugging, not for settled-state identity.

- `areaID`, `mapID`, `entryID` while `CurGameMode` still reports file-select callbacks
  - Why: upstream/DX file-select logic can populate save-derived map state before leaving file-select.
  - Rule: these are useful hints only after a stronger non-file-select signal exists.

### Unsafe / Non-Authoritative

- `filemenu_main_menuBP` snapshot at `0x80409158`
- `filemenu_yesno_menuBP` snapshot at `0x804091D0`
  - Why: these addresses are not currently backed by a trustworthy vanilla build artifact in the local references.
  - Runtime evidence: the sampled structs are zeroed in current bundles.
  - Rule: do not use these panel fields as evidence until they are derived or validated against a real vanilla symbol/build source.

## Current Verified Conclusions

- The tracked authoritative file-select fixture and all currently explored deeper branches still report:
  - `state_init_file_select`
  - `state_step_file_select`
  - `filemenu_currentMenu = FILE_MENU_MAIN`

- A no-input settle from the authoritative file-select state back to `frame=423` reproduces the canonical file-select hash:
  - `6fa8688b382fa1e6f0323f054861a85f593d2d47ca737bb78448e3f268ca63e3`

- Direct one-frame `START` or `A` from the authoritative file-select state do not act like no-ops.
  - With the current long settle, both collapse into the first deeper deterministic branch:
  - `89cb1bddd5c2dd2a62b063210af11c2324eca04d3060e746042edc0323b00e8e`

- The currently verified deterministic ladder is:
  - authority + no input -> `6fa8688b382fa1e6f0323f054861a85f593d2d47ca737bb78448e3f268ca63e3`
  - authority + `START` -> `89cb1bddd5c2dd2a62b063210af11c2324eca04d3060e746042edc0323b00e8e`
  - authority + `A` -> `89cb1bddd5c2dd2a62b063210af11c2324eca04d3060e746042edc0323b00e8e`
  - `89cb1b...` + `A` -> `674bbf51ab0c985d16088aedd373d2bd7d3d8fdc5f1e12020858f322e7073732`
  - `89cb1b...` + `A -> A` -> `fece26f3ac694b9cbf9c395c10a4cb0543499cdc8eb2aa9beaacb896c2acd1ad`
  - `89cb1b...` + `A -> START` -> `fece26f3ac694b9cbf9c395c10a4cb0543499cdc8eb2aa9beaacb896c2acd1ad`
  - `89cb1b...` + `START -> START` -> `86d3d0a9f7db600bdc0f0f4b8ec29d9c7ff1418a7e7c7ac346dc9a710c2dd3a7`

## What We Still Need

- A vanilla-safe signal that can distinguish:
  - `FM_MAIN_SELECT_FILE`
  - `FM_CONFIRM_START`
  - the actual exit from file-select

- A trustworthy vanilla source for `MenuPanel` globals, or a better replacement signal that makes direct panel snapshots unnecessary.

## Immediate Implication

- Keep using callback pairs, `filemenu_currentMenu`, frame, and screenshot hash as the current safe bundle semantics.
- Keep panel snapshots in the bundle only as explicitly non-authoritative research traces.
- Use the branch ladder as a bounded search tree until a stronger vanilla-safe substate signal is found.
