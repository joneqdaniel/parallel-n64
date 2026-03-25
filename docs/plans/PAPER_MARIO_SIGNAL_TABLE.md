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

- `filemenu_menus` at `0x80249B84`
  - Why: upstream and DX agree on the symbol address, and it gives us a vanilla-safe pointer source for the live `MenuPanel` structs.
  - Current use: the tracked runtime path now dereferences `[FILE_MENU_MAIN]` and `[FILE_MENU_CONFIRM]` through this array instead of relying on guessed fixed addresses.

- Pointer-derived `main_panel` / `confirm_panel` snapshots
  - Why: these snapshots now resolve through `filemenu_menus` and produce live nonzero structs in the runtime bundles.
  - Current safe fields:
    - `main_panel.state`
    - `main_panel.selected`
    - `confirm_panel.selected`
  - Current safe derived predicate:
    - `exit_mode_guess`, mirroring vanilla `filemenu_get_exit_mode()`

### Advisory

- `filemenu_pressedButtons` at `0x8024C084`
- `filemenu_heldButtons` at `0x8024C08C`
  - Why: upstream and DX agree on these addresses, and [filemenu_update()](/home/auro/code/paper_mario/papermario/src/filemenu/filemenu_common.c#L300) clearly writes them from `gGameStatusPtr`.
  - Limitation: they are sample-time sensitive and can legitimately be zero by the time a settled branch is captured.
  - Rule: use them for immediate input-delivery debugging, not for settled-state identity.

- `gWindows` file-select window snapshots at `0x80159D50 + windowID * 0x20`
  - Current tracked windows:
    - `WIN_FILES_TITLE = 45`
    - `WIN_FILES_CONFIRM_PROMPT = 46`
    - `WIN_FILES_CONFIRM_OPTIONS = 50`
    - `WIN_FILES_SLOT2_BODY = 57`
  - Why: upstream vanilla window layout and window IDs are stable, and file-select logic uses `set_window_update()` on these windows during branch transitions.
  - Current useful fields:
    - `fp_update`
    - `fp_pending`
    - `flag_names`
    - `update_counter`
  - Current proven signal:
    - the first deeper `authority + A` branch flips `WIN_FILES_TITLE` and `WIN_FILES_SLOT2_BODY` from their authority-state update callbacks onto `filemenu_update_hidden_with_rotation`, while the filemenu panel globals stay unchanged
  - Rule: treat these as the strongest current advisory discriminator for the hidden branch, but not yet as proof of an actual exit from file select.

- `areaID`, `mapID`, `entryID` while `CurGameMode` still reports file-select callbacks
  - Why: upstream/DX file-select logic can populate save-derived map state before leaving file-select.
  - Rule: these are useful hints only after a stronger non-file-select signal exists.

### Unsafe / Non-Authoritative

- Direct hard-coded `filemenu_main_menuBP` / `filemenu_yesno_menuBP` addresses
  - Why: those fixed addresses are not backed by a trustworthy vanilla build artifact in the local references.
  - Rule: do not reintroduce fixed panel-address snapshots; always go through `filemenu_menus`.

## Current Verified Conclusions

- The tracked authoritative file-select fixture and all currently explored deeper branches still report:
  - `state_init_file_select`
  - `state_step_file_select`
  - `filemenu_currentMenu = FILE_MENU_MAIN`

- The current authoritative file-select state now decodes cleanly through `filemenu_menus` as:
  - `main_panel.state = FM_MAIN_SELECT_FILE`
  - `main_panel.selected = FM_MAIN_OPT_FILE_2`
  - `confirm_panel.selected = NO`
  - `exit_mode_guess = selected_file`

- The first deeper `authority + A` branch currently decodes to the same top-level file-select predicates as the authority state.
  - That means the current safe signals still do not distinguish that deeper visual branch from the steady-state authority.

- A bounded `A` settle sweep across `1`, `2`, `3`, `5`, `10`, and `20` frames stays on that same decoded top-level state for every sample.
  - Immediate implication: the missing discriminator is probably not “the same panel fields but sampled slightly earlier” within that small window.

- A bounded one-frame button sweep across `A`, `B`, `START`, `UP`, `DOWN`, `LEFT`, and `RIGHT` also stays on that same decoded top-level state.
- `A` and `START` with `post-input-settle = 0` still stay on that same decoded top-level state.
  - Immediate implication: the next useful discriminator lives outside the current filemenu globals.

- Window-side state now gives that stronger discriminator.
  - Authority state:
    - `WIN_FILES_TITLE.fp_update = filemenu_update_show_title`
    - `WIN_FILES_SLOT2_BODY.fp_update = filemenu_update_show_options_right`
  - Immediate `authority + A` branch, sampled at settles `0`, `1`, `2`, `3`, `5`, `10`, and `20`:
    - `WIN_FILES_TITLE.fp_update = filemenu_update_hidden_with_rotation`
    - `WIN_FILES_SLOT2_BODY.fp_update = filemenu_update_hidden_with_rotation`
  - `WIN_FILES_CONFIRM_OPTIONS` stays on `WINDOW_UPDATE_HIDE` across that same sweep.
  - So the hidden branch is now distinguishable in a vanilla-safe way, even though it still remains inside `state_init_file_select` / `state_step_file_select` and keeps the same top-level filemenu panel predicates.

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
- Keep panel snapshots in the bundle as advisory research traces.
- Keep the `gWindows` file-select snapshots in the bundle as the current strongest branch discriminator short of an actual mode/menu transition.
- Use the branch ladder as a bounded search tree until a stronger vanilla-safe substate signal is found.
