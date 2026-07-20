---
phase: 3
title: "Verification"
status: pending
priority: P1
dependencies: [1, 2]
---

# Phase 3: Verification

## Overview

Plan the evidence required to accept the bottom-anchored floating-caption refinement without conflating deterministic XCTest coverage with behavior that only a physical Mac can establish. This phase adds no product capability: it verifies the one active-capture, nonactivating `NSPanel`, its bounded source-first transcript projection, and the optional panel-local Pet Mode.

## Requirements

- **Deterministic contracts:** Cover active/inactive row selection and display order; timestamp/identity ties; the four-complete-source-row cap and eviction; and source-stable translation association. When a nonempty volatile transcript exists, tests must choose the deterministic active volatile candidate by the existing `(endTime, identity)` tie-breaker, reserve one of four slots for it, select up to three newest remaining eligible groups, render those inactive groups oldest-to-newest, then render the active group bottom-most—even if a finalized candidate has a later end time. With no volatile transcript, tests must select up to four newest finalized/history groups and render them oldest-to-newest; no row is active.
- **Deterministic interaction and geometry contracts:** Cover Pet Mode default-off and enabled presentation state, hidden-pet non-eligibility, visible pet/header routing to the coordinator's same drag transaction, passive caption body, menu-bar reset ownership, per-display persistence, malformed-placement rejection, deterministic fallback, and clamping/restoration after display or panel-size changes.
- **Presentation and accessibility contracts:** Assert supplied presentation values preserve source before its optional translation, expose explicit live versus finalized semantics, and do not add focus, scrolling, transcript gestures, a second panel, or pet content inputs.
- **Required planned gates:** Run focused floating-caption XCTest coverage, the complete `Kineto` macOS XCTest scheme, and an unsigned arm64 Debug build. These are validation steps to perform after implementation; this plan records no result.
- **Required real-device evidence:** On a physical Mac, validate VoiceOver, Reduce Motion, large text, Increase Contrast in light and dark appearance, nonactivation, fullscreen meeting applications, normal screenshot/screen-share visibility, and multi-display behavior. Record each outcome or leave it explicitly open; automated tests and a successful build cannot substitute for these trials.

## Architecture

Verification follows the existing ownership boundaries rather than introducing a UI-test surface or persistence path:

1. `AppModel` remains the live/final transcript and translation-state owner. Focused presentation tests feed deterministic segments, volatile transcripts, translations, Pet Mode state, and capture state into `FloatingCaptionPresentation`.
2. `FloatingCaptionPresentation` tests own the shared active-last selection: choose the deterministic active volatile candidate by `(endTime, identity)`, reserve its slot, select up to three newest remaining eligible groups, and render inactive groups oldest-to-newest before the active group. Without volatility, tests select up to four newest finalized/history groups and render them oldest-to-newest. They also own exact source-to-translation association; tests use complete source-row groups so a translation cannot become an independently retained row.
3. `FloatingCaptionPanelPlacement` tests own pure normalized placement serialization, restore, fallback, malformed-input rejection, and clamp behavior. Coordinator-level tests cover reset clearing only the current display's saved placement and returning the same panel to its fallback.
4. `FloatingCaptionView`, `FloatingCaptionPetView`, `FloatingCaptionPanelCoordinator`, and `SignalGateMenu` are covered at their observable contracts: the visible header and visible pet invoke the coordinator's one drag path; the hidden pet and caption body do not become interaction or focus targets; the menu action invokes coordinator reset; and panel configuration remains nonactivating.
5. Physical-Mac trials own AppKit event delivery, VoiceOver traversal and spoken order, accessibility display settings, Spaces/fullscreen behavior, real multi-display topology, other-app activation, and actual screen-capture exposure. They remain unproven until performed and recorded.

## Related Code Files

- Verify/update focused contracts: `KinetoTests/FloatingCaptionPresentationTests.swift`
- Verify/add focused coordinator or placement contracts: `KinetoTests/` and `Kineto.xcodeproj/project.pbxproj` only if a new test file requires target membership
- Verify presentation projection: `KinetoApp/App/AppModel.swift` and `KinetoApp/UI/FloatingCaption/FloatingCaptionPresentation.swift`
- Verify rendering, accessibility, and drag routing: `KinetoApp/UI/FloatingCaption/FloatingCaptionView.swift` and `KinetoApp/UI/FloatingCaption/FloatingCaptionPetView.swift`
- Verify panel lifecycle, nonactivation, reset, persistence, and geometry: `KinetoApp/UI/FloatingCaption/FloatingCaptionPanelCoordinator.swift` and `KinetoApp/UI/FloatingCaption/FloatingCaptionPanelPlacement.swift`
- Verify menu reset routing: `KinetoApp/App/KinetoApp.swift` and `KinetoApp/UI/MenuBar/SignalGateMenu.swift`

## Implementation Steps

1. Add focused `FloatingCaptionPresentation` contract tests for mixed finalized and volatile candidates. Exercise one volatile, multiple volatile candidates, and no volatile candidate; assert deterministic active selection by `(endTime, identity)`, reserving one of four slots for the active volatile, selecting at most three newest remaining eligible groups, and rendering inactive groups oldest-to-newest before exactly one bottom-most active group.
2. Add an explicit later-final regression fixture: a nonempty active volatile candidate and one or more finalized candidates with later end times. Assert the deterministic active volatile remains retained and bottom-most, later finalized candidates compete only for the three inactive slots, and the view receives inactive chronological rows followed by the active row. Include equal-time stable-identity cases to prove the existing tie-breaker decides active-row choice reproducibly rather than input-array or dictionary iteration order.
3. Add cap and eviction matrices with more than four complete source-row groups, including volatile and finalized combinations. Assert no partial source/translation group appears; with volatility, the active slot is reserved and only up to three newest remaining eligible groups are retained, while without volatility up to four newest finalized/history groups are retained; in both cases the supplied display sequence follows the shared active-last rule.
4. Add translation-association tests for matching, missing, delayed, unrelated, and evicted translations. Assert an optional translation remains beneath its matching source, never attaches to a same-time or adjacent source, and cannot reorder, create, or revive a retained source row.
5. Add Pet Mode and interaction-contract tests. Cover default-off/hidden state, enabled listening and settled states, visible-pet eligibility, hidden-pet ineligibility, and shared callback routing for header and visible pet. Assert the caption body supplies no drag or interaction path and Pet Mode receives only presentation state and existing drag callbacks.
6. Add reset and placement tests around the pure helper and coordinator seam: normalize and restore per-display positions, reject malformed stored values, clamp after changed dimensions or display bounds, preserve other-display values, and have menu reset clear the current display's placement before using its deterministic fallback.
7. Add or extend a narrow panel-configuration test seam where feasible to assert the existing panel remains a single nonactivating active-capture `NSPanel`; do not attempt to infer inter-application focus behavior from source-only assertions.
8. Execute the planned automated gates after the tests are in place: focused floating-caption tests, the full `Kineto` macOS XCTest scheme, then an unsigned arm64 Debug build using the repository's established Xcode invocation. Treat any failure as a regression to repair rather than a reason to weaken the listed contracts.
9. On a physical Mac, run and record a separate validation matrix: start active capture with Pet Mode off and on; drag with header and visible pet; confirm the body and hidden pet do not drag; reset from the menu bar; move across displays, resize/relaunch, disconnect or rearrange displays, and confirm clamping/restoration.
10. On that same physical-Mac matrix, verify VoiceOver reads the header before the supplied inactive chronological source-plus-translation rows and the active volatile row last when present; enable Reduce Motion, large text, and Increase Contrast in light and dark appearance; verify the overlay neither activates Kineto nor steals the meeting app's focus; then exercise fullscreen Zoom, Google Meet, and Teams where installed, plus normal screenshot and screen-share sessions. Mark unavailable platform trials as open evidence, not passes.

## Success Criteria

- [ ] Focused deterministic tests protect the active-last selection invariant, including the later-final edge case: a deterministic active volatile is retained in a reserved slot and rendered bottom-most, with at most three newest remaining eligible inactive groups ahead of it; without volatility, up to four newest finalized/history groups render oldest-to-newest. Tests also protect time/identity ties and exact source-to-translation association.
- [ ] Focused deterministic tests protect Pet Mode off/on state, visible drag eligibility, hidden-pet/body inertness, shared drag ownership, menu reset, and per-display clamp/restore behavior.
- [ ] The planned focused XCTest run, full macOS XCTest scheme, and unsigned arm64 Debug build have been executed and their actual results recorded separately.
- [ ] Physical-Mac evidence records results for multi-display behavior, VoiceOver, Reduce Motion, large text, contrast, nonactivation, fullscreen meeting apps, and normal screen-share visibility; any unrun trial remains an open gate.
- [ ] No verification activity expands the approved surface, ownership, persistence, transcript, translation, or Pet Mode data-access boundaries.

## Risk Assessment

- **False assurance:** Unit tests can prove deterministic projection and geometry but cannot prove real AppKit focus, cursor/event delivery, VoiceOver speech, display topology, Spaces, fullscreen meeting-app behavior, or screen-share disclosure. Keep the physical-Mac matrix mandatory and separate.
- **Ordering regressions:** Equal timestamps, later finalized candidates, and late translations can make tests accidentally pass in incidental input order. Use deliberately shuffled fixtures and stable identities to prove the active reservation, active-last rendering, tie-breaker, and source association.
- **Interaction regressions:** A drag recognizer attached too broadly can make the passive caption body or hidden pet interactive while preserving basic visual tests. Verify callback ownership in source-level tests and pointer behavior on hardware.
- **Accessibility regressions:** Semantic live styling may rely on color or size alone, and visual hierarchy can fail at large text or increased contrast. Require VoiceOver and accessibility-display-setting evidence rather than treating layout inspection as proof.
- **Scope drift:** A second overlay, scrollable history, pet persistence, content-driven pet behavior, or a new capture path is outside this refinement and must require a separate approved design.
