---
title: "Bottom-anchored floating caption"
description: "Approved plan for a single, bottom-anchored active-capture caption panel with a passive four-row transcript and an optional decorative Pet Mode."
status: pending
priority: P2
branch: "main"
tags: [caption-overlay, appkit, swiftui, accessibility, pet-mode]
blockedBy: []
blocks: []
created: "2026-07-20T07:20:14.477Z"
createdBy: "ck:plan"
source: skill
---

# Bottom-anchored floating caption

## Overview

### Approved objective

Refine Kineto's existing active-capture caption overlay into one vertically composed, nonactivating `NSPanel`: a draggable capture header, an optional visible Pet Mode region, and a fixed passive transcript anchored at the panel bottom. When a nonempty volatile transcript exists, choose the deterministic newest volatile group by the established `(endTime, identity)` tie-breaker, reserve one of four group slots for it, select up to three newest remaining eligible groups, render those inactive retained groups oldest-to-newest, and render the active group last. With no volatile transcript, select up to four newest finalized/history groups and render them oldest-to-newest. A translation remains attached to its finalized source group and never consumes a separate slot.

### Non-goals

- Do not add a second panel, window, surface, framework, persistence path, transcript cache, timer, scrolling container, or focus target.
- Do not give Pet Mode transcript, translation, source, audio, identity, sentiment, or capture-model access. Pet Mode remains default-off, panel-local, state-only, and decorative except for dragging the visible panel.
- Do not add transcript-row, caption-body, or root-layout gestures; caption content remains passive, nonfocusable, and non-scrollable.
- Do not alter coordinator ownership of lifecycle, nonactivation, sizing, placement, clamping, reset, or panel-only persistence.
- Do not treat a finalized caption as live when no volatile caption is retained.

## Requirements

### State and presentation boundaries

- `AppModel` remains the single owner of live/final transcript and translation state.
- `FloatingCaptionPresentation` is a deterministic projection: it first selects the sole active nonempty volatile group when present, reserves its slot, selects the remaining eligible complete source-row groups deterministically, attaches optional translations to finalized source rows, and emits inactive groups chronologically with the active group last.
- `FloatingCaptionView` renders only the supplied presentation snapshot. It does not select, cache, infer, or mutate transcript state.
- `FloatingCaptionPanelCoordinator` remains the sole owner of the one `NSPanel` and its lifecycle, nonactivation, dimensions, placement, display clamping, drag transaction, reset, and panel-only persistence.
- `FloatingCaptionPetView` receives only `FloatingCaptionPetState` plus the existing panel-drag callbacks; its presence is conditional on visible state.

### Global invariants

- The overlay is always the existing one nonactivating active-capture `NSPanel`; there is no second pet surface or independent geometry.
- When Pet Mode is off, it reserves no space and exposes no visual, accessibility, or interaction region. When shown, the pet is above—not beside—the transcript and can drag the same panel as the header.
- A retained group consists of original source text followed by its optional translation. Groups are never split.
- When a nonempty volatile transcript exists, select the deterministic newest volatile group by `(endTime, identity)` before choosing any other group; reserve its slot, select up to three newest remaining eligible groups, render those inactive retained groups oldest-to-newest, then render the active group last. A later finalized group cannot displace the active group from the bottom.
- Without a volatile transcript, select up to four newest finalized/history groups by `(endTime, identity)` and render them oldest-to-newest. No more than four complete source-row groups render; `activeLineID` is absent in this fallback.
- Caption content cannot focus, activate, scroll, or drag. Source wrapping has no horizontal scrolling.
- VoiceOver reads the header before combined row descriptions in rendered display order: chronological inactive groups followed by the active group when present. Reduce Motion, Increase Contrast, and light/dark appearance preserve the live-state distinction without relying on color or size alone.

## Dependencies

- **Required design reference:** [`docs/plans/2026-07-20-bottom-anchored-floating-caption-design.md`](../../docs/plans/2026-07-20-bottom-anchored-floating-caption-design.md) is approved and defines the product boundary this plan implements.
- **Cross-plan dependencies:** None. This plan has an explicit no-cross-plan block; its phases depend only on their stated ordering and the approved design reference.

## Architecture

### High-level data flow

```text
AppModel
  ├─ finalized segments + translations
  ├─ volatile transcripts
  └─ Pet Mode preference/state
          │
          ▼
FloatingCaptionPresentation
  ├─ choose the deterministic active volatile group first, when one exists
  ├─ reserve its slot; select up to three newest remaining groups, or four finalized/history groups when no volatile exists
  ├─ attach translations to finalized sources; render inactive groups oldest → newest, then active last
  └─ emit lines, activeLineID, header, and panel-local pet state
          │
          ▼
FloatingCaptionPanelCoordinator ── owns one nonactivating NSPanel
          │                                │
          │                                ├─ size/place/clamp/reset/persist panel only
          ▼                                └─ shared drag transaction
FloatingCaptionView
  ├─ draggable header
  ├─ conditional FloatingCaptionPetView (state + drag callbacks only)
  └─ fixed passive bottom transcript
```

The projection is intentionally one-way: model state enters the presentation contract, and the view renders it. Panel drag callbacks return only to the coordinator; neither the pet nor transcript obtains capture data or creates a presentation/persistence path.

## Related Code Files

- `KinetoApp/App/AppModel.swift` — continues to own capture, finalized transcript, translation, and preference inputs.
- `KinetoApp/UI/FloatingCaption/FloatingCaptionPresentation.swift` — presentation projection, bounded active-slot selection, inactive chronological and active-last ordering, translation association, active-row semantics, and panel-local pet state.
- `KinetoApp/UI/FloatingCaption/FloatingCaptionView.swift` — vertical composition and passive transcript rendering.
- `KinetoApp/UI/FloatingCaption/FloatingCaptionPetView.swift` — visible-only decorative pet and shared panel-drag affordance.
- `KinetoApp/UI/FloatingCaption/FloatingCaptionPanelCoordinator.swift` — single-panel lifecycle and geometry ownership.
- `KinetoTests/FloatingCaptionPresentationTests.swift` — deterministic presentation-contract coverage.

## Implementation Steps

### Phase 1 — [Presentation contract](./phase-01-presentation-contract.md)

Establish the deterministic presentation boundary before changing layout. When a volatile transcript exists, select its deterministic newest group first, reserve one of four slots for it, select up to three newest remaining groups, then render the inactive groups chronologically before the active bottom row; otherwise select four newest finalized/history groups and render them chronologically. Keep source-before-translation association, Pet Mode as a state-only field with no capture-data inputs, and existing coordinator ownership without introducing any surface or persistence path.

### Phase 2 — [Vertical layout and accessibility](./phase-02-vertical-layout-and-accessibility.md)

Compose the existing panel content vertically: draggable header, visible-only pet region, then a fixed bottom-aligned passive transcript. Make the active row visually and semantically clear while preserving subdued historical rows, source wrapping, passive hit testing, VoiceOver order, appearance contrast, and Reduce Motion behavior. Ensure header and visible pet dispatch the same panel drag callbacks.

### Phase 3 — [Verification](./phase-03-verification.md)

Verify the deterministic presentation contract with focused automated tests, then perform required real-device overlay validation. The automated suite establishes selection, ordering, association, active-row, and state-boundary behavior; it cannot prove AppKit nonactivation, multi-display clamping, screen-sharing visibility, or assistive-technology interaction, which require device-level observation.

## Success Criteria

- [ ] Active capture presents through exactly one nonactivating `NSPanel`; coordinator lifecycle and panel-only geometry ownership remain intact.
- [ ] When a volatile transcript exists, the transcript renders its deterministic active volatile group plus at most three remaining complete source-row groups: inactive groups are oldest-to-newest and the active group is bottom-most even when a finalized group has a later end time. Without a volatile transcript, it renders up to four newest finalized/history groups oldest-to-newest; original text precedes its optional translation in every group.
- [ ] The active row is exactly the deterministic newest nonempty volatile group and is bottom-most; no volatile transcript produces no active row.
- [ ] Pet Mode defaults off and, when off, leaves no gap or hidden hit/accessibility region. When visible, it appears above the transcript and shares the panel drag transaction with the header.
- [ ] Caption rows stay passive, nonfocusable, and non-scrollable; VoiceOver follows the header with inactive chronological groups and then the active row when present.
- [ ] The presentation remains understandable under Reduce Motion, Increase Contrast, and light/dark appearance.
- [ ] Focused deterministic contract tests and real-device validation both pass their respective checks; neither is used as a substitute for the other.

## Risk Assessment

| Risk | Mitigation | Validation |
|---|---|---|
| Incorrect generic newest-four selection lets a later finalized group displace the active volatile row or splits a source from its translation | Select the active volatile group first, reserve its slot, select only the remaining slots deterministically, then append the active group after chronological inactive groups; attach translations to their source group | Deterministic contract tests with later finalized candidates, multiple volatile candidates, no volatile candidates, ties, empty values, and over-limit groups |
| Layout changes introduce an invisible pet gap or a body-level drag target | Conditionally compose the pet only when visible; keep drag callbacks on the header and visible pet | Visual and interaction checks with Pet Mode both off and on |
| A second surface or geometry store erodes nonactivation and placement guarantees | Keep the coordinator as sole panel and persistence owner | Real-device checks for nonactivation, reset, clamping, screenshots, and screen sharing |
| Accessibility or visual-state changes make live status ambiguous | Preserve explicit live semantics and test/inspect VoiceOver, contrast, appearance, and motion settings | Real-device assistive-technology and appearance validation |

## Open Questions

- Which existing device matrix (display arrangements, screen-sharing client, VoiceOver configuration, and system appearance settings) is the release-validation baseline? This does not change scope or architecture; it identifies the required real-device coverage.
- Does the current panel-height policy already accommodate the maximum four-group transcript at the supported accessibility text settings, or should Phase 2 document a bounded sizing adjustment within the coordinator's existing ownership? No new persistence or second surface is permitted either way.
