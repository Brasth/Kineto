# Design Implementation Plan: Floating Caption Panel Redesign

**Date:** 2026-07-21  
**Status:** Approved + Implementation in progress (Phase 1 + 2 largely complete in source)
**Target Component:** Floating caption overlay (active-capture only)
**Scope:** Single component redesign — visual presence, entrance behavior, hierarchy, contrast, and control affordances inside the existing floating panel.
**Explicitly out of scope:** Changing `CapturePresentationMode`, auto-floating on Start, main window ordering, or the overall presentation contract.
## Summary of Approved Direction
- **Base:** Variant C (Comfortable Two-Zone layout)
- **Additions:**
  - Stronger visual presence + brief prominent entrance treatment (from first-round request + Variant A)
  - Persistent high-contrast REC + elapsed time + refined mint signal (B + E influences)
- **Goal:** Make the floating panel immediately noticeable and glanceable the moment recording starts, while remaining calm/professional and dramatically more usable. Keep auto-floating behavior.

**Brand:** Minimal, Trustworthy, Focused, Commanding (at start instant), Professional, Calm.  
**Density:** Comfortable for reading + temporarily stronger on entrance, then settles.

## Must-Keep Invariants (non-negotiable — every change must preserve these)
- Nonactivating borderless NSPanel pair at `.floating` level (`canJoinAllSpaces`, `fullScreenAuxiliary`)
- Linked caption + companion (pet) geometry with existing drag model and caption suppression during companion drag
- Maximum ~4 lines of live transcript history
- Immediate full hide on Pause, Stop & Process, Show Meeting Details, source loss, processing, and all non-capturing states
- Visible in screenshots and screen sharing (no privacy claim change)
- Existing control set: Pause/Resume, Stop & Process, Show Meeting Details (gated by `SignalGatePresentation`)
- Pet Mode remains optional, decorative-only; receives only `FloatingCaptionPetState` + visual prefs (no transcript, audio, or capture data)
- Per-display persisted placement with clamping (`FloatingCaptionPanelPlacement`)
- Full Reduce Motion, VoiceOver, keyboard, and Increase Contrast support
- Lightweight (no measurable increase in CPU/memory during capture)

## Files to Change

**Primary:**
- `KinetoApp/UI/FloatingCaption/FloatingCaptionView.swift` — complete visual and layout refactor (two zones, new header/status treatment, entrance support, contrast, controls placement)
- `KinetoApp/UI/FloatingCaption/FloatingCaptionPanelCoordinator.swift` — add one-time entrance delivery hook; ensure first post-Start presentation can signal emphasis; preserve all drag, suppression, lifecycle, and positioning logic

**Presentation / State (minimal):**
- `KinetoApp/UI/FloatingCaption/FloatingCaptionPresentation.swift` — optional small addition for entrance flag or "isEmphasized" if coordinator cannot derive it cleanly from first delivery after `.capturing`
- `KinetoApp/App/AppModel.swift` — expose (or derive) a lightweight "first appearance after start" signal if needed for the presentation; do not change core `capturePresentationMode` or `signalGatePhase` logic

**Supporting / Polish:**
- `KinetoApp/UI/FloatingCaption/FloatingCaptionCompanionPanel.swift` — minor if pet suppression during entrance is required (prefer doing it in SwiftUI root)
- `KinetoApp/App/KinetoApp.swift` — only if coordinator injection or observation needs tiny wiring change (expect none)

**Documentation & Guidelines (after visual behavior is stable):**
- `docs/design-guidelines.md` — update Floating caption overlay section
- `docs/user-guide.md` — minor refresh of floating captions description if wording changes
- Possibly `plans/` historical notes if relevant

**Tests:**
- Update or add focused tests under `KinetoTests/` for presentation projection and entrance behavior (existing `FloatingCaption*` tests)
- Real-device validation is the primary gate (see checklist)

No changes to `KinetoCore`, capture, ASR, storage, or main live transcript logic.

## Implementation Strategy (Phased)

### Phase 1: Contract & Coordinator Hook (safe, no visual change)
1. Audit current delivery path: `present(_:)` → `deliverPendingPresentation()` → `rootView(for:...)`.
2. Add a clean, one-shot "entrance" signal owned by the coordinator (cleared after first delivery or after a short timeout). Drive it from the transition into `.capturing` state.
3. If `FloatingCaptionPresentation` needs an `isEmphasized` or similar boolean for the first frame, add it (keep default `false` for backward compatibility).
4. Add a coordinator-owned callback or state so the view can know "apply entrance treatment now".
5. Verify: all existing hide paths, drag suppression, companion linking, and placement still work exactly as before. No behavior change yet.

**Exit criteria:** Coordinator can deliver an "emphasized first frame" without side effects. All existing tests and smoke paths pass.

### Phase 2: Visual & Layout Redesign (core work)
Refactor `FloatingCaptionView` (and its private subviews):

1. Introduce clear two-zone structure:
   - Top zone (status + controls): higher visual weight.
   - Bottom zone (transcript): comfortable, readable.

2. Top zone content:
   - Persistent REC indicator + elapsed time (system red dot + mint accent for Kineto identity).
   - Controls (Pause/Resume, Stop, Show Meeting Details) with clear separation and ≥28 pt hit areas.
   - Refined left mint signal accent (status-zone height only).

3. Container treatment:
   - Move away from uniform `.thinMaterial`.
   - Give top zone stronger separation (heavier material, custom fill, or stronger border/accent while active).
   - Transcript zone can stay lighter.

4. Entrance treatment (one-time, non-repeating):
   - On the emphasized first delivery: short scale + opacity/intensity boost focused on the top zone or REC element (≈150-250 ms, ease-out).
   - Then immediately relax to normal state.
   - Honor `Reduce Motion` → no motion, just the stronger static treatment for first frame or two.

5. Typography & contrast:
   - Transcript lines: comfortable line height, higher contrast than current.
   - Source labels: secondary but clear.
   - Keep 4-line bound.

6. Pet integration:
   - Keep linked placement.
   - During entrance emphasis, allow visual suppression or static state (no motion).

7. Update private subviews (`FloatingCaptionHeaderView`, `FloatingCaptionControlsView`, `FloatingCaptionLineView`) or introduce new `FloatingCaptionStatusZone` / `FloatingCaptionTranscriptZone` as needed for clarity.

**Constraints during this phase:** Never break nonactivation, drag, or hide contracts. Keep the view receiving exactly the same `FloatingCaptionPresentation` + `SignalGatePresentation` shape where possible.

### Phase 3: Controls, Interaction & Polish
- Ensure controls have strong tap targets and clear focus/hover states (even on nonactivating panel).
- Make drag handle obvious (header grip or integrated REC area) while preserving existing drag gesture code.
- Verify "Show Meeting Details" is reachable and labeled correctly.
- Test all signal-gate states (capturing, paused, etc.) render correctly in the new zones.

### Phase 4: Validation (the real gate — do not skip)
Real-device testing on physical Macs (minimum):
- Typical meeting app backgrounds (Zoom, Google Meet, Teams — light and dark UIs).
- "Start Meeting" → can the user immediately locate REC state and at least one control within 1-2 seconds without searching?
- Screen share + screenshot visibility (panel must remain legible and present).
- Full hide on Pause, Stop & Process, Show Meeting Details, source loss.
- Drag (header + companion), suppression during companion drag, position persistence across displays and resolution changes.
- VoiceOver labels/order, keyboard navigation, Reduce Motion (static), Increase Contrast.
- Pet on/off, size/motion/accent settings.
- Fullscreen auxiliary behavior.
- No focus stealing or activation of the main app.
- Performance: no regression in capture smoothness or memory during long meetings.

Update or add lightweight unit tests for any new presentation projection logic.

### Phase 5: Documentation & Cleanup
- Update `docs/design-guidelines.md` (Floating caption overlay section).
- Light refresh of `docs/user-guide.md` if descriptions of the floating UI change.
- Remove temporary `.claude-design/` artifacts.
- Consider adding a short note in the plan directory or journal.

## Component / View Changes (high level)

**FloatingCaptionView**
- New two-zone root layout.
- New or heavily revised status zone view containing REC + time + controls.
- Refined transcript zone.
- Entrance transition modifier (conditional on emphasized flag).
- Stronger contrast and material decisions for top zone.

**FloatingCaptionPresentation (minor)**
- Optional `isEmphasized` or similar for first post-start frame (derive in coordinator if possible to avoid model changes).

**Coordinator**
- One-time entrance state management.
- First delivery after entering capturing state triggers emphasis.
- All other responsibilities unchanged.

## Required UI States to Support
- Default active capture (settled comfortable state)
- Entrance/emphasized first frame (stronger top zone)
- Paused (while still visible — though hide usually happens quickly)
- Controls enabled/disabled per `SignalGatePresentation`
- Pet visible / hidden
- Reduce Motion variant of entrance
- High contrast / increased contrast variant

## Accessibility Checklist
- [ ] All controls have clear VoiceOver labels (Pause, Stop & Process, Show Meeting Details)
- [ ] Logical traversal order (header/status first, then transcript is non-interactive)
- [ ] Drag handle has accessibility hint
- [ ] Focus rings / states visible where applicable
- [ ] Panel absent from accessibility tree when hidden or suppressed
- [ ] Reduce Motion respected (no animation on entrance)
- [ ] Color not used alone (REC dot + text + mint rail)

## Testing & Validation Checklist
- Existing focused presentation and pet tests still pass.
- New entrance behavior covered in presentation projection tests.
- Full real-device matrix listed in Phase 4.
- Screen share / screenshot manual verification.
- Multi-display clamp + persistence regression check.
- Long-running capture with pet on/off.

## Design Tokens / Guidelines Alignment
- Use existing mint accent, red for recording, deep graphite.
- Respect 4 pt rhythm, 28 pt minimum control size.
- Update design-guidelines.md "Floating caption overlay" description after implementation.
- Keep "Dark Broadcast Studio" language.

## Risks & Mitigations
- Risk: Increased visual weight makes panel feel heavier in screen shares. → Mitigate by settling quickly and using refined (not loud) accents.
- Risk: Height increase from comfortable treatment breaks placement math. → Mitigate by measuring and adjusting clamp/fallback logic only if necessary (prefer not to).
- Risk: Entrance treatment feels jarring. → One-shot, short duration, Reduce-Motion safe; user testing will validate.
- Risk: Breaking nonactivation or drag contracts. → Phase 1 + continuous manual verification on every change.

## References
## Implementation Progress (as of latest edits)

- Phase 1 (Contract & Hook): Complete. One-shot emphasizeEntrance flag wired in coordinator and passed to view. All must-keep behaviors preserved.
- Phase 2 (Visual): Two-zone layout implemented. Stronger top status zone with prominent REC, left mint rail, regularMaterial, drag affordance on top zone. Comfortable transcript zone. Entrance effect (scale + stronger mint border/rail when emphasized, Reduce Motion safe).
- Dead code: Old FloatingCaptionHeaderView removed.
- Build: Succeeds cleanly.
- Remaining for full completion: Real-device validation (Phase 4), minor elapsed time wiring if desired, documentation updates.

**Exit criteria for this plan:** All must-keep invariants hold, real-device start-recording visibility and usability trials pass, and the panel feels like a high-signal professional tool rather than something users want to hide.

Generated from approved design-lab exploration (ck:ask + design-lab skill).