---
phase: 2
title: Minimal subtitle bar
status: completed
priority: P2
dependencies:
  - 1
---

# Phase 2: Minimal subtitle bar

## Overview

Replace the current card-like caption treatment with a compact minimal subtitle bar while retaining the approved four-row presentation semantics and the header's accessible drag fallback.

## Requirements

- Functional: render all supplied rows in presentation order—chronological inactive history followed by the active volatile `Live` row—without local selection, sorting, scrolling, or gesture handling on transcript content.
- Functional: keep each original source caption immediately before its optional translation.
- Visual: use a tighter translucent horizontal bar, reduced corner radius, restrained border, compact capture-status header, and stronger active-row contrast. Keep the visible companion visually separate above it.
- Accessibility: preserve the header label/hint and combined line descriptions; retain explicit live text and non-color state differentiation; honor Reduce Motion and system appearance.

## Related Code Files

- Modify: `KinetoApp/UI/FloatingCaption/FloatingCaptionView.swift`
- Modify: `docs/design-guidelines.md` only for the changed subtitle-bar visual contract.
- Modify: `docs/project-overview-pdr.md` only if its caption composition wording changes materially.

## Implementation Steps

1. Retain `FloatingCaptionView`'s supplied `presentation`, width, header callbacks, and passive line list.
2. Rework outer spacing, padding, material, border, and corner treatment into a low-profile subtitle bar; do not introduce another container or persistent geometry.
3. Make the header compact and visually subordinate while retaining capture state, accessible move label, and header-drag callback.
4. Tune inactive and active line typography/spacing so four rows remain readable: history subdued, active last line clearly marked and mint-accented, translations secondary.
5. Verify no hit testing reaches transcript rows and Pet Mode state still determines companion visibility outside this view.

## Success Criteria

- [ ] The panel reads as a minimal subtitle bar, not a large generic card.
- [ ] Four-row bounded transcript semantics, active-last ordering, and translation association remain unchanged.
- [ ] The header remains an accessible fallback move handle; transcript content stays passive.
- [ ] Layout stays legible with wrapping, large text, dark/light appearance, and Increase Contrast.

## Risk Assessment

| Risk | Mitigation |
|---|---|
| Styling hides live state | Keep text `Live`, type hierarchy, and mint accent; do not rely on color alone. |
| Compact treatment harms long captions | Preserve wrapping and fixed vertical sizing; avoid truncation and horizontal scrolling. |
| New visual gesture leaks to body | Restrict all gesture code to the existing header and external visible companion. |
