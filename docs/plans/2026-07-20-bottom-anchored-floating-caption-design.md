---
title: Bottom-Anchored Floating Caption Design
status: approved
date: 2026-07-20
---

# Bottom-Anchored Floating Caption Design

## Context

Kineto's active-capture caption overlay is one nonactivating `NSPanel`. Pet Mode is optional, default-off, and must remain a decorative, state-only companion inside that panel. The caption body remains passive; only the visible header and visible pet may drag the same panel.

## Decision

Retain the existing AppKit/SwiftUI surface and presentation flow. Recompose the panel vertically:

1. Draggable capture header.
2. Optional visible pet region above the transcript.
3. Fixed, passive, bottom-aligned transcript region.

The pet is conditionally composed only when visible. When Pet Mode is off, it has no reserved space, accessibility element, hit target, window, placement, or persisted state.

## Transcript Semantics

- When a nonempty volatile transcript exists, choose the deterministic newest volatile group by the existing time/identity tie-breaker and reserve one of four slots for it.
- Fill up to three remaining slots with the newest other eligible groups; render those inactive groups oldest-to-newest, then render the active volatile group last. A later finalized group cannot displace it.
- When no volatile transcript exists, select up to four newest finalized/history groups and render them oldest-to-newest with no active row.
- Original source text remains before its translation; translations remain subordinate and attached to their finalized source segment.
- The active row receives larger semantic text, active accent, and explicit `Live` status; older rows retain the existing subdued hierarchy.

## Boundaries

`AppModel` remains the owner of live/final transcript and translation state. `FloatingCaptionPresentation` deterministically selects, orders, and identifies the active row. `FloatingCaptionView` only renders that supplied snapshot. `FloatingCaptionPanelCoordinator` remains sole owner of panel lifecycle, nonactivation, sizing, placement, drag transactions, clamping, persistence, and reset.

`FloatingCaptionPetView` continues to receive only `FloatingCaptionPetState` and the existing panel-drag callbacks. It must not receive transcript, translation, source, audio, identity, sentiment, or capture-model data.

## Rejected Alternatives

- A second pet panel, independent surface, focus target, or persisted geometry.
- Scroll views, auto-scroll, `List`, local transcript caches, or additional update timers.
- Gestures on transcript rows, the caption body, or the root layout.
- Content-driven pet behavior or pet-specific transcript access.
- Treating the latest finalized caption as active when no volatile caption exists.

## Acceptance Criteria

- Pet Mode off leaves no visual gap or invisible interaction region; header drag remains available.
- Pet Mode on places the visible pet above—not beside—the transcript; pet and header move the same panel.
- At most four complete source-row groups appear: inactive groups are oldest-to-newest, then the active volatile group is bottom-most when present.
- Exactly one volatile row, when present, is visually active and bottom-most; without volatility, no final row is active.
- Source text wraps without horizontal scrolling; translations remain attached to their source rows.
- Caption rows remain passive and non-focusable; VoiceOver reads header then chronological combined row descriptions.
- Reduce Motion disables pet/layout motion; Increase Contrast and light/dark appearance preserve active-state clarity without color or font size alone.
- Panel stays nonactivating, clamps across displays, resets from the menu bar, and remains normally visible in screenshots and screen sharing.

## Next

Create an implementation plan limited to the presentation projection, vertical SwiftUI composition, focused contract tests, and real-device overlay validation. No second surface, new framework, or persistence path is in scope.
