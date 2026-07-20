---
title: Pet-led subtitle overlay
description: >-
  Approved follow-on redesign: a companion-led drag affordance,
  caption-surface suppression during held companion dragging, and compact
  four-row subtitle bar.
status: completed
priority: P2
branch: main
tags:
  - caption-overlay
  - appkit
  - swiftui
  - accessibility
  - pet-mode
blockedBy: []
blocks: []
created: '2026-07-20T09:48:15.310Z'
createdBy: 'ck:plan'
source: skill
---

# Pet-led subtitle overlay

## Overview

Implement the approved follow-on to the completed floating-caption work. The visible companion becomes the primary pointer drag affordance: its frame tracks the pointer and the caption panel retains the linked placement below it. During the held companion drag, visually suppress the entire caption surface while keeping the panel/frame alive; restore it immediately on release. The header is the accessible fallback when the caption surface is restored and remains visible during a header-initiated drag. Preserve the existing linked nonactivating panels, one persisted caption placement, four-row active-last transcript projection, and decorative-only companion boundary.

## Status

- [x] Implementation complete: the approved five-pet customization is implemented for Signal Cat, Orbit Fox, Beacon Frog, Night Owl, and Meadow Rabbit.
- [x] Automated verification is green: focused pet/presentation tests (33 tests), the full Kineto macOS XCTest scheme (40 tests, 0 failures), and an unsigned Debug launch smoke.
- [ ] Physical-Mac validation and any release gates remain open; no real-device acceptance is marked complete.

## Baseline and dependencies

- Approved design: [`docs/plans/2026-07-20-pet-led-subtitle-overlay-design.md`](../../docs/plans/2026-07-20-pet-led-subtitle-overlay-design.md).
- The earlier bottom-anchored caption plan is implementation baseline only. This plan does not rework transcript selection, settings persistence, or companion visual preferences.
- No new persistence key, panel, window level, input target, or transcript data path is permitted.

## Phases

| Phase | Name | Status | Dependency |
|---|---|---|---|
| 1 | [Pet-led drag geometry](./phase-01-drag-geometry.md) | Completed | Existing linked-panel coordinator |
| 2 | [Minimal subtitle bar](./phase-02-subtitle-bar.md) | Completed | Phase 1 |
| 3 | [Verification and documentation](./phase-03-verification.md) | Completed | Phases 1–2 |

## Architecture

```text
Visible pet drag gesture
  -> companion start frame + gesture translation
  -> proposed companion origin
  -> inverse linked-placement conversion
  -> clamped caption origin on destination display
  -> synchronized caption panel frame + companion frame
  -> visually suppress the entire caption surface for the held companion drag
  -> restore the caption surface immediately on drag end
  -> persist caption placement only on drag end
```

The coordinator owns the conversion, clamp, and drag-only caption-surface state. `FloatingCaptionCompanionPanel` owns only its transparent nonactivating child-window presentation. `FloatingCaptionView` remains a pure renderer of the supplied bounded presentation, rendering the compact 576 pt default-width subtitle bar with 68 pt minimum content height and 14 pt vertical padding when the caption surface is restored. The header is the accessible drag fallback when restored and remains visible during a header-initiated drag; the entire caption surface is visually suppressed during a held companion drag. Pause, stop, and processing transitions remain terminal, not drag-continuation states.

## Success criteria

- [ ] Dragging the visible pet keeps it under the pointer while its linked caption panel/frame retains the fixed gap; the entire caption surface is visually suppressed for the held drag and restores immediately on release.
- [ ] When the caption surface is restored, header dragging remains visibly available as the accessible fallback and moves the same linked placement; during a header-initiated drag it remains visible, only the caption origin persists, and reset restores that link.
- [ ] The visible overlay is a compact 576 pt default-width subtitle bar with 68 pt minimum content height, 14 pt vertical padding, up to four source-first rows, chronological inactive history, and an active last mint `Live` row.
- [ ] Pet Mode off yields no visible or interactive companion surface.
- [x] Focused pet/presentation tests (33), the full Kineto macOS XCTest scheme (40 tests, 0 failures), and the unsigned Debug app launch smoke pass.
- [ ] Physical-Mac validation is pending and must prove whole-caption-surface suppression and immediate restoration during held companion dragging, multi-display drag, VoiceOver, ordinary screenshot and screen-share behavior outside the held drag, fullscreen apps, and Reduce Motion. No physical-Mac item is marked complete.

## Open questions

None.
