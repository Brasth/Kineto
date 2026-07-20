# Pet-led subtitle overlay design

## Goal

Make the decorative companion the primary visible drag affordance for Kineto's floating captions. The companion stays under the pointer while dragging; the caption panel retains its linked placement below it, but the entire caption surface is visually suppressed for the held companion drag. Its panel and frame remain alive, and the surface returns immediately on release. Replace the current card-like caption treatment with a compact minimal subtitle bar while retaining the current four-row transcript contract.

## Decisions

- Keep the existing linked nonactivating AppKit panels and one persisted transcript placement. Do not create a companion-specific coordinate or persistence record.
- Keep the caption panel as the storage anchor, but derive each drag update from the companion's frame and its fixed relationship to the caption panel. This gives the pet-led interaction without reversing the AppKit parent/child relationship.
- Update the caption and companion frames together for every drag event. The companion remains under the pointer; the caption panel retains its fixed linked frame and vertical gap while the companion is dragged.
- During an active companion pointer drag, visually suppress the entire caption surface, including the header; do not tear down, hide, or move its panel/frame independently. Restore the surface immediately when the drag ends. The header is the accessible fallback once the caption surface is restored and remains visible during a header-initiated drag.
- Pause, stop, and processing transitions are terminal rather than drag-continuation states.
- Render the caption surface as a compact translucent subtitle bar with a 576 pt default width, 68 pt minimum content height, and 14 pt vertical padding. It preserves up to four source-first rows: chronological inactive history and a final, mint-accented active volatile `Live` row. Translations stay subordinate to their finalized source.
- Preserve all existing privacy, nonactivation, screen-share, settings, motion, color, placement, and transcript-selection contracts outside the user-held companion drag.

## Alternatives rejected

1. Reverse the AppKit parent/child hierarchy so the pet panel owns the caption panel. This makes the pet technically primary but adds lifecycle, ordering, Spaces, and persistence risk.
2. Merge pet and transcript into one surface. Simpler, but it removes the requested separate pet-led composition.

## Verification

- [x] Deterministic placement and presentation behavior is implemented and covered by focused pet/presentation tests (33 tests).
- [x] The approved five-pet customization implementation is complete: Signal Cat, Orbit Fox, Beacon Frog, Night Owl, and Meadow Rabbit.
- [x] The full Kineto macOS XCTest scheme passes with 40 tests and 0 failures.
- [x] An unsigned Debug app launch smoke succeeds.
- [ ] Physical-Mac validation remains required and unrecorded: drag the visible pet across displays; confirm it remains under the pointer, its caption panel/frame stays linked while the entire caption surface is visually suppressed, and that surface restores immediately on release. Also confirm reset restores the linked layout; once the caption surface is restored, header dragging stays visible and works; hidden Pet Mode has no hit target; VoiceOver behavior; ordinary screenshot and screen-share behavior outside the held drag; fullscreen-app behavior; and Reduce Motion. No physical-Mac or release-gate acceptance is marked complete.
