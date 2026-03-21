# Phase 2: Scaling And Sharpness

## Objective

- Make hi-res replacement scale sharply and consistently while keeping the result as close as practical to stable N64 behavior

## Preconditions

- Phase 1 replacement path is stable on its first strict targets
- evidence bundles can distinguish replacement issues from scaling issues
- fallback and exclusion reporting is already in place

## Required Rules

- do not blur scaling logic into replacement identity logic
- treat texrect behavior, CI/TLUT interactions, and VI interaction as high-risk areas
- add support by explicit proof, not by assumption

## Success Definition

- Phase 1 targets remain clean under scaling work
- scaling artifacts are not hand-waved as “unimplemented”
- sharper output is achieved without introducing corruption or ambiguous regressions

## Expansion Path

- once Paper Mario reaches a stable milestone, widen the validation matrix and revisit broader planning
