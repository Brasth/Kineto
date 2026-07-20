---
title: Kineto Design Guidelines
status: proposed-for-wireframe-review
updated: 2026-07-18
---

# Kineto Design Guidelines

## Direction: Dark Broadcast Studio

Kineto is a focused, dark-first meeting workspace with a luminous mint signal accent. Meeting content dominates; the live state feels active without becoming a telemetry dashboard. The memorable element remains a **signal rail** connecting capture, transcription, translation, and post-stop evidence validation.

Use native macOS controls, behaviors, typography, and adaptive materials. Dark is the authored reference appearance; light mode remains fully supported. The HTML wireframe approximates these decisions for review and is not a source of hardcoded SwiftUI values.

## Product principles

1. **Trust is visible:** always show whether capture is active, where processing occurs, and whether raw audio is retained.
2. **Source before derivation:** original transcript is visually primary; machine translation and summary are labeled and subordinate.
3. **One primary action:** each state has one dominant next step—download, start, stop, or export.
4. **Progressive disclosure:** routine meeting flow stays simple; model, storage, and diagnostics detail lives in secondary views.
5. **Native over novel:** use platform pickers, menus, toolbars, sheets, alerts, keyboard conventions, and accessibility semantics.

## Information architecture

```text
Home / Library
├── New Meeting
├── Recent meetings
├── Model & Language
└── Privacy & Storage

Contextual meeting flow
Home → New Meeting → Live Focus → Processing → Summary
             └── Blocked capability setup only when required
```

- Home and Summary show the library sidebar; Live, Processing, and blocked setup hide it.
- Live uses the full canvas for transcript plus an optional trailing capture-health inspector.
- Summary restores the library and offers a resizable/collapsible trailing evidence inspector.
- At compact widths, hide inspectors before collapsing the library.
- Never create nested scrolling around the transcript; transcript is the primary scroll region.

## Core screens

### Home and contextual setup

- Home starts with a ready-to-capture meeting card, source, summary language, raw-audio policy, and recent meetings.
- Do not show a permanent checklist of already-satisfied permissions and models.
- Open focused setup only for an unavailable permission, model, translation pair, or language asset.
- A blocked-capability view states the cause, retained progress, exact recovery action, and safe dismissal behavior.
- Microphone denial does not block system audio.
- Put participant-notification language beside the manual Start button.
- Raw-audio retention status must be explicit before capture starts.

### Live Meeting

- Persistent recording mark, elapsed time, effective selected-source boundary, and local-processing badge.
- Original segments use normal foreground text; translations use secondary text plus an accent rule.
- Volatile ASR is visually softer and replaced in place; finalized text becomes stable.
- Speaker labels are `You` and `Selected Source`; use `Meeting` only after source-isolation proof and never imply participant recognition.
- Live meeting controls: Pause, Stop & Process, and separately confirmed Stop & Delete. The active caption overlay conditionally adds Pause, Stop & Process, and Show Meeting Details; destructive deletion remains separated and labeled.
- Capture-health inspector shows effective source scope, source tracks, translation backlog, and resource state without private content.
- The floating caption overlay is a linked pair of automatic nonactivating `NSPanel`s projected only when `AppModel.capturePresentationMode` is `.floating` during active capture: a compact transcript subtitle bar follows below a tight transparent decorative companion AppKit child panel. They share one displayed placement, reset action, display clamp, lifecycle, and screenshot/screen-share behavior; only the transcript anchor persists. Successful Start Meeting enters floating mode automatically, and the app reversibly orders every identified main `WindowGroup` window out rather than closing it. When permitted by the canonical signal-gate presentation, the subtitle bar shows compact **Pause**, **Stop & Process**, and **Show Meeting Details** controls. Show Meeting Details reveals the existing live meeting window, not a new detail route or second panel. Keep the controls separate from the accessible header drag region; caption text remains noninteractive. Pointer-dragging the visible companion is the primary move affordance: its frame remains under the pointer and the subtitle panel/frame remain linked, while the caption surface and controls are visually suppressed and inaccessible for the held companion drag, then restore immediately on release. The transcript header remains the accessible fallback move handle; header-initiated dragging keeps the caption surface visible.
- Hide the full overlay, including its controls, immediately on Pause, Stop & Process, Show Meeting Details, source loss, or the transition to processing; every non-capturing phase returns to `.mainWindow` and reveals the existing main window through reversible ordering. The hidden companion and hidden controls must not be invisible interactive targets. Resume leaves the main window shown; the live meeting's explicit **Use Floating Captions** control is the only active-capture re-entry path. The panels may be visible in screenshots or screen sharing; do not claim otherwise.
- **Pet Mode** is optional and off by default. Its global configuration lives in Kineto Settings rather than meeting Preflight. When enabled, it shows an original pixel-art companion—with five built-in themes, Signal Cat, Orbit Fox, Beacon Frog, Night Owl, and Meadow Rabbit—in the child panel above the transcript during active capture. It is decorative except for its pointer move affordance and receives non-content `FloatingCaptionPetState` plus persisted appearance, size, motion, and opaque canonical sRGB accent preferences. Settings persist as a versioned Codable snapshot with independent per-field fallback for missing or invalid values; colors normalize to opaque canonical sRGB, and a failed picker conversion retains the prior valid accent. It never reads, reveals, retains, logs, or reacts to caption/transcript text, translations, audio, speaker identity, source application/window identity, or sentiment. It has no independent placement persistence, capture data, transcript data, or work; it accepts neither focus nor content interaction and follows the transcript panel's normal screenshot and screen-share visibility. Its arbitrary accent applies only to its pixel primitives, never to recording, warning, transcript, translation, focus, or action semantics.

### Processing

- Stopping rejects callbacks, drains/flushes bounded ASR work, and seals the source transcript before summary work begins.
- Show translation finalization, summary generation, and extractive evidence validation as distinct stages.
- Allow summary cancellation without deleting the authoritative transcript or finalized translations.
- Failure offers idempotent retry or transcript-only completion; it never reopens capture or invents a completed result.

### Summary

- Summary language is the meeting-selected English or Vietnamese locale.
- Overview, decisions, and action items each link to original segment IDs plus supporting spans.
- Evidence inspector shows timestamp, track label, spoken language, highlighted original support, and labeled translation when present.
- Unknown or unsupported owner/date/amount stays explicitly unknown; UI never converts absence into an assignment.

## Visual system

### Typography

Use San Francisco through semantic SwiftUI text styles. Do not bundle display fonts.

- Window/section title: `.title2` or platform-equivalent, semibold.
- Main document heading: `.title`, semibold, tight but system-controlled tracking.
- Transcript: `.body`, regular, comfortable line spacing.
- Speaker/field label: `.caption`, medium or semibold.
- Timestamp/timer: monospaced digits; avoid layout movement.
- Support Dynamic Type and never encode state by font size alone.

### Color and materials

Use semantic platform colors and materials; support light appearance, but author and validate the dark capture experience first.

- Dark window/sidebar/surface roles use deep green-black graphite with clear separators.
- Primary text uses high-contrast label color; secondary metadata uses secondary-label color.
- Signal accent uses luminous mint for tint, focus, active pipeline state, waveform texture, and translation rule.
- Recording/destructive uses system red plus label/icon; never color alone.
- Warning uses system orange plus recovery text.
- A very subtle signal/waveform texture may appear only in Live Focus and must disappear with Reduce Transparency or increased contrast.
- Do not use decorative gradients, translucent transcript cards, or multiple brand accents.

### Spacing and shape

- 4 pt base rhythm; common gaps 8, 12, 16, 24, and 32 pt.
- Content gutters: 20–28 pt depending on window width.
- Floating caption sizing: 576 pt default width, 68 pt minimum content height, and 14 pt vertical padding for the compact, modestly narrower and taller subtitle treatment.
- Compact floating-control hit regions are at least 28 pt on macOS, use standard system control sizes, and remain distinct from the header and companion drag regions.
- Corners: system defaults; cards approximately 8–10 pt where grouping needs a boundary.
- Prefer separators and material changes over shadows. Reserve elevation for floating recording controls and sheets.

## Components

- **Signal rail:** four textual states with dot and connector; color and fill indicate progress.
- **Blocked capability card:** shown only for a missing requirement; includes cause, progress, retry, and safe dismissal.
- **Processing stages:** transcript, translation, and summary/evidence status without implying completion early.
- **Utterance:** timestamp, source label, spoken-language tag, original text, optional translated text.
- **Evidence link:** source count or timestamp button; keyboard and VoiceOver reachable.
- **Capture badge:** persistent recording/local/retention state, not a transient toast.
- **Floating caption overlay:** a linked pair of automatic nonactivating panels during active capture only, projected by `AppModel.capturePresentationMode == .floating`: a compact transcript subtitle bar follows below a tight transparent decorative companion AppKit child panel. The pair shares one anchor, display clamp, lifecycle, menu-bar Reset Caption Position action, and normal screenshot/screen-share visibility; only the transcript anchor persists. Successful Start Meeting enters floating mode and reversibly orders identified main `WindowGroup` windows out; returning to `.mainWindow` hides the pair and reveals the existing main window without closing it. It receives the canonical signal-gate presentation and conditionally exposes compact Pause, Stop & Process, and Show Meeting Details controls. Show Meeting Details reveals the existing live meeting window rather than opening a new route or second panel. Controls are separate from the header drag region; caption text is noninteractive. Companion dragging keeps linked geometry alive but suppresses and makes the subtitle surface and controls inaccessible until release; header dragging remains visible as the accessible fallback. Pause, Stop & Process, Show Meeting Details, source loss, and processing hide the full overlay. Resume leaves the main window shown; only Use Floating Captions from the live meeting explicitly re-enters floating mode.
- **Pet Mode:** optional, default-off, original pixel-art companion with five immutable built-in themes—Signal Cat, Orbit Fox, Beacon Frog, Night Owl, and Meadow Rabbit—controlled from global Kineto Settings. It is active-capture-only and decorative except for its pointer move affordance, and receives non-content `FloatingCaptionPetState` plus persisted appearance, size, motion, and opaque canonical sRGB accent preferences. Settings persist as a versioned Codable snapshot with per-field fallback; colors normalize to opaque canonical sRGB, and failed color-picker conversion retains the prior valid accent. It has no independent placement persistence, capture or transcript data, caption, translation, audio, speaker, source-identity, or sentiment input and no data retention, logging, independent work, focus, or content interaction. Its arbitrary accent applies only to companion pixels, never to recording, warning, transcript, translation, focus, or action semantics.
- **Signal Gate menu-bar extra:** capture and paused native status surface with a distinct monochrome phase glyph, generic state copy, local-processing and raw-audio facts, guarded in-session controls including paused Resume, and the accessible Reset Caption Position action; no caption content, source identity, setup, or destructive deletion actions.
- **Meeting package row:** title, date/duration, and language metadata; no content preview in notifications.

## Interaction and motion

- State feedback begins immediately; operations over 300 ms show determinate progress when available.
- Use native transitions only when they explain state change; 150–250 ms target for custom micro-interactions.
- Volatile-to-final transcript replacement may crossfade without moving the reading position.
- All motion must remain interruptible and honor Reduce Motion.
- Pet Mode may use one non-looping transform/opacity transition of 200 ms or less to explain a state change. With Reduce Motion it is static.
- Provide menu commands and keyboard shortcuts for New Meeting, Start, Pause/Resume, Stop & Process, Add Marker, Export, and the accessible Reset Caption Position action where safe.
- Stop & Delete always requires a confirmation dialog describing exactly what is removed.

## Accessibility

- Full keyboard traversal with visible focus and logical order.
- VoiceOver labels include control purpose and current capture/permission state; Pause, Stop & Process, Show Meeting Details, and Use Floating Captions have clear labels and logical traversal. Overlay controls are absent from the accessibility tree whenever the overlay is hidden or drag-suppressed; Use Floating Captions exists only in the live meeting while active capture is available. The menu-bar Reset Caption Position action must be discoverable and operable.
- Announce finalized segments and errors politely; do not continuously announce volatile tokens.
- Never depend on teal/red/orange alone—pair color with text, icon shape, or both.
- Preserve readable transcript width at larger text sizes; wrap rather than truncate source content.
- Verify Increase Contrast, Reduce Transparency, Reduce Motion, dark mode, and largest practical text size.
- Live transcript and recording controls remain usable when the optional inspector is hidden.
- Real-device validation remains open: on physical Macs, verify each compact overlay control has its own ≥28 pt hit area, invokes without activating the nonactivating panel, and is correctly announced and ordered by VoiceOver; verify Start Meeting automatically enters floating mode, all identified main `WindowGroup` windows are reversibly ordered out (not closed), and Use Floating Captions is available only in the active live meeting. Verify Show Meeting Details reveals the current live meeting window without a new route or panel. Trigger Pause and Stop & Process, source loss, and processing and confirm the entire overlay, controls, and companion hide immediately with the main window shown; Resume must leave the main window shown until explicit Use Floating Captions re-entry. Drag the visible companion child panel and verify it remains under the pointer while the subtitle panel/frame stays linked, its caption surface and controls are inaccessible only for the held drag, and that surface restores immediately on release; separately, drag the visible header outside any companion drag and verify the caption surface remains visible. Reset from the menu; verify no hidden-companion or hidden-control interaction; clamp and restore across displays; confirm Reduce Motion, nonactivation, fullscreen Zoom/Meet/Teams behavior, and normal screen-sharing visibility.

## Privacy copy rules

- Say **“processed on this Mac”**, not “100% private.”
- Say **“raw audio off/on for this meeting”**, not a vague “private mode.”
- Label mixed application/system audio **“Selected Source”** and disclose browser/application-wide scope; use **“Meeting”** only after isolation proof.
- Require explicit per-session acknowledgment that the operator informed participants; do not imply Zoom/Meet/Teams recording indicators are active.
- Disclose that explicit exports are plaintext copies outside Kineto’s deletion boundary.

## Wireframe review artifact

Open `plans/design/kineto-wireframes.html`. Review five states in dark and light appearance:

1. Contextual blocked setup
2. Home / ready meeting
3. Live Focus without library sidebar
4. Post-stop Processing
5. Evidence-linked Summary with library and inspector

## Acceptance checklist

- Manual start and persistent capture indicator are unmistakable.
- Original text remains visually authoritative over translation and summary.
- EN/VI code-switching is readable without creating separate meeting modes.
- Local processing and raw-audio retention are visible before and during capture.
- Effective source scope and explicit per-session participant-notification acknowledgment appear before Start and remain visible during capture.
- Pause, Stop & Process, and Show Meeting Details remain reachable from the active caption overlay when permitted, with keyboard and assistive technology access; Start Meeting automatically enters floating mode with reversible main-window ordering; paused Resume returns to the live meeting/menu bar with the main window shown, and Use Floating Captions is an explicit active-capture re-entry; destructive Stop & Delete stays separately confirmed.
- Window remains usable at compact width without horizontal scrolling or hidden primary controls.
