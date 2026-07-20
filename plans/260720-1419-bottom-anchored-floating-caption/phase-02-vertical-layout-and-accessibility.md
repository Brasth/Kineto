---
phase: 2
title: "Vertical layout and accessibility"
status: pending
priority: P1
dependencies: [1]
---

# Phase 2: Vertical layout and accessibility

## Overview

Recompose `FloatingCaptionView` as a compact vertical overlay: a draggable capture header, an optional visible Pet Mode region, and a bounded passive caption body anchored at the panel’s bottom. This phase consumes the deterministic row snapshot from Phase 1; it does not alter transcript selection, panel ownership, capture state, or persistence.

## Requirements

- Preserve the single existing nonactivating active-capture `NSPanel`. `FloatingCaptionPanelCoordinator` remains its sole owner for lifecycle, root-view delivery, fitting size, display placement, clamping, drag transactions, reset, and panel-only placement persistence.
- Use a vertical SwiftUI stack in `FloatingCaptionView`: header first, then the pet only when `presentation.petState` is not `.hidden`, then the transcript region at the bottom.
- Compose no pet view, space, accessibility element, gesture, or hit-testable container when Pet Mode is hidden. Pet Mode remains optional/default-off, panel-local, decorative except for visible dragging, and state-only.
- Give the header and the visible pet the same existing `onPanelDragChanged` and `onPanelDragEnded` callbacks. The root layout and caption body must not install gestures, row actions, drop targets, controls, or hidden drag affordances.
- Reserve a fixed/minimum transcript body footprint that bottom-aligns its rows within that region while allowing the complete retained rows to determine any necessary vertical growth. The region is passive, nonfocusable, non-scrollable, and must not use `ScrollView`, `List`, automatic scrolling, or an independent transcript cache/timer.
- Render at most the supplied four complete source-row groups as supplied: inactive groups in chronological order, followed by the supplied active volatile group last when one exists. Use each presentation row’s stable source identity as the `ForEach` identity; do not synthesize position-based identities, sort, or reorder rows in the view.
- Keep an original source followed immediately by its optional translation within one row group. Only the supplied active volatile row is visually active and announced as live, including when an inactive finalized group has a later end time; all inactive rows retain subdued history treatment. With no volatile row, no row is active/live.
- Constrain text to the supplied panel width, wrap source and translation naturally, and let the coordinator continue to obtain the SwiftUI fitting height. Do not introduce horizontal scrolling, manual panel geometry, a second window/surface, or a persistence path.
- Keep traversal intentional: VoiceOver encounters the header before the supplied inactive chronological combined row descriptions, followed by the supplied active volatile description last when present. Caption rows expose source, final/live status, original text, then optional translation in that order; they are not focusable controls or actionable elements.
- Respect accessibility settings: Reduce Motion removes pet and layout motion rather than merely shortening it. Light/dark appearance and Increase Contrast must distinguish active/live state from historical state with redundant cues (status text, hierarchy/weight, and contrast-aware styling), never color or font size alone.
- Maintain Pet Mode’s privacy boundary: `FloatingCaptionPetView` continues to receive only `FloatingCaptionPetState` plus the existing panel-drag callbacks—never transcript rows, translations, audio/source metadata, identity, sentiment, capture model, or derived behavior.

## Architecture

`FloatingCaptionPresentation` is the immutable rendering contract: Phase 1 supplies complete inactive groups in chronological order and, when present, the one deterministic active volatile group last, each with source-stable IDs and attached translations. `FloatingCaptionView` renders that supplied sequence without selecting, sorting, caching, or deriving transcript state. Its nested header and visible pet reuse the coordinator-owned drag transaction callbacks; the caption body deliberately has no interaction ownership.

The coordinator retains the one `NSPanel` and continues to replace only its hosted SwiftUI root as presentations arrive. This phase changes neither panel configuration nor placement policy. Because the pet is conditionally composed instead of visually hidden, disabling Pet Mode removes its layout and input/accessibility footprint rather than leaving an invisible surface.

## Related Code Files

- Modify: `KinetoApp/UI/FloatingCaption/FloatingCaptionView.swift` — vertical composition, conditional pet placement, passive bottom-aligned transcript body, row hierarchy, and accessibility semantics.
- Reference only: `KinetoApp/UI/FloatingCaption/FloatingCaptionPresentation.swift` — supplied stable row IDs, volatility/active-state contract, header presentation, and pet state; do not move projection logic into the view.
- Reference only: `KinetoApp/UI/FloatingCaption/FloatingCaptionPetView.swift` — retain its narrow state-and-drag-callback input contract; change it only if required to honor Reduce Motion without broadening inputs.
- Reference only: `KinetoApp/UI/FloatingCaption/FloatingCaptionPanelCoordinator.swift` — retain the single-panel lifecycle, sizing, nonactivation, placement, clamping, reset, persistence, and shared drag callbacks.
- Update in the verification phase: `KinetoTests/FloatingCaptionPresentationTests.swift` and any focused UI/accessibility test location already established by the project. Deterministic presentation-contract tests and real-device overlay validation are separate obligations.

## Implementation Steps

1. Inspect the finalized Phase 1 presentation contract and retain the view’s existing callback injection from `FloatingCaptionPanelCoordinator`. Treat supplied inactive chronological rows, the supplied active-last volatile row, identities, translation association, and live designation as display-only inputs; do not add local selection, sorting, or state.
2. Replace the side-by-side body with a top-to-bottom composition. Keep the draggable capture header first; insert `FloatingCaptionPetView` directly below it only for a visible pet state; place the caption body last and anchor its content to that body’s bottom edge.
3. Route the existing drag callbacks unchanged to the header and, only while composed, to the pet. Make the header’s drag affordance explicit in its accessibility hint. Do not attach a gesture to the outer container, transcript body, row group, source text, or translation text, and do not add an invisible overlay to preserve drag behavior while the pet is absent.
4. Define the caption body with a deliberate minimum/fixed visual footprint and bottom alignment, while allowing complete retained row groups to expand the fitting height rather than clip, scroll, or truncate them. Preserve a finite width derived from the coordinator-supplied panel width so source and translation wrap vertically without horizontal scrolling.
5. Render the supplied inactive chronological rows followed by the supplied active volatile row last, with their source-stable identifiers and without animations that can make live updates reorder or interpolate as new history. Keep one `FloatingCaptionLineView` per complete group: source/status context, original text, then attached optional translation. Style the supplied active volatile group as the only live row; style all inactive rows as historical.
6. Keep the transcript body explicitly passive and out of keyboard focus. Do not introduce `Button`, context menu, drag/drop, row selection, focus state, scroll container, text selection action, or body/root hit target. Preserve the nonactivating panel behavior by leaving AppKit window configuration and coordinator interaction policy unchanged.
7. Refine accessibility semantics: expose the header before the supplied inactive chronological groups and the supplied active volatile group last when present; combine each group into a spoken description containing source, final or live status, original, then translation. Ensure labels make live state intelligible without relying on visual accent, and ensure decorative pet content does not expose transcript-derived information or become a hidden interactive target.
8. Apply environment-aware visual behavior. Disable decorative pet/layout motion under Reduce Motion, keep update layout deterministic, and provide contrast-aware active/history separation for both light and dark appearances and Increase Contrast using redundant textual/status and typographic cues.
9. In Phase 3, add deterministic contract tests for stable identities, four-group bounds/order, source-before-translation association, and the zero-or-one active volatile rule. Separately perform required real-device validation of the actual nonactivating panel across displays, drag behavior, VoiceOver traversal, keyboard focus, Pet Mode visibility, Reduce Motion, Increase Contrast, screenshots, and screen sharing; unit tests cannot establish those AppKit and assistive-technology behaviors.

## Success Criteria

- [ ] The overlay is vertically ordered as header, visible pet when enabled, then a bottom-aligned transcript body; hiding Pet Mode leaves no visual gap, accessibility node, or hit target.
- [ ] Header and visible pet initiate the same coordinator-owned panel drag transaction; no caption/body/root gesture or row action can move the panel or invoke an action.
- [ ] The single coordinator-owned nonactivating `NSPanel` remains the only presentation surface, with its existing sizing, placement, clamping, reset, and panel-only persistence responsibilities unchanged.
- [ ] The passive, nonfocusable, non-scrollable caption body shows no more than four complete stable-identity groups, rendering supplied inactive chronological groups followed by the supplied active volatile group at the bottom whenever one exists.
- [ ] Every group presents original source before its optional translation, wraps within the panel width, and has no horizontal scrolling or independent transcript state.
- [ ] Only the supplied active volatile group receives live treatment; finalized rows are never labeled or styled as live when no volatile row exists.
- [ ] VoiceOver traversal is header, then supplied inactive chronological combined row descriptions, then the supplied active volatile description last when present; captions expose no controls, selection, focus trap, or transcript-derived pet content.
- [ ] Reduce Motion removes pet/layout motion, and active/history distinction remains clear in light/dark appearance and Increase Contrast without depending on color or font size alone.
- [ ] Phase 3 distinguishes passing deterministic presentation-contract tests from required successful real-device overlay and accessibility validation; neither is represented as completed by this planning phase.

## Risk Assessment

| Risk | Mitigation |
| --- | --- |
| A visually hidden pet leaves an invisible drag or accessibility target. | Conditionally compose the pet region only for visible state; do not reserve a transparent container or attach root-level drag handling. |
| Vertical reflow makes captions scroll, clip, or float away from the bottom edge. | Use a bounded bottom-aligned passive body with a minimum footprint and complete-row-driven fitting height; prohibit scroll containers and coordinate no geometry locally. |
| SwiftUI iteration churn reorders rows or animates active/history transitions. | Consume Phase 1’s supplied inactive-then-active-last sequence directly, key rows by source-stable identity, and suppress presentation-only reordering animation. |
| Added interactions activate the overlay, create focus traps, or bypass coordinator drag persistence. | Keep only header/visible-pet drag callbacks, retain the coordinator’s single nonactivating panel, and add no controls, focus state, or new surface. |
| Accessibility styling loses meaning under contrast or motion preferences. | Pair visual live treatment with explicit status labels and hierarchy, and make pet/layout motion conditional on Reduce Motion. |
| Pet implementation acquires capture data while integrating layout. | Keep its public inputs limited to `FloatingCaptionPetState` and existing drag callbacks; pass no transcript, translation, source, audio, identity, sentiment, or model data. |
