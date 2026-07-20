---
phase: 2
title: Interactive overlay
status: completed
priority: P1
dependencies:
  - 1
---

# Phase 2: Interactive overlay

## Overview

Make the existing active-capture caption panel movable from an explicit header and capable of routing a regular-file drop to the current meeting attachment API. Increase the bounded caption projection to four rows without changing the app-lifetime observation or coalesced delivery lifecycle.

## Requirements

- Functional: render no more than four rows. A current volatile caption is visually provisional and consumes the newest slot; finalized history fills remaining slots in chronological order. Each final source line receives only its matching translation.
- Functional: the panel header is the only drag origin and the only drop target. It accepts file URLs only and reports concise accessible acceptance/rejection/import status.
- Functional: store a normalized, display-keyed panel origin locally; restore and clamp it into the destination screen `visibleFrame` after every content-size or display change.
- Functional: route accepted file URLs to `AppModel` and `MeetingPackageStore` only while an active capture meeting exists.
- Non-functional: retain nonactivating, floating, all-spaces, fullscreen-auxiliary behavior. The header is interactive; caption rows and Pet Mode remain noninteractive display content.
- Non-functional: do not create a second panel, timer, observer, direct storage access from the view, or capture-path await.

## Architecture

`AppModel` remains the value owner for capture phase, finalized segment order, translations, and attachment import status. It maps that state to a four-row `FloatingCaptionPresentation` with segment-stable IDs.

`FloatingCaptionPanelCoordinator` remains the sole `NSPanel` owner, app-lifetime observer, delivery coalescer, and geometry owner. It supplies header callbacks to `FloatingCaptionView`, translates AppKit drag coordinates to display-normalized placement, persists them through a namespaced coordinator-owned preference, and recreates the SwiftUI root without losing coordinator-owned drag state.

`FloatingCaptionView` adds a thin header above the existing caption/pet body. The header is the only SwiftUI drag/drop surface; it exposes no transcript history controls. Pet Mode receives only its existing enum and retains its fixed decorative footprint and Reduce Motion behavior.

## Related Code Files

- Modify: `KinetoApp/App/AppModel.swift`
- Modify: `KinetoApp/App/KinetoApp.swift` only if coordinator callback injection requires composition changes
- Modify: `KinetoApp/UI/FloatingCaption/FloatingCaptionPresentation.swift`
- Modify: `KinetoApp/UI/FloatingCaption/FloatingCaptionPanelCoordinator.swift`
- Modify: `KinetoApp/UI/FloatingCaption/FloatingCaptionView.swift`
- Modify: `KinetoApp/UI/FloatingCaption/FloatingCaptionPetView.swift` only if layout integration demands no contract change
- Modify: `KinetoTests/FloatingCaptionPresentationTests.swift`
- Create: focused app-level overlay placement/drop tests under `KinetoTests/`
- Modify: `Kineto.xcodeproj/project.pbxproj` for any new app test/source membership.

## Implementation Steps

1. Replace the current two-source/latest-line projection in `AppModel.floatingCaptionPresentation` with segment-identified rows sorted by finalized segment chronology. Match translations by `sourceSegmentID`; do not reorder history when translation completion arrives later.
2. Bound presentation at four rows in `FloatingCaptionPresentation`, update line IDs to segment identity, and preserve explicit volatile/final accessibility labels. Retain Pet Mode derivation from only enabled state, visible presentation, and volatility.
3. Add an attachment import state to `AppModel` that contains no source path or file contents. Expose a main-actor method called by the coordinator that validates an active recording meeting, delegates to `MeetingPackageStore`, and maps success/failure to concise user-visible status without interrupting capture.
4. Add a fixed-height header in `FloatingCaptionView` with a descriptive drop target, VoiceOver labels, and header-only drag gesture/drop handling. Preserve source-first row typography and the four-row bounded height; do not make caption rows or Pet Mode controls.
5. Replace all-panel `ignoresMouseEvents` behavior with a deliberately interactive nonactivating panel configuration. Header and drop-target points alone trigger overlay actions; caption-body points remain inert, cannot ingest content, and may consume pointer events while the overlay is visible. The panel must not become the app’s primary content window or create a focus trap.
6. Implement coordinator-owned drag state and callbacks. During a header drag, apply the pointer delta to the panel frame, resolve its active display from frame intersection/center, clamp to that display’s `visibleFrame`, and persist normalized origin on drag end.
7. Define a versioned, namespaced `UserDefaults` placement representation keyed by stable display identity. Defensively reject malformed stored values; use a deterministic bottom-center fallback; recompute after caption height, screen, or display-layout changes.
8. Forward only file URL drops from the header to the app model. While import work is running, show status without blocking the 250 ms caption delivery task or moving the panel. Reject drops outside active capture and disclose the failure accessibly.
9. Maintain immediate panel hiding for pause, stop, draining, processing, source loss, deletion, and reset. Do not move the coordinator from its app-lifetime observation scope or alter the generation guard/coalescing logic.
10. Add narrow app tests for four-row contract, provisional/final precedence, translation matching, header-only callback routing, normalized placement round-trip/clamping, display fallback, and hidden/noncapturing lifecycle behavior.

## Success Criteria

- [ ] Captions never exceed four rows; source text is primary and matching translation remains beneath its source.
- [ ] History order is stable when translations arrive later and no historical row IDs collide.
- [ ] Header and drop-target points alone trigger overlay actions; caption-body points are inert and cannot ingest content.
- [ ] Restored placement remains reachable across display-size, dock, and monitor changes.
- [ ] File drops do not make capture wait, restart the overlay observer, or create a new caption delivery task.
- [ ] The panel is hidden in every existing noncapturing state and remains nonactivating when interactive.

## Risk Assessment

- **Overlay update race:** root view recreation can reset SwiftUI-local drag state. Keep drag state exclusively in the coordinator.
- **Off-screen placement:** dynamic height and display changes can invalidate a saved origin. Clamp after `setContentSize` and on display changes.
- **Caption identity errors:** source-based IDs collapse history. Use finalized segment IDs.
- **Interaction regression:** removing pointer-through can block underlying UI. Limit visible interaction affordances to a slim header and validate real cross-app use.
- **Capture starvation:** attachment import could compete for main actor time. Make the main actor only initiate/status-map the storage task; stream I/O in the storage actor/helper.
