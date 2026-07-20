---
phase: 1
title: Pet-led drag geometry
status: completed
priority: P1
dependencies: []
---

# Phase 1: Pet-led drag geometry

## Overview

Make the visible companion the pointer-led drag surface without changing the caption panel's sole persisted placement or the linked child-panel lifecycle.

## Requirements

- Functional: a companion drag starts from its on-screen origin, maps gesture translation to a proposed companion origin, derives the corresponding caption origin, chooses the destination display before clamping, then positions both panels.
- Functional: header drag keeps its existing caption-led semantics and uses the same end/persist transaction.
- Non-functional: hidden Pet Mode accepts no hit testing; no panel activates, no new geometry key is stored, and caption updates remain deferred while either drag transaction is active.

## Architecture

Add pure linked-placement conversion helpers adjacent to the existing `companionOrigin`, `linkedSize`, `clamp`, and `placement` helpers. The inverse helper converts a desired companion origin into the caption origin using the current caption size, companion size, and fixed vertical gap. Keep screen selection based on the proposed linked frame—not the drag-start screen—so the pair can cross displays.

## Related Code Files

- Modify: `KinetoApp/UI/FloatingCaption/FloatingCaptionPanelPlacement.swift`
- Modify: `KinetoApp/UI/FloatingCaption/FloatingCaptionPanelCoordinator.swift`
- Modify: `KinetoApp/UI/FloatingCaption/FloatingCaptionCompanionPanel.swift` only if its callback needs a distinct pet-led callback name.
- Modify: `KinetoTests/FloatingCaptionPresentationTests.swift` or create the smallest matching placement test target/file only if the existing test convention requires it.

## Implementation Steps

1. Add deterministic inverse placement math from companion origin to caption origin; keep it independent of AppKit.
2. Split coordinator drag entry points into caption-header and companion-pet paths while keeping one drag-end/persistence path.
3. At companion drag start, capture the companion frame; on each update, derive the proposed companion origin, resolve the target display from the proposed linked frame, clamp the derived caption origin, and synchronize the companion after moving the caption.
4. Preserve the current cross-display screen selection, reset behavior, coalesced presentation deferral, and `UserDefaults` caption-only persistence.
5. Add boundary tests for inverse geometry, linked centering, clamping, and destination-display behavior.

## Success Criteria

- [ ] A pet drag maps directly to a synchronized linked caption origin; the pet does not lag or remain at its old location.
- [ ] Header drag and pet drag both persist the same normalized caption placement.
- [ ] The pair remains onscreen and can transition to another display.
- [ ] No companion placement preference or independent drag state survives the drag transaction.

## Risk Assessment

| Risk | Mitigation |
|---|---|
| Pet jumps on first drag frame | Capture the actual companion start origin and use its inverse relation to the caption origin. |
| Caption clamps to start display | Resolve display from the proposed linked frame before clamping. |
| Child panel desynchronizes | Route every caption-origin mutation through one synchronization helper. |
