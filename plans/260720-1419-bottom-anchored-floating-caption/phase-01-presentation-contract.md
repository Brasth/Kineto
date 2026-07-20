---
phase: 1
title: "Presentation contract"
status: pending
priority: P1
dependencies: []
---

# Phase 1: Presentation contract

## Overview
Define the pure, deterministic transcript projection used by the existing floating-caption panel. This phase changes only `FloatingCaptionPresentation` and its focused XCTest contract so the view receives a bounded snapshot whose inactive retained groups are chronological and whose sole active volatile group, when present, is always bottom-most.

## Requirements
- Functional: project at most four complete source-row groups from finalized segments and nonempty volatile transcripts. A group is one original source row plus its optional translation; a translation never consumes a separate slot.
- Functional: when nonempty volatile transcripts exist, first choose the deterministic newest volatile candidate by end time then stable row identity, reserve one of four group slots for it, and fill up to three slots with the newest remaining eligible groups by that same ranking. Render the inactive retained groups oldest-to-newest, then render the active group last; a finalized candidate with a later end time cannot displace it. When no volatile transcript exists, select up to four newest finalized/history groups by the same ranking and render them oldest-to-newest.
- Functional: expose an optional `activeLineID`. It is the identity of the deterministic newest nonempty volatile candidate and is always retained when one exists; it is `nil` only when no volatile transcript exists. A finalized row must never be designated or styled as live.
- Functional: retain stable, collision-safe row identities across updates, exclude duplicate volatile/final representations of the same source-row transition, and use the shared `(endTime, identity)` rule to choose exactly one active volatile candidate under equal-time ties. The existing `AppModel` finalized-event transition that clears the matching per-source volatile state remains the cross-state handoff; do not invent text-based or translation-based duplicate matching.
- Functional: attach a translation only to its matching finalized `sourceSegmentID`, after candidate selection, without changing that source row's identity or ordering. Volatile rows have no translation.
- Non-functional: keep the projection pure, value-based, and bounded at the presentation boundary. It must not create storage, persistence, a local transcript cache, a timer, or any panel/coordinator behavior.
- Boundary: preserve the existing single nonactivating active-capture `NSPanel`, coordinator ownership, and panel-local Pet Mode contract. Pet state remains non-content state only; this phase gives it no transcript, audio, source, translation, or sentiment access.

## Architecture
`AppModel` continues to pass its in-memory finalized segments, translations, and volatile snapshot into `FloatingCaptionPresentation.live`. Inside that presentation factory, normalize candidates to stable source-row identities, discard empty volatile values and duplicate identities, and rank recency by the shared `(endTime, identity)` rule. If any volatile candidate remains, choose its newest candidate as the active group first, reserve one slot, select up to three newest remaining eligible groups, sort only those inactive retained groups into oldest-to-newest display order, and append the active group last. If none remains, select up to four newest finalized/history groups and sort them oldest-to-newest for display.

Derive `activeLineID` from the active-first volatile choice, not from the generic retained set or last chronological inactive group. The active choice is retained and rendered last even when a finalized candidate has a later recency key. Use the existing finalized-event removal of the source's volatile snapshot to prevent a finalization transition from rendering both states of one row; do not add fuzzy text comparison or a second state path. Build `FloatingCaptionLine` values only after selection and look up translations by `sourceSegmentID` for selected finalized rows.

The projection remains stateless. Its output is capped even as meetings grow; it may scan the supplied in-memory inputs but must avoid sorting or mapping an unbounded line output and must not introduce a projection cache, store, or update timer. Existing coordinator delivery coalescing remains the only cadence control.

## Related Code Files
- Modify: `KinetoApp/UI/FloatingCaption/FloatingCaptionPresentation.swift`
- Modify: `KinetoTests/FloatingCaptionPresentationTests.swift`
- Do not modify: `KinetoApp/App/AppModel.swift`
- Do not modify: `KinetoApp/UI/FloatingCaption/FloatingCaptionView.swift`
- Do not modify: `KinetoApp/UI/FloatingCaption/FloatingCaptionPanelCoordinator.swift`

## Implementation Steps
1. Extend `FloatingCaptionPresentation` with the optional active-line identity and make its initializer and hidden presentation preserve the four-group limit while guaranteeing that no volatile candidate yields no active identity.
2. Replace input-order/prefix projection with one deterministic candidate-selection path in `live`: filter empty volatile text, deduplicate stable candidate identities, rank by the documented end-time and identity tie-breaker, then choose the newest volatile candidate first when present and reserve one of four group slots for it. Fill at most three remaining slots from the newest remaining eligible groups; only when no volatile candidate exists, fill up to four slots from finalized/history groups.
3. Order the inactive retained groups oldest-to-newest and append the reserved active group last. Apply the volatile/final transition rule without a second model: rely on the existing per-source volatile clearing when a final is published and prevent duplicate candidate identities in the projection. Do not use content equality, translations, or new persistence to guess equivalence.
4. Construct selected finalized lines with their stable segment IDs and attach only the matching `TranslationRecord.sourceSegmentID`; construct selected volatile lines without translations. Derive `activeLineID` once from the reserved active volatile candidate, never from a generic newest-four list, a later finalized candidate, or the last chronological inactive line.
5. Replace obsolete input-order/newest-first presentation tests with focused deterministic contract tests for: active-slot reservation despite a later finalized candidate; three-slot remaining-group capping; no-volatile four-finalized/history fallback; inactive chronological order plus active-last order; source-first translation attachment; volatile/final transition duplicate exclusion; equal-time identity tie-breaks; exactly one active volatile identity; and the no-volatile/no-active-final rule.
6. Keep the tests at the presentation-factory boundary using synthetic `Segment`, `VolatileTranscript`, and `TranslationRecord` values. Do not add view snapshots, timers, persistence fixtures, or panel lifecycle tests in this phase.

## Success Criteria
- [ ] With one or more eligible volatile transcripts, a snapshot renders the deterministic active volatile group plus at most three newest remaining eligible source groups; the inactive groups display oldest-to-newest and the active group displays last even if a finalized candidate has a later end time.
- [ ] With no volatile transcript, a snapshot renders up to four deterministic newest finalized/history groups oldest-to-newest and exposes no active row.
- [ ] Every displayed row is a complete source group: original text precedes its optional translation, and no translation appears without or moves ahead of its matching finalized source segment.
- [ ] Duplicate volatile/final transition state does not create two displayed representations of one source row; unrelated rows from the same source remain eligible history.
- [ ] Equal end times always resolve using the documented stable identity rule without input-order dependence.
- [ ] When one or more volatile rows are eligible, `activeLineID` identifies only the deterministic newest volatile row and that row is retained and bottom-most; no final row can become active.
- [ ] Focused XCTest coverage asserts the active-slot reservation, inactive chronological ordering, active-last display, and no-volatile fallback rather than reversing a generic newest-four list or asserting implementation details.
- [ ] No panel/window, interaction, Pet Mode data-flow, persistence, store, cache, or timer behavior is added or changed.

## Risk Assessment
The supplied segment and translation collections grow throughout a long meeting, so a projection recomputed during live delivery can become increasingly expensive. Keep the result bounded to four groups: choose and reserve the active volatile group first when present, select only the remaining slots before constructing presentation lines, and attach translations only for retained final rows. This ordering prevents a later finalized candidate from displacing the bottom active row while avoiding an unbounded rendered collection or repeated whole-history line allocation. With no volatile candidate, use the bounded four-finalized/history fallback. The projection remains stateless and gains neither a local cache/store nor a timer—the coordinator's existing coalesced delivery cadence is sufficient. Required real-device validation in the later verification phase must exercise a long active capture and confirm that caption updates remain responsive; deterministic XCTest cases here prove active-slot selection, ordering, and identity contracts only, not AppKit lifecycle or accessibility behavior.
